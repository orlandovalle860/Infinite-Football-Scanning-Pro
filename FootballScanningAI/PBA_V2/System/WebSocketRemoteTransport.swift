//
//  WebSocketRemoteTransport.swift
//  FootballScanningAI
//
//  Scaffolding: `RemoteTransport` over URLSessionWebSocketTask. Not wired into the app yet.
//

import Foundation

final class WebSocketRemoteTransport: NSObject, RemoteTransport {
    /// Retained for same-session reconnect (fresh WebSocket task without HTTP re-join).
    let sessionConfig: WebSocketSessionConfig
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var urlSession: URLSession!
    private var webSocketTask: URLSessionWebSocketTask?
    private var isReceiveLoopActive = false
    /// Bumped on each connect/disconnect so stale cancelled-task callbacks cannot clobber a newer socket.
    private var connectionGeneration: UInt64 = 0
    /// Detects half-open / zombie sockets (common on hotspot walk-away) when URLSession still reports connected.
    private var keepaliveTimer: Timer?
    private static let keepaliveIntervalSeconds: TimeInterval = 5.0

    private var _connectionState: ConnectionState = .disconnected {
        didSet {
            if _connectionState != oldValue {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.onConnectionStateChanged?(self._connectionState)
                }
            }
        }
    }

    var connectionState: ConnectionState { _connectionState }

    var onConnectionStateChanged: ((ConnectionState) -> Void)?
    var onTwoMinuteMessageReceived: ((TwoMinuteMessage) -> Void)?
    /// Called with raw UTF-8 text for every incoming string frame (e.g. relay `control.*` JSON). Optional; used for debug logging.
    var onRawTextReceived: ((String) -> Void)?

    /// Creates a transport for the given relay `WebSocketSessionConfig` (URL, `sessionId`, optional token).
    init(config: WebSocketSessionConfig) {
        self.sessionConfig = config
        super.init()
        let configuration = URLSessionConfiguration.default
        // Do NOT set a short timeoutIntervalForRequest/Resource — those apply to the
        // long-lived WebSocket and will idle-kill a healthy Partner link (field: -1001
        // ~12–20s after connect → DISPLAY_ALREADY_CONNECTED reconnect loop).
        // Fail fast when offline instead of parking on waitsForConnectivity.
        configuration.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }

    func connect() {
        disconnectPreparingForReconnect()
        connectionGeneration &+= 1
        let generation = connectionGeneration
        _connectionState = .searching

        var request = URLRequest(url: sessionConfig.url)
        request.setValue(sessionConfig.sessionId, forHTTPHeaderField: "X-Session-Id")
        if let token = sessionConfig.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        _connectionState = .connecting
        task.resume()
        startReceiveLoop(generation: generation)
    }

    func disconnect() {
        stopKeepalive()
        disconnectPreparingForReconnect()
        _connectionState = .disconnected
    }

    /// Cancels the active task without publishing disconnected (used at the start of ``connect()``).
    private func disconnectPreparingForReconnect() {
        stopKeepalive()
        isReceiveLoopActive = false
        connectionGeneration &+= 1
        let old = webSocketTask
        webSocketTask = nil
        old?.cancel(with: .goingAway, reason: nil)
    }

    private func startKeepalive(generation: UInt64) {
        stopKeepalive()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.keepaliveIntervalSeconds, repeats: true) { [weak self] _ in
            self?.sendKeepalivePing(expectedGeneration: generation)
        }
        // Partner drills often run under tracking RunLoop modes; default timer mode can stall.
        RunLoop.main.add(timer, forMode: .common)
        keepaliveTimer = timer
        // Immediate probe so a zombie does not wait a full interval after "connected".
        sendKeepalivePing(expectedGeneration: generation)
    }

    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }

    private func sendKeepalivePing(expectedGeneration: UInt64) {
        guard connectionGeneration == expectedGeneration,
              _connectionState == .connected,
              let task = webSocketTask else { return }
        task.sendPing { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.connectionGeneration == expectedGeneration, self.webSocketTask === task else { return }
                guard let error else { return }
                HotspotBaselineLog.emit(
                    "WS keepalive_ping_fail sessionSuffix=\(HotspotBaselineLog.sessionSuffix(self.sessionConfig.sessionId)) error=\(error.localizedDescription)"
                )
                self.stopKeepalive()
                self.isReceiveLoopActive = false
                self.webSocketTask = nil
                task.cancel(with: .goingAway, reason: nil)
                self._connectionState = .disconnected
            }
        }
    }

    func send(_ message: TwoMinuteMessage) {
        send(message, completion: nil)
    }

    /// - Parameter completion: Called on the main queue after the send attempt finishes (success or failure).
    func send(_ message: TwoMinuteMessage, completion: (@Sendable () -> Void)?) {
        let nextRepIndex: Int? = {
            if case .nextRep(let repIndex) = message { return repIndex }
            return nil
        }()
        let sessionSuffix = HotspotBaselineLog.sessionSuffix(sessionConfig.sessionId)
        guard let task = webSocketTask else {
            if let repIndex = nextRepIndex {
                HotspotBaselineLog.emit(
                    "COACH ws_send fail kind=nextRep reason=nil_task repIndex=\(repIndex) sessionSuffix=\(sessionSuffix)"
                )
            }
            DispatchQueue.main.async { [weak self] in
                self?._connectionState = .disconnected
                completion?()
            }
            return
        }
        let generation = connectionGeneration
        do {
            let envelope = try WebSocketEnvelope(sessionId: sessionConfig.sessionId, message: message)
            let data = try encoder.encode(envelope)
            guard let string = String(data: data, encoding: .utf8) else {
                if let repIndex = nextRepIndex {
                    HotspotBaselineLog.emit(
                        "COACH ws_send fail kind=nextRep reason=utf8_encode repIndex=\(repIndex) sessionSuffix=\(sessionSuffix)"
                    )
                }
                DispatchQueue.main.async { completion?() }
                return
            }
            if let repIndex = nextRepIndex {
                HotspotBaselineLog.emit(
                    "COACH ws_send attempt kind=nextRep repIndex=\(repIndex) sessionSuffix=\(sessionSuffix)"
                )
            }
            task.send(.string(string)) { [weak self] error in
                DispatchQueue.main.async {
                    if let repIndex = nextRepIndex {
                        if error != nil {
                            HotspotBaselineLog.emit(
                                "COACH ws_send fail kind=nextRep reason=task_send_error repIndex=\(repIndex) sessionSuffix=\(sessionSuffix)"
                            )
                        } else {
                            HotspotBaselineLog.emit(
                                "COACH ws_send ok kind=nextRep repIndex=\(repIndex) sessionSuffix=\(sessionSuffix)"
                            )
                        }
                    }
                    if error != nil {
                        self?.handleSendFailure(expectedGeneration: generation, task: task)
                    }
                    completion?()
                }
            }
        } catch {
            if let repIndex = nextRepIndex {
                HotspotBaselineLog.emit(
                    "COACH ws_send fail kind=nextRep reason=encode_throw repIndex=\(repIndex) sessionSuffix=\(sessionSuffix)"
                )
            }
            DispatchQueue.main.async { [weak self] in
                self?.handleSendFailure(expectedGeneration: generation, task: task)
                completion?()
            }
        }
    }

    private func handleSendFailure(expectedGeneration: UInt64, task: URLSessionWebSocketTask) {
        guard connectionGeneration == expectedGeneration, webSocketTask === task else { return }
        _connectionState = .disconnected
    }

    private func startReceiveLoop(generation: UInt64) {
        guard let task = webSocketTask else { return }
        isReceiveLoopActive = true
        receiveOnce(task: task, generation: generation)
    }

    private func receiveOnce(task: URLSessionWebSocketTask, generation: UInt64) {
        guard isReceiveLoopActive, connectionGeneration == generation, webSocketTask === task else { return }
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                guard self.connectionGeneration == generation, self.webSocketTask === task else { return }
                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    self.handleIncomingData(data)
                @unknown default:
                    break
                }
                if self.isReceiveLoopActive, self.connectionGeneration == generation, self.webSocketTask === task {
                    self.receiveOnce(task: task, generation: generation)
                }
            case .failure:
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    guard self.connectionGeneration == generation, self.webSocketTask === task else { return }
                    self._connectionState = .disconnected
                }
            }
        }
    }

    private func handleIncomingText(_ text: String) {
        onRawTextReceived?(text)
        guard let data = text.data(using: .utf8) else { return }
        handleIncomingData(data)
    }

    private func handleIncomingData(_ data: Data) {
        if let envelope = try? decoder.decode(WebSocketEnvelope.self, from: data),
           envelope.type == "twoMinute",
           let msg = try? decoder.decode(TwoMinuteMessage.self, from: envelope.payload) {
            deliverTwoMinuteMessage(msg)
            return
        }
        if let direct = try? decoder.decode(TwoMinuteMessage.self, from: data) {
            deliverTwoMinuteMessage(direct)
        }
    }

    /// Same delivery path as Multipeer (`ConnectionManager`): notify observers, then transport callback.
    private func deliverTwoMinuteMessage(_ message: TwoMinuteMessage) {
        if case .nextRep(let repIndex) = message {
            HotspotBaselineLog.emit(
                "WS nextRep_frame_decoded repIndex=\(repIndex) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(sessionConfig.sessionId))"
            )
        }
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: .twoMinuteMessageReceived, object: message)
            self?.onTwoMinuteMessageReceived?(message)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketRemoteTransport: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard self.webSocketTask === webSocketTask else { return }
        _connectionState = .connected
        startKeepalive(generation: connectionGeneration)
    }
}

// MARK: - URLSessionTaskDelegate

extension WebSocketRemoteTransport: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Ignore completions from a cancelled prior task after a newer connect().
        guard task === webSocketTask else { return }
        if error != nil || task.state == .completed {
            _connectionState = .disconnected
        }
    }
}
