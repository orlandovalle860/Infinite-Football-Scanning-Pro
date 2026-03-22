//
//  ConnectionManager.swift
//  FootballScanningAI
//
//  Singleton that owns all MultipeerConnectivity logic for coach remote ↔ training iPad (no Wi‑Fi).
//
//  Connection reliability:
//  • MCSession created once (ensureSession) and reused for app lifecycle; never recreated in views.
//  • MCSession(peer:securityIdentity:nil, encryptionPreference: .none) for faster negotiation.
//  • All sends use session.send(..., with: .reliable).
//  • invitePeer(..., timeout: 10) for short invite timeout.
//
//  Architecture:
//  • iPad = host only: MCNearbyServiceAdvertiser, accepts invitations. startHosting() no-op on iPhone.
//  • iPhone = remote only: MCNearbyServiceBrowser, invites iPad. startBrowsing() no-op on iPad.
//

import Combine
import Foundation
import MultipeerConnectivity
import SwiftUI
import UIKit

/// Connection lifecycle state for UI and reconnection logic.
enum ConnectionState: String, Equatable {
    case searching
    case connecting
    case connected
    case disconnected
}

private let serviceType = "pba-training"
private let pbaDisplayPrefix = "PBA-Display-"
private let heartbeatPrefix = "pba:hb"
private let triggerMessage = "trigger".data(using: .utf8)!
private let pba2Prefix = "pba2:".data(using: .utf8)!
private let displayPrefix = "display:".data(using: .utf8)!
private let heartbeatInterval: TimeInterval = 3
private let heartbeatTimeout: TimeInterval = 9
private let inviteTimeoutSeconds: TimeInterval = 20

/// Single persistent ConnectionManager. Views must NOT create MCSession, advertiser, or browser.
final class ConnectionManager: NSObject, ObservableObject {
    static let shared = ConnectionManager()

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var availablePeers: [MCPeerID] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published var lastError: String?

    /// True when this device is the host (iPad). False when remote (iPhone).
    var isHost: Bool { !isBrowsing }

    /// Host (iPad) advertises; remote (iPhone) browses. Set at first start.
    private var role: Role?
    private var myPeerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var heartbeatTimer: Timer?
    private var receiveCheckTimer: Timer?
    private var lastReceivedTime: Date?
    private let queue = DispatchQueue(label: "com.pba.connectionmanager")

    private enum Role {
        case host   // iPad: advertiser only
        case remote // iPhone: browser only
    }

    private override init() {
        super.init()
    }

    // MARK: - Session (create once)

    private func ensureSession(as role: Role) {
        guard session == nil else { return }
        self.role = role
        switch role {
        case .host:
            myPeerID = MCPeerID(displayName: Self.displayPeerDisplayName())
        case .remote:
            myPeerID = MCPeerID(displayName: UIDevice.current.name)
        }
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
    }

    private static func displayPeerDisplayName() -> String {
        let raw = UIDevice.current.identifierForVendor?.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
            ?? UserDefaults.standard.string(forKey: "pba_display_peer_id")
            ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        if UserDefaults.standard.string(forKey: "pba_display_peer_id") == nil, raw.count >= 4 {
            UserDefaults.standard.set(raw, forKey: "pba_display_peer_id")
        }
        let suffix = String(raw.suffix(4))
        return "\(pbaDisplayPrefix)\(suffix)"
    }

    /// iPad only. No-op on iPhone so only the iPad advertises.
    private var isHostDevice: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: - Host (iPad) – Advertiser only. Call on iPad only.

