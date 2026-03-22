import Combine
import Foundation
import UIKit

final class MultipeerRemoteTransport: RemoteTransport {
    private let connection = ConnectionManager.shared
    private var messageObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    var onConnectionStateChanged: ((ConnectionState) -> Void)? {
        didSet {
            onConnectionStateChanged?(connection.connectionState)
        }
    }

    var onTwoMinuteMessageReceived: ((TwoMinuteMessage) -> Void)?

    var connectionState: ConnectionState {
        connection.connectionState
    }

    init() {
        messageObserver = NotificationCenter.default.addObserver(
            forName: .twoMinuteMessageReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let msg = notification.object as? TwoMinuteMessage else { return }
            self?.onTwoMinuteMessageReceived?(msg)
        }

        connection.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.onConnectionStateChanged?(state)
            }
            .store(in: &cancellables)
    }

    deinit {
        if let messageObserver {
            NotificationCenter.default.removeObserver(messageObserver)
        }
    }

    func connect() {
        // Preserve existing behavior: iPad hosts, iPhone browses.
        if UIDevice.current.userInterfaceIdiom == .pad {
            connection.startHosting()
        } else {
            connection.startBrowsing()
        }
    }

    func disconnect() {
        // Preserve existing behavior: stop the role-specific connection flow.
        if UIDevice.current.userInterfaceIdiom == .pad {
            connection.stopHosting()
        } else {
            connection.stopBrowsing()
        }
    }

    func send(_ message: TwoMinuteMessage) {
        connection.sendTwoMinuteMessage(message)
    }
}
