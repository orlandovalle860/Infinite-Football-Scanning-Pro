//
//  PartnerRelayDisplaySession.swift
//  FootballScanningAI
//
//  Display-side relay: HTTP create session → join code → WebSocket (display role).
//  Reusable for any partner activity; wire `onCoachPairingChanged` into the activity’s session/pairing model.
//

import Combine
import Foundation
import UIKit

/// Owns **display** relay session state: join code, socket lifecycle, coach paired (from `control.peer_joined` / `peer_left`).
/// Conforms to ``PartnerRelayDisplayControlling`` for a shared adoption pattern across partner activities.
/// Message sends currently use `TwoMinuteMessage` + `WebSocketEnvelope` (same as Multipeer path) where applicable.
final class PartnerRelayDisplaySession: ObservableObject {
    /// Join code from `POST /v1/sessions` (show on display for coach entry).
    @Published private(set) var joinCode: String?
    /// Relay WebSocket lifecycle (searching … connected … disconnected).
    @Published private(set) var socketConnectionState: ConnectionState = .disconnected
    /// `true` after `control.peer_joined` or `control.ack` with `peerPresent: true`.
    /// Cleared immediately on `peer_left`, `stopHosting()`, or `tearDown()`; on socket disconnect, cleared only after a 1.5s debounce if still disconnected.
    @Published private(set) var isCoachPaired: Bool = false
    /// Relay server session id (HTTP/WebSocket config); used for reconnect checkpoint logging.
    @Published private(set) var relaySessionId: String?

    private var transport: WebSocketRemoteTransport?

    /// Used to avoid treating intentional ``tearDown()`` disconnects as unexpected drops.
    private var lastSocketStateForRecycle: ConnectionState = .disconnected
    private var relayDisconnectRecycleTask: Task<Void, Never>?
    /// Delay clearing ``isCoachPaired`` on socket drop so a hotspot blip does not restart 3–2–1 / waiting overlay.
    private var unpairedDebounceTask: Task<Void, Never>?
    private static let unpairedDebounceNanoseconds: UInt64 = 1_500_000_000
    /// Legacy/race: `DISPLAY_ALREADY_CONNECTED` should be rare after same-token relay replace; keep bounded reconnect.
    private var displayAlreadyConnectedRetryTask: Task<Void, Never>?
    private var displayAlreadyConnectedRetryCount = 0
    private static let displayAlreadyConnectedMaxRetries = 3
    private static let displayAlreadyConnectedBackoffNs: [UInt64] = [
        2_000_000_000,
        5_000_000_000,
        10_000_000_000,
    ]

    /// Mirror into the activity’s pairing flag (e.g. `TwoMinuteSessionManager.setConnected`).
    var onCoachPairingChanged: ((Bool) -> Void)?

    /// True when the relay WebSocket is fully established (not just in-flight).
    var isRelaySocketConnected: Bool {
        socketConnectionState == .connected
    }

