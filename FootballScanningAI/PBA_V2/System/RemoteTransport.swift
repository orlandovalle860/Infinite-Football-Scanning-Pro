import Foundation

protocol RemoteTransport: AnyObject {
    var connectionState: ConnectionState { get }
    /// Emitted when the transport’s connection state changes (e.g. Multipeer session). Prefer main-thread delivery.
    var onConnectionStateChanged: ((ConnectionState) -> Void)? { get set }
    var onTwoMinuteMessageReceived: ((TwoMinuteMessage) -> Void)? { get set }

    func connect()
    func disconnect()

    func send(_ message: TwoMinuteMessage)
}
