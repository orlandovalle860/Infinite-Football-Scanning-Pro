import Combine
import Foundation

/// Sends `TwoMinuteMessage` over the active transport. Payload `kind` strings are protocol-stable — see `CoachRemoteDecisionModelMIGRATION.md`.
final class RemoteService: ObservableObject {
    @Published private(set) var connectionState: ConnectionState

    private var transport: RemoteTransport

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
        transport.connect()
        connectionState = transport.connectionState
    }

    func disconnect() {
        transport.disconnect()
        connectionState = transport.connectionState
    }

    func send(_ message: TwoMinuteMessage) {
        transport.send(message)
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
        send(.nextRep(repIndex: repIndex))
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
#if DEBUG
        print("[RemoteService] connectionState \(connectionState.rawValue) -> \(state.rawValue) [\(source)]")
#endif
        connectionState = state
    }
}
