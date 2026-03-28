//
//  PartnerRelayDisplaySession.swift
//  FootballScanningAI
//
//  Display-side relay: HTTP create session → join code → WebSocket (display role).
//  Reusable for any partner activity; wire `onCoachPairingChanged` into the activity’s session/pairing model.
//

import Combine
import Foundation

/// Owns **display** relay session state: join code, socket lifecycle, coach paired (from `control.peer_joined` / `peer_left`).
/// Conforms to ``PartnerRelayDisplayControlling`` for a shared adoption pattern across partner activities.
/// Message sends currently use `TwoMinuteMessage` + `WebSocketEnvelope` (same as Multipeer path) where applicable.
final class PartnerRelayDisplaySession: ObservableObject {
    /// Join code from `POST /v1/sessions` (show on display for coach entry).
    @Published private(set) var joinCode: String?
    /// Relay WebSocket lifecycle (searching … connected … disconnected).
    @Published private(set) var socketConnectionState: ConnectionState = .disconnected
    /// `true` after `control.peer_joined`, `false` after `peer_left` or socket disconnect.
    @Published private(set) var isCoachPaired: Bool = false

    private var transport: WebSocketRemoteTransport?

    /// Mirror into the activity’s pairing flag (e.g. `TwoMinuteSessionManager.setConnected`).
    var onCoachPairingChanged: ((Bool) -> Void)?

    /// True when the relay WebSocket is fully established (not just in-flight).
    var isRelaySocketConnected: Bool {
        #if DEBUG
        socketConnectionState == .connected
        #else
        false
        #endif
    }

    #if DEBUG
    /// Whether a WebSocket transport instance exists (for diagnostics).
    var hasRelayTransportForDiagnostics: Bool { transport != nil }
    #endif

    /// True when an in-flight or live relay exists (reuse same join code across activity transitions).
    private var hasActiveRelayInFlightOrLive: Bool {
        #if DEBUG
        switch socketConnectionState {
        case .connected, .connecting, .searching: return true
        case .disconnected: return false
        }
        #else
        return false
        #endif
    }