    func startHosting() {
        guard isHostDevice else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopBrowsingIfNeeded()
            self.ensureSession(as: .host)
            self.advertiser?.stopAdvertisingPeer()
            let adv = MCNearbyServiceAdvertiser(peer: self.myPeerID, discoveryInfo: nil, serviceType: serviceType)
            self.advertiser = adv
            DispatchQueue.main.async {
                adv.delegate = self
                adv.startAdvertisingPeer()
                self.isAdvertising = true
                self.isBrowsing = false
                self.connectionState = .searching
                self.lastError = nil
            }
        }
    }

    func stopHosting() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopHeartbeat()
            self.advertiser?.stopAdvertisingPeer()
            self.advertiser = nil
            self.session?.disconnect()
            DispatchQueue.main.async {
                self.isAdvertising = false
                self.connectionState = .disconnected
                self.connectedPeerName = nil
            }
        }
    }

    /// iPhone only. No-op on iPad so only the iPhone browses.
    private var isRemoteDevice: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    // MARK: - Remote (iPhone) – Browser only

    func startBrowsing() {
        guard isRemoteDevice else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopAdvertisingIfNeeded()
            self.ensureSession(as: .remote)
            self.browser?.stopBrowsingForPeers()
            let br = MCNearbyServiceBrowser(peer: self.myPeerID, serviceType: serviceType)
            self.browser = br
            DispatchQueue.main.async {
                br.delegate = self
                br.startBrowsingForPeers()
                self.isBrowsing = true
                self.isAdvertising = false
                self.connectionState = .searching
                self.availablePeers = []
                self.lastError = nil
            }
        }
    }

    func stopBrowsing() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopHeartbeat()
            self.browser?.stopBrowsingForPeers()
            self.browser = nil
            self.session?.disconnect()
            DispatchQueue.main.async {
                self.isBrowsing = false
                self.connectionState = .disconnected
                self.connectedPeerName = nil
                self.availablePeers = []
            }
        }
    }

    func invite(peerID: MCPeerID) {
        queue.async { [weak self] in
            guard let self = self, let browser = self.browser, let session = self.session else { return }
            guard self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) else { return }
            DispatchQueue.main.async { self.connectionState = .connecting }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: inviteTimeoutSeconds)
        }
    }

    private func stopBrowsingIfNeeded() {
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
    }

    private func stopAdvertisingIfNeeded() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
    }

    // MARK: - Send (all .reliable). Views must use these; do not create session/send directly.

    /// Send raw data to the connected peer. Uses MCSessionSendDataMode.reliable.
    func sendCommand(_ data: Data) {
        queue.async { [weak self] in
            guard let self = self, let session = self.session, !session.connectedPeers.isEmpty else {
                DispatchQueue.main.async { [weak self] in self?.lastError = "Not connected" }
                return
            }
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                DispatchQueue.main.async { [weak self] in self?.lastError = error.localizedDescription }
            }
        }
    }

    /// Pressure trigger (iPhone → iPad).
    func sendTrigger() {
        guard connectedPeerName != nil else { DispatchQueue.main.async { self.lastError = "Not connected to iPad" }; return }
        sendCommand(triggerMessage)
    }

    /// Two-minute test / PBA V2 message (iPhone → iPad).
    func sendTwoMinuteMessage(_ message: TwoMinuteMessage) {
        guard connectedPeerName != nil else { DispatchQueue.main.async { self.lastError = "Not connected to iPad" }; return }
        do {
            var data = pba2Prefix
            data.append(try JSONEncoder().encode(message))
            sendCommand(data)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    /// Session info iPad → iPhone (e.g. hasCompletedInitialTest).
    func sendDisplaySessionInfo(hasCompletedInitialTest: Bool) {
        guard isAdvertising, connectedPeerName != nil else { return }
        do {
            var data = displayPrefix
            data.append(try JSONEncoder().encode(["hasCompletedInitialTest": hasCompletedInitialTest]))
            sendCommand(data)
        } catch { /* best-effort */ }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        lastReceivedTime = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
                self?.sendHeartbeat()
            }
            self.heartbeatTimer?.tolerance = 0.3
            RunLoop.main.add(self.heartbeatTimer!, forMode: .common)
            self.receiveCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkReceiveTimeout()
            }
            self.receiveCheckTimer?.tolerance = 0.2
            RunLoop.main.add(self.receiveCheckTimer!, forMode: .common)
        }
    }

    private func stopHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
            self?.receiveCheckTimer?.invalidate()
            self?.receiveCheckTimer = nil
        }
        lastReceivedTime = nil
    }

    private func sendHeartbeat() {
        guard let data = heartbeatPrefix.data(using: .utf8), let session = session, !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    private func handleReceivedData(_ data: Data, fromPeer peerID: MCPeerID) {
        if data == triggerMessage {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .pressureResponseTrigger, object: nil) }
        } else if data.count > 5, data.prefix(5) == pba2Prefix {
            let json = data.dropFirst(5)
            do {
                let msg = try JSONDecoder().decode(TwoMinuteMessage.self, from: json)
                DispatchQueue.main.async {
                    self.lastError = nil
                    NotificationCenter.default.post(name: .twoMinuteMessageReceived, object: msg)
                }
            } catch {
                DispatchQueue.main.async { self.lastError = "2-min decode: \(error.localizedDescription)" }
            }
        } else if data.count > 8, data.prefix(8) == displayPrefix {
            let json = data.dropFirst(8)
            if let payload = try? JSONDecoder().decode([String: Bool].self, from: json),
               let flag = payload["hasCompletedInitialTest"] {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(flag, forKey: hasCompletedInitialTestKey)
                    NotificationCenter.default.post(name: .displaySessionInfoReceived, object: nil)
                }
            }
        }
    }

    private func checkReceiveTimeout() {
        guard let last = lastReceivedTime else { return }
        if Date().timeIntervalSince(last) > heartbeatTimeout {
            handleSilentDisconnect()
        }
    }

    private func handleSilentDisconnect() {
        stopHeartbeat()
        session?.disconnect()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionState = .disconnected
            self.connectedPeerName = nil
            self.triggerAutoReconnect()
        }
    }

    private func triggerAutoReconnect() {
        if role == .remote {
            startBrowsing()
        } else if role == .host {
            startHosting()
        }
    }

    private func onPeerDisconnected() {
        stopHeartbeat()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectedPeerName = nil
            if self.session?.connectedPeers.isEmpty ?? true {
                self.connectionState = .disconnected
                self.triggerAutoReconnect()
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension ConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            queue.async { [weak self] in
                self?.lastReceivedTime = Date()
                self?.startHeartbeat()
            }
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .connected
                self?.connectedPeerName = peerID.displayName
                self?.availablePeers = []
                self?.lastError = nil
            }
        case .notConnected, .connecting:
            if session.connectedPeers.isEmpty {
                onPeerDisconnected()
            }
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        queue.async { [weak self] in
            self?.lastReceivedTime = Date()
        }
        if data.count >= 6, String(data: data.prefix(6), encoding: .utf8) == heartbeatPrefix {
            return
        }
        handleReceivedData(data, fromPeer: peerID)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in self?.connectionState = .connecting }
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension ConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard peerID.displayName.hasPrefix(pbaDisplayPrefix) else { return }
            guard !self.availablePeers.contains(where: { $0.displayName == peerID.displayName }) else { return }
            self.availablePeers.append(peerID)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.availablePeers.removeAll { $0.displayName == peerID.displayName }
            if self?.connectedPeerName == peerID.displayName {
                self?.connectedPeerName = nil
            }
        }
    }
}