    /// True when a display relay session was created (e.g. coach-link warm-up) and should be adopted by
    /// ``TrainingPartnerConnectionCoordinator/beginPartnerTrainingSessionIfNeeded()`` instead of tearing down.
    var hasAdoptableRelaySession: Bool {
        guard let raw = joinCode?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return false }
        return transport != nil
    }

    #if DEBUG
    /// Whether a WebSocket transport instance exists (for diagnostics).
    var hasRelayTransportForDiagnostics: Bool { transport != nil }
    #endif

    /// True when an in-flight or live relay exists (reuse same join code across activity transitions).
    private var hasActiveRelayInFlightOrLive: Bool {
        switch socketConnectionState {
        case .connected, .connecting, .searching: return true
        case .disconnected: return false
        }
    }

    /// Starts HTTP create + WebSocket connect for display.
    func startDisplaySession() async {
        #if DEBUG
        print("[RelayWS-DEBUG] PartnerRelayDisplaySession.startDisplaySession entered")
        #endif
        do {
            let created = try await WebSocketSessionAPI.createSession()
            await MainActor.run {
                joinCode = created.joinCode
                PartnerSetupLog.display("new relay room created joinSuffix=\(PartnerSetupLog.joinCodeSuffix(created.joinCode)) \(PartnerSetupLog.activityTag())")
            }
            #if DEBUG
            print("[RelayWS-DEBUG] session creation OK sessionId=\(created.sessionId)")
            print("[RelayWS-DEBUG] joinCode=\(created.joinCode) (share with coach for relay join)")
            print("[RelayWS-DEBUG] wsUrl(base)=\(created.wsUrl) expiresAt=\(created.expiresAt ?? "nil")")
            #endif

            let wsURL = try created.webSocketURLForDisplay()
            #if DEBUG
            print("[RelayWS-DEBUG] WebSocket URL (with query)=\(wsURL.absoluteString)")
            #endif

            let config = WebSocketSessionConfig(url: wsURL, sessionId: created.sessionId, authToken: created.displayToken)
            let newTransport = WebSocketRemoteTransport(config: config)

            newTransport.onConnectionStateChanged = { [weak self] state in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.applySocketConnectionState(state)
                }
                #if DEBUG
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
                #endif
            }
            newTransport.onRawTextReceived = { [weak self] text in
                #if DEBUG
                print("[RelayWS-DEBUG] received raw: \(text)")
                #endif
                self?.handleRawRelayText(text)
            }

            await MainActor.run {
                relaySessionId = created.sessionId
                TrainingPartnerConnectionCoordinator.shared.recordRelaySessionId(created.sessionId)
                transport = newTransport
                #if DEBUG
                print("[RelayWS-DEBUG] calling connect()")
                #endif
                newTransport.connect()
            }
        } catch {
            #if DEBUG
            print("[RelayWS-DEBUG] relay session/WebSocket setup failed: \(error)")
            #endif
            await MainActor.run {
                joinCode = nil
                relaySessionId = nil
                transport = nil
            }
        }
    }

    /// Reuses an existing relay session when we already have a join code and transport (training session pairing).
    /// Call instead of ``startDisplaySession()`` when moving to another partner activity in the same run.
    ///
    /// **Important:** Reuse while the socket is still **connecting** or **searching**, not only `.connected`.
    /// Otherwise a fast activity switch can POST a second `/v1/sessions` and show a new join code while the coach
    /// is still on the first code.
    func startDisplaySessionIfNeeded() async {
        if let t = transport, joinCode != nil {
            if hasActiveRelayInFlightOrLive {
                await MainActor.run {
                    PartnerSetupLog.display("reconnect preserve live relay socket=\(socketConnectionState.rawValue) joinSuffix=\(PartnerSetupLog.joinCodeSuffix(joinCode)) \(PartnerSetupLog.activityTag())")
                }
                #if DEBUG
                print("[RelayWS-DEBUG] PartnerRelayDisplaySession.startDisplaySessionIfNeeded — reusing active relay (socket=\(socketConnectionState.rawValue), same join code)")
                PartnerPersistDebug.log("startDisplaySessionIfNeeded → reuse existing relay (socket active/in-flight)")
                #endif
                return
            }
            if socketConnectionState == .disconnected {
                await MainActor.run {
                    PartnerSetupLog.display("reconnect preserve existing session socket=disconnected joinSuffix=\(PartnerSetupLog.joinCodeSuffix(joinCode)) \(PartnerSetupLog.activityTag())")
                    #if DEBUG
                    print("[RelayWS-DEBUG] PartnerRelayDisplaySession.startDisplaySessionIfNeeded — reconnecting existing transport (same join code, was disconnected)")
                    PartnerPersistDebug.log("startDisplaySessionIfNeeded → reconnect existing transport (was disconnected)")
                    #endif
                    t.connect()
                }
                return
            }
        }
        #if DEBUG
        if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
            print("[RelayWS-DEBUG] NEW /v1/sessions while partner training active — old transport/joinCode missing (transport=\(transport != nil) joinCode=\(joinCode ?? "nil")). Coach must use the NEW code on the display.")
        }
        PartnerPersistDebug.log("startDisplaySessionIfNeeded → create new relay session (HTTP + WebSocket)")
        #endif
        await startDisplaySession()
    }

    /// Stops the relay WebSocket and cancels deferred recycle work (display-side relay “host”).
    /// Does **not** clear `joinCode` / `relaySessionId`; use ``resetSession()`` for a full new session.
    func stopHosting() {
        cancelRelayDisconnectRecycleTask()
        cancelUnpairedDebounceTask()
        resetDisplayAlreadyConnectedRetryState()
        lastSocketStateForRecycle = .disconnected
        transport?.disconnect()
        socketConnectionState = .disconnected
        applyCoachUnpaired(notify: true)
    }

    /// Full relay reset: tear down local state and create a **new** HTTP session (new `relaySessionId` + join code).
    @MainActor
    func resetSession() async {
        let previousJoin = joinCode
        let previousSessionId = relaySessionId
        cancelRelayDisconnectRecycleTask()
        tearDown()
        await startDisplaySession()
        #if DEBUG
        if let j = joinCode, let p = previousJoin, !p.isEmpty, j == p {
            print("[RelayWS-DEBUG] resetSession: unexpected — join code unchanged after new POST (old=\(p) new=\(j))")
        }
        if let s = relaySessionId, let ps = previousSessionId, !ps.isEmpty, s == ps {
            print("[RelayWS-DEBUG] resetSession: unexpected — relaySessionId unchanged after new POST (old=\(ps) new=\(s))")
        }
        #endif
    }

    /// App moved to background (springboard / app switcher). Disconnect socket but **keep** `joinCode` and `transport`
    /// so ``startDisplaySessionIfNeeded()`` can reconnect without a new HTTP session.
    func suspendForAppBackground() {
        #if DEBUG
        print("[RelayWS-DEBUG] PartnerRelayDisplaySession.suspendForAppBackground — disconnect socket; keep joinCode=\(joinCode ?? "nil")")
        #endif
        transport?.disconnect()
    }

    /// Disconnects socket and clears relay UI state.
    func tearDown() {
        cancelRelayDisconnectRecycleTask()
        cancelUnpairedDebounceTask()
        resetDisplayAlreadyConnectedRetryState()
        lastSocketStateForRecycle = .disconnected
        transport?.disconnect()
        transport = nil
        joinCode = nil
        relaySessionId = nil
        socketConnectionState = .disconnected
        applyCoachUnpaired(notify: true)
    }

    func cancelRelayDisconnectRecycleTask() {
        relayDisconnectRecycleTask?.cancel()
        relayDisconnectRecycleTask = nil
    }

    private func cancelUnpairedDebounceTask() {
        if unpairedDebounceTask != nil {
            PartnerSetupLog.display("unpairedDebounce cancelled \(PartnerSetupLog.activityTag())")
        }
        unpairedDebounceTask?.cancel()
        unpairedDebounceTask = nil
    }

    @MainActor
    private func applyCoachPaired() {
        cancelUnpairedDebounceTask()
        guard !isCoachPaired else { return }
        isCoachPaired = true
        PartnerSetupLog.display("isCoachPaired false→true \(PartnerSetupLog.activityTag())")
        onCoachPairingChanged?(true)
    }

    @MainActor
    private func applyCoachUnpaired(notify: Bool) {
        cancelUnpairedDebounceTask()
        guard isCoachPaired else { return }
        isCoachPaired = false
        PartnerSetupLog.display("isCoachPaired true→false \(PartnerSetupLog.activityTag())")
        if notify {
            onCoachPairingChanged?(false)
        }
    }

    /// Tear down the expired relay and create a fresh display session (new join code).
    @MainActor
    func recycleRelaySessionForExpiredJoinCode() async {
        await resetSession()
    }

    /// Sends a message when display relay is active (e.g. session ended). Safe no-op if not connected.
    func sendTwoMinuteMessage(_ message: TwoMinuteMessage) {
        sendTwoMinuteMessage(message, completion: nil)
    }

    /// - Parameter completion: Called on the main queue after the send attempt (or immediately if no transport).
    func sendTwoMinuteMessage(_ message: TwoMinuteMessage, completion: (@Sendable () -> Void)?) {
        guard let transport = transport else {
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
            return
        }
        transport.send(message, completion: completion)
    }

    @MainActor
    private func applySocketConnectionState(_ state: ConnectionState) {
        let previous = lastSocketStateForRecycle
        let wasConnected = previous == .connected
        lastSocketStateForRecycle = state
        socketConnectionState = state
        if state == .connected || state == .disconnected, previous != state {
            PartnerSetupLog.display("socket \(previous.rawValue)→\(state.rawValue) paired=\(isCoachPaired) \(PartnerSetupLog.activityTag())")
        }
        if state == .disconnected {
            scheduleCoachUnpairedAfterTransientDisconnectIfNeeded()
            if wasConnected {
                scheduleDisplayRelayRecycleAfterUnexpectedDisconnectIfNeeded()
            }
        } else if state == .connected {
            cancelUnpairedDebounceTask()
            cancelRelayDisconnectRecycleTask()
            resetDisplayAlreadyConnectedRetryState()
            PartnerSetupLog.display(
                "snapshot sent after replacement-or-reconnect joinSuffix=\(PartnerSetupLog.joinCodeSuffix(joinCode)) \(PartnerSetupLog.activityTag())"
            )
            TrainingPartnerConnectionCoordinator.shared.broadcastPartnerSessionSnapshotFromDisplay(reason: "socket_connected")
            TrainingPartnerConnectionCoordinator.shared.rebroadcastTimedSessionActiveFromDisplayIfNeeded()
            TrainingPartnerConnectionCoordinator.shared.rebroadcastDisplayRepEngineReadyFromDisplayIfNeeded()
        }
    }

    /// Keep ``isCoachPaired`` through a short socket drop so countdown / setup does not restart.
    @MainActor
    private func scheduleCoachUnpairedAfterTransientDisconnectIfNeeded() {
        guard isCoachPaired else { return }
        cancelUnpairedDebounceTask()
        PartnerSetupLog.display("unpairedDebounce scheduled 1.5s \(PartnerSetupLog.activityTag())")
        unpairedDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.unpairedDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard socketConnectionState == .disconnected else { return }
            unpairedDebounceTask = nil
            PartnerSetupLog.display("unpairedDebounce fired \(PartnerSetupLog.activityTag())")
            applyCoachUnpaired(notify: true)
        }
    }

    /// When the relay drops while the app is active, wait 1.5s then reconnect.
    /// If a timed session is already managing, the existing join code is reused; otherwise a new room may be minted.
    @MainActor
    private func scheduleDisplayRelayRecycleAfterUnexpectedDisconnectIfNeeded() {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        guard !TrainingPartnerConnectionCoordinator.shared.shouldSuppressUnexpectedRelayRecycleNow() else {
            #if DEBUG
            print("[RelayWS-DEBUG] suppress unexpected relay recycle during transient lifecycle interruption")
            #endif
            return
        }
        cancelRelayDisconnectRecycleTask()
        relayDisconnectRecycleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard socketConnectionState == .disconnected else { return }
            guard joinCode != nil else { return }
            guard !TrainingPartnerConnectionCoordinator.shared.shouldSuppressUnexpectedRelayRecycleNow() else {
                #if DEBUG
                print("[RelayWS-DEBUG] recycle task skipped (transient lifecycle interruption)")
                #endif
                return
            }
            await TrainingPartnerConnectionCoordinator.shared.recyclePlayerDisplayRelaySessionKeepingPartnerRun(reason: "relay_socket_dropped_while_active")
        }
    }

    private func handleRawRelayText(_ text: String) {
        if text.contains("control.error") || text.contains("\"type\":\"control.error\"") {
            Task { @MainActor in
                handleRelayControlErrorText(text)
            }
        }
        if text.contains("peer_left") {
            Task { @MainActor in
                applyCoachUnpaired(notify: true)
            }
            return
        }
        let ackShowsPeerPresent = text.contains("\"peerPresent\":true")
            || text.contains("\"peerPresent\": true")
        if text.contains("peer_joined") || ackShowsPeerPresent {
            Task { @MainActor in
                applyCoachPaired()
                TrainingPartnerConnectionCoordinator.shared.broadcastPartnerSessionSnapshotFromDisplay(reason: "peer_joined_or_ack")
                TrainingPartnerConnectionCoordinator.shared.rebroadcastTimedSessionActiveFromDisplayIfNeeded()
                TrainingPartnerConnectionCoordinator.shared.rebroadcastDisplayRepEngineReadyFromDisplayIfNeeded()
            }
        }
    }

    @MainActor
    private func handleRelayControlErrorText(_ text: String) {
        let code: String
        if text.contains("DISPLAY_ALREADY_CONNECTED") {
            code = "DISPLAY_ALREADY_CONNECTED"
        } else if text.contains("INVALID_TOKEN") {
            code = "INVALID_TOKEN"
        } else if text.contains("SESSION_NOT_FOUND") {
            code = "SESSION_NOT_FOUND"
        } else if text.contains("SESSION_EXPIRED") {
            code = "SESSION_EXPIRED"
        } else {
            code = "UNKNOWN"
        }
        PartnerSetupLog.display(
            "relay control.error code=\(code) joinSuffix=\(PartnerSetupLog.joinCodeSuffix(joinCode)) \(PartnerSetupLog.activityTag())"
        )
        guard code == "DISPLAY_ALREADY_CONNECTED" else { return }
        // Same-token reclaim on current relay makes this obsolete; keep bounded retry for older relays / races.
        scheduleDisplayAlreadyConnectedRetryIfNeeded()
    }

    @MainActor
    private func scheduleDisplayAlreadyConnectedRetryIfNeeded() {
        guard transport != nil, joinCode != nil else { return }
        guard displayAlreadyConnectedRetryCount < Self.displayAlreadyConnectedMaxRetries else {
            PartnerSetupLog.display(
                "DISPLAY_ALREADY_CONNECTED retries exhausted max=\(Self.displayAlreadyConnectedMaxRetries) joinSuffix=\(PartnerSetupLog.joinCodeSuffix(joinCode))"
            )
            return
        }
        let attempt = displayAlreadyConnectedRetryCount
        let delay = Self.displayAlreadyConnectedBackoffNs[min(attempt, Self.displayAlreadyConnectedBackoffNs.count - 1)]
        displayAlreadyConnectedRetryTask?.cancel()
        displayAlreadyConnectedRetryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard socketConnectionState == .disconnected else { return }
            guard let t = transport else { return }
            displayAlreadyConnectedRetryCount += 1
            PartnerSetupLog.display(
                "DISPLAY_ALREADY_CONNECTED retry attempt=\(displayAlreadyConnectedRetryCount)/\(Self.displayAlreadyConnectedMaxRetries) joinSuffix=\(PartnerSetupLog.joinCodeSuffix(joinCode))"
            )
            t.connect()
        }
    }

    private func resetDisplayAlreadyConnectedRetryState() {
        displayAlreadyConnectedRetryTask?.cancel()
        displayAlreadyConnectedRetryTask = nil
        displayAlreadyConnectedRetryCount = 0
    }
}
