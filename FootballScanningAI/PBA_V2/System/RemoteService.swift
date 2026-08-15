import Combine
import Foundation

/// Sends `TwoMinuteMessage` over the active transport. Payload `kind` strings are protocol-stable — see `CoachRemoteDecisionModelMIGRATION.md`.
final class RemoteService: ObservableObject {
    @Published private(set) var connectionState: ConnectionState

    /// Whether the active transport WebSocket (relay) is connected — used for partner UI and ``onChange`` (via ``connectionState``) without duplicating `ConnectionState` switches everywhere.
    var isCoachConnected: Bool { connectionState == .connected }

    private var transport: RemoteTransport

    /// True when the installed transport can open a relay WebSocket (not pending/Multipeer placeholder).
    var hasUsableWebSocketRemoteTransport: Bool {
        transport is WebSocketRemoteTransport
    }

    /// Diagnostic label for HotspotBaseline (never includes credentials).
    var installedTransportKindForDiagnostics: String {
        if transport is WebSocketRemoteTransport { return "WebSocketRemoteTransport" }
        if transport is RelayPendingRemoteTransport { return "RelayPendingRemoteTransport" }
        if transport is MultipeerRemoteTransport { return "MultipeerRemoteTransport" }
        return "other"
    }

    var onTwoMinuteMessageReceived: ((TwoMinuteMessage) -> Void)? {
        didSet {
            bindTransportMessageForwarding()
        }
    }

    init(transport: RemoteTransport = MultipeerRemoteTransport()) {
        self.transport = transport
        self.connectionState = transport.connectionState
        bindTransportMessageForwarding()
        bindTransportConnectionState()
    }

    /// Swaps the active transport (e.g. relay: pending → WebSocket after join). Disconnects the previous transport first.
    func replaceTransport(_ newTransport: RemoteTransport) {
        transport.disconnect()
        transport = newTransport
        connectionState = transport.connectionState
        bindTransportMessageForwarding()
        bindTransportConnectionState()
    }

    func connect() {
        HotspotBaselineLog.emit(
            "COACH RemoteService.connect() priorState=\(connectionState.rawValue) transport=\(installedTransportKindForDiagnostics)"
        )
        transport.connect()
        connectionState = transport.connectionState
        HotspotBaselineLog.emit(
            "COACH RemoteService.connect() afterState=\(connectionState.rawValue) transport=\(installedTransportKindForDiagnostics)"
        )
    }

    func disconnect() {
        HotspotBaselineLog.emit("COACH RemoteService.disconnect() CALLED priorState=\(connectionState.rawValue)")
        transport.disconnect()
        connectionState = transport.connectionState
        HotspotBaselineLog.emit("COACH RemoteService.disconnect() afterState=\(connectionState.rawValue)")
    }

    func send(_ message: TwoMinuteMessage) {
        send(message, completion: nil)
    }

    /// - Parameter completion: Called on the main queue after the send attempt (WebSocket: after URLSession callback; Multipeer: immediately).
    func send(_ message: TwoMinuteMessage, completion: (@Sendable () -> Void)?) {
        if let ws = transport as? WebSocketRemoteTransport {
            ws.send(message, completion: completion)
        } else {
            transport.send(message)
            completion?()
        }
        connectionState = transport.connectionState
    }

    func sendPassTriggered(repIndex: Int, timestamp: Date) {
        send(.passTriggered(repIndex: repIndex, timestamp: timestamp))
    }

    func sendExitLogged(repIndex: Int, gate: Gate, timestamp: Date) {
        send(.exitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp))
    }

    /// Still required when coach must mark wrong without logging a misleading direction (all partner activities).
    func sendIncorrectDecision(repIndex: Int, timestamp: Date) {
        send(.incorrectDecision(repIndex: repIndex, timestamp: timestamp))
    }

    func sendNextRep(repIndex: Int) {
        HotspotBaselineLog.emit(
            "COACH sendNextRep called repIndex=\(repIndex) connectionState=\(connectionState.rawValue) transport=\(installedTransportKindForDiagnostics)"
        )
        send(.nextRep(repIndex: repIndex)) { [weak self] in
            HotspotBaselineLog.emit(
                "COACH sendNextRep completion repIndex=\(repIndex) connectionState=\(self?.connectionState.rawValue ?? "nil") transport=\(self?.installedTransportKindForDiagnostics ?? "nil")"
            )
        }
        DispatchQueue.main.async {
            let coordinator = TrainingPartnerConnectionCoordinator.shared
            coordinator.markPartnerDrillUnderwayForMidSessionRecovery()
            if let activityId = coordinator.currentTimedSessionActivityId ?? coordinator.lastNonNilActivityId {
                coordinator.notePersistedCoachNextRepIndex(repIndex, activityId: activityId)
            }
        }
    }

    func sendCalibrationPassTapped(timestamp: Date) {
        send(.calibrationPassTapped(timestamp: timestamp))
    }

    func sendCalibrationArrivalTapped(timestamp: Date) {
        send(.calibrationArrivalTapped(timestamp: timestamp))
    }

    func sendCalibrationFinished(averageTravelTimeSeconds: Double?) {
        send(.calibrationFinished(averageTravelTimeSeconds: averageTravelTimeSeconds))
    }

    private func bindTransportMessageForwarding() {
        transport.onTwoMinuteMessageReceived = { [weak self] message in
            self?.onTwoMinuteMessageReceived?(message)
            self?.mirrorConnectionState(self?.transport.connectionState ?? .disconnected, source: "transport_message")
        }
    }

    private func bindTransportConnectionState() {
        transport.onConnectionStateChanged = { [weak self] state in
            self?.mirrorConnectionState(state, source: "transport_state")
        }
    }

    private func mirrorConnectionState(_ state: ConnectionState, source: String) {
        guard connectionState != state else { return }
        HotspotBaselineLog.emit("COACH socket \(connectionState.rawValue)->\(state.rawValue) source=\(source)")
#if DEBUG
        print("[RemoteService] connectionState \(connectionState.rawValue) -> \(state.rawValue) [\(source)]")
#endif
        connectionState = state
    }
}
