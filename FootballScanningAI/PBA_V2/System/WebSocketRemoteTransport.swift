//
//  WebSocketRemoteTransport.swift
//  FootballScanningAI
//
//  Scaffolding: `RemoteTransport` over URLSessionWebSocketTask. Not wired into the app yet.
//

import Foundation

final class WebSocketRemoteTransport: NSObject, RemoteTransport {
    private let config: WebSocketSessionConfig
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var urlSession: URLSession!
    private var webSocketTask: URLSessionWebSocketTask?
    private var isReceiveLoopActive = false

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
        self.config = config
        super.init()
        let configuration = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }

    func connect() {
        disconnect()
        _connectionState = .searching

        var request = URLRequest(url: config.url)
        request.setValue(config.sessionId, forHTTPHeaderField: "X-Session-Id")
        if let token = config.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        _connectionState = .connecting
        task.resume()
        startReceiveLoop()
    }

    func disconnect() {
        isReceiveLoopActive = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        _connectionState = .disconnected
    }

    func send(_ message: TwoMinuteMessage) {
        send(message, completion: nil)
    }

    /// - Parameter completion: Called on the main queue after the send attempt finishes (success or failure).
    func send(_ message: TwoMinuteMessage, completion: (@Sendable () -> Void)?) {
        guard let task = webSocketTask else {
            DispatchQueue.main.async { [weak self] in
                self?._connectionState = .disconnected
                completion?()
            }
            return
        }
        do {
            let envelope = try WebSocketEnvelope(sessionId: config.sessionId, message: message)
            let data = try encoder.encode(envelope)
            guard let string = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion?() }
                return
            }
            task.send(.string(string)) { [weak self] error in
                DispatchQueue.main.async {
                    if error != nil {
                        self?.handleSendFailure()
                    }
                    completion?()
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.handleSendFailure()
                completion?()
            }
        }
    }

    private func handleSendFailure() {
        _connectionState = .disconnected
    }

    private func startReceiveLoop() {
        guard let task = webSocketTask else { return }
        isReceiveLoopActive = true
        receiveOnce(task: task)
    }

    private func receiveOnce(task: URLSessionWebSocketTask) {
        guard isReceiveLoopActive else { return }
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    self.handleIncomingData(data)
                @unknown default:
                    break
                }
                if self.isReceiveLoopActive, self.webSocketTask === task {
                    self.receiveOnce(task: task)
                }
            case .failure:
                DispatchQueue.main.async { [weak self] in
                    self?._connectionState = .disconnected
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
        _connectionState = .connected
    }
}

// MARK: - URLSessionTaskDelegate

extension WebSocketRemoteTransport: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil || task.state == .completed {
            _connectionState = .disconnected
        }
    }
}
