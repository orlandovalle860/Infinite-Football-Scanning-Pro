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
        }
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
        #if DEBUG
        transport?.send(message)
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