    /// Starts HTTP create + WebSocket connect for display. No-op in non-DEBUG builds.
    func startDisplaySession() async {
        #if DEBUG
        print("[RelayWS-DEBUG] PartnerRelayDisplaySession.startDisplaySession entered")
        do {
            let created = try await WebSocketSessionAPI.createSession()
            await MainActor.run {
                joinCode = created.joinCode
            }
            print("[RelayWS-DEBUG] session creation OK sessionId=\(created.sessionId)")
            print("[RelayWS-DEBUG] joinCode=\(created.joinCode) (share with coach for relay join)")
            print("[RelayWS-DEBUG] wsUrl(base)=\(created.wsUrl) expiresAt=\(created.expiresAt ?? "nil")")

            let wsURL = try created.webSocketURLForDisplay()
            print("[RelayWS-DEBUG] WebSocket URL (with query)=\(wsURL.absoluteString)")

            let config = WebSocketSessionConfig(url: wsURL, sessionId: created.sessionId, authToken: created.displayToken)
            let newTransport = WebSocketRemoteTransport(config: config)

            newTransport.onConnectionStateChanged = { [weak self] state in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.applySocketConnectionState(state)
                }
                switch state {
                case .searching:
                    print("[RelayWS-DEBUG] connection state: searching")
                case .connecting:
                    print("[RelayWS-DEBUG] connection state: connecting")
                case .connected:
                    print("[RelayWS-DEBUG] connection state: connected")
                case .disconnected:
                    print("[RelayWS-DEBUG] connection state: disconnected")
                }
            }
            newTransport.onRawTextReceived = { [weak self] text in
                print("[RelayWS-DEBUG] received raw: \(text)")
                self?.handleRawRelayText(text)
            }

            await MainActor.run {
                transport = newTransport
                print("[RelayWS-DEBUG] calling connect()")
                newTransport.connect()
            }
        } catch {
            print("[RelayWS-DEBUG] relay session/WebSocket setup failed: \(error)")
            await MainActor.run {
                joinCode = nil
                transport = nil
            }
        }
        #endif
    }

    /// Reuses an existing relay session when we already have a join code and transport (training session pairing).
    /// Call instead of ``startDisplaySession()`` when moving to another partner activity in the same run.
    ///
    /// **Important:** Reuse while the socket is still **connecting** or **searching**, not only `.connected`.
    /// Otherwise a fast activity switch can POST a second `/v1/sessions` and show a new join code while the coach
    /// is still on the first code.
    func startDisplaySessionIfNeeded() async {
        #if DEBUG
        if let t = transport, joinCode != nil {
            if hasActiveRelayInFlightOrLive {
                print("[RelayWS-DEBUG] PartnerRelayDisplaySession.startDisplaySessionIfNeeded — reusing active relay (socket=\(socketConnectionState.rawValue), same join code)")
                PartnerPersistDebug.log("startDisplaySessionIfNeeded → reuse existing relay (socket active/in-flight)")
                return
            }
            if socketConnectionState == .disconnected {
                await MainActor.run {
                    print("[RelayWS-DEBUG] PartnerRelayDisplaySession.startDisplaySessionIfNeeded — reconnecting existing transport (same join code, was disconnected)")
                    t.connect()
                    PartnerPersistDebug.log("startDisplaySessionIfNeeded → reconnect existing transport (was disconnected)")
                }
                return
            }
        }
        #if DEBUG
        if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
            print("[RelayWS-DEBUG] NEW /v1/sessions while partner training active — old transport/joinCode missing (transport=\(transport != nil) joinCode=\(joinCode ?? "nil")). Coach must use the NEW code on the display.")
        }
        #endif
        PartnerPersistDebug.log("startDisplaySessionIfNeeded → create new relay session (HTTP + WebSocket)")
        await startDisplaySession()
        #endif
    }

    /// App moved to background (springboard / app switcher). Disconnect socket but **keep** `joinCode` and `transport`
    /// so ``startDisplaySessionIfNeeded()`` can reconnect without a new HTTP session.
    func suspendForAppBackground() {
        #if DEBUG
        print("[RelayWS-DEBUG] PartnerRelayDisplaySession.suspendForAppBackground — disconnect socket; keep joinCode=\(joinCode ?? "nil")")
        transport?.disconnect()
        #endif
    }

    /// Disconnects socket and clears relay UI state.
    func tearDown() {
        #if DEBUG
        transport?.disconnect()
        transport = nil
        joinCode = nil
        socketConnectionState = .disconnected
        isCoachPaired = false
        onCoachPairingChanged?(false)
        #endif
    }

    /// Sends a message when display relay is active (e.g. session ended). Safe no-op if not connected.
    func sendTwoMinuteMessage(_ message: TwoMinuteMessage) {
        sendTwoMinuteMessage(message, completion: nil)
    }

    /// - Parameter completion: Called on the main queue after the send attempt (or immediately if no transport).
    func sendTwoMinuteMessage(_ message: TwoMinuteMessage, completion: (@Sendable () -> Void)?) {
        #if DEBUG
        guard let transport = transport else {
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
            return
        }
        transport.send(message, completion: completion)
        #else
        if let completion {
            DispatchQueue.main.async(execute: completion)
        }
        #endif
    }

    #if DEBUG
    @MainActor
    private func applySocketConnectionState(_ state: ConnectionState) {
        socketConnectionState = state
        if state == .disconnected {
            isCoachPaired = false
            onCoachPairingChanged?(false)
        }
    }

    private func handleRawRelayText(_ text: String) {
        if text.contains("peer_joined") {
            Task { @MainActor in
                isCoachPaired = true
                onCoachPairingChanged?(true)
            }
        }
        if text.contains("peer_left") {
            Task { @MainActor in
                isCoachPaired = false
                onCoachPairingChanged?(false)
            }
        }
    }
    #endif
}
