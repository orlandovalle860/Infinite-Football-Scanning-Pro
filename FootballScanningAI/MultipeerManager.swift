//
//  MultipeerManager.swift
//  FootballScanningAI
//
//  Thin facade over ConnectionManager.shared for backward compatibility.
//  Views should prefer ConnectionManager.shared.startHosting() / startBrowsing() / sendCommand(...).
//

import Combine
import Foundation
import MultipeerConnectivity
import SwiftUI
import UIKit

extension Notification.Name {
    static let pressureResponseTrigger = Notification.Name("PressureResponseTrigger")
    static let twoMinuteMessageReceived = Notification.Name("TwoMinuteMessageReceived")
    static let displaySessionInfoReceived = Notification.Name("DisplaySessionInfoReceived")
    static let requestPopToRoot = Notification.Name("RequestPopToRoot")
}

let hasCompletedInitialTestKey = "hasCompletedInitialTest"

final class MultipeerManager: NSObject, ObservableObject {
    static weak var shared: MultipeerManager?

    private let connection = ConnectionManager.shared
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var isAdvertising: Bool = false
    @Published private(set) var isBrowsing: Bool = false
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var availablePeers: [MCPeerID] = []
    @Published var lastError: String?

    var isHost: Bool { connection.isHost }

    override init() {
        super.init()
        MultipeerManager.shared = self
        connection.$connectionState.receive(on: DispatchQueue.main).sink { [weak self] in self?.connectionState = $0 }.store(in: &cancellables)
        connection.$isAdvertising.receive(on: DispatchQueue.main).sink { [weak self] in self?.isAdvertising = $0 }.store(in: &cancellables)
        connection.$isBrowsing.receive(on: DispatchQueue.main).sink { [weak self] in self?.isBrowsing = $0 }.store(in: &cancellables)
        connection.$connectedPeerName.receive(on: DispatchQueue.main).sink { [weak self] in self?.connectedPeerName = $0 }.store(in: &cancellables)
        connection.$availablePeers.receive(on: DispatchQueue.main).sink { [weak self] in self?.availablePeers = $0 }.store(in: &cancellables)
        connection.$lastError.receive(on: DispatchQueue.main).sink { [weak self] in self?.lastError = $0 }.store(in: &cancellables)
    }

    func startAdvertising() { connection.startHosting() }
    func stopAdvertising() { connection.stopHosting() }
    func startBrowsing() { connection.startBrowsing() }
    func stopBrowsing() { connection.stopBrowsing() }
    func invite(peerID: MCPeerID) { connection.invite(peerID: peerID) }
    func sendTrigger() { connection.sendTrigger() }
    func sendTwoMinuteMessage(_ message: TwoMinuteMessage) { connection.sendTwoMinuteMessage(message) }
    func sendDisplaySessionInfo(hasCompletedInitialTest: Bool) { connection.sendDisplaySessionInfo(hasCompletedInitialTest: hasCompletedInitialTest) }
}
