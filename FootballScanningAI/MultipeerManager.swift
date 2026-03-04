//
//  MultipeerManager.swift
//  FootballScanningAI
//
//  Manages Multipeer Connectivity for Pressure Response: iPad advertises,
//  iPhone browses and sends "trigger"; iPad receives and posts notification.
//

import Combine
import Foundation
import MultipeerConnectivity
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted when the iPad receives a trigger from the iPhone.
    static let pressureResponseTrigger = Notification.Name("PressureResponseTrigger")
    /// Posted when the iPad receives a TwoMinuteMessage (PBA V2). object = TwoMinuteMessage.
    static let twoMinuteMessageReceived = Notification.Name("TwoMinuteMessageReceived")
}

/// Service type for discovery (1–15 chars, lowercase letters/numbers/hyphens).
private let serviceType = "fbpressure"

final class MultipeerManager: NSObject {
    /// Whether we are advertising (iPad, receiver).
    @Published private(set) var isAdvertising = false
    /// Whether we are browsing (iPhone, sender).
    @Published private(set) var isBrowsing = false
    /// Connected peer display name, nil if none.
    @Published private(set) var connectedPeerName: String?
    /// Last error message for UI.
    @Published var lastError: String?

    private var myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let triggerMessage = "trigger".data(using: .utf8)!

    override init() {
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    // MARK: - iPad (receiver)

    func startAdvertising() {
        guard !isAdvertising else { return }
        stopBrowsing()
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
        lastError = nil
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session.disconnect()
        isAdvertising = false
        connectedPeerName = nil
    }

    // MARK: - iPhone (sender)

    func startBrowsing() {
        guard !isBrowsing else { return }
        stopAdvertising()
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        lastError = nil
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        session.disconnect()
        isBrowsing = false
        connectedPeerName = nil
    }

    /// Send trigger to connected peer. Call from iPhone when user taps Pass Made.
    func sendTrigger() {
        guard !session.connectedPeers.isEmpty else {
            DispatchQueue.main.async { self.lastError = "Not connected to iPad" }
            return
        }
        do {
            try session.send(triggerMessage, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    // MARK: - PBA V2 (2-Minute Test)

    /// Send a TwoMinuteMessage to connected peer. Call from iPhone (Coach).
    func sendTwoMinuteMessage(_ message: TwoMinuteMessage) {
        guard !session.connectedPeers.isEmpty else {
            DispatchQueue.main.async { self.lastError = "Not connected to iPad" }
            return
        }
        do {
            let encoder = JSONEncoder()
            let json = try encoder.encode(message)
            var data = "pba2:".data(using: .utf8)!
            data.append(json)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

}

// Explicit ObservableObject conformance (satisfies Swift 6 / strict concurrency)
extension MultipeerManager: ObservableObject {}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeerName = peerID.displayName
                self.lastError = nil
            case .notConnected, .connecting:
                if session.connectedPeers.isEmpty {
                    self.connectedPeerName = nil
                }
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if data == triggerMessage {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pressureResponseTrigger, object: nil)
            }
        } else if data.count > 5, data.prefix(5) == "pba2:".data(using: .utf8)! {
            let json = data.dropFirst(5)
            do {
                let msg = try JSONDecoder().decode(TwoMinuteMessage.self, from: json)
                DispatchQueue.main.async {
                    self.lastError = nil
                    NotificationCenter.default.post(name: .twoMinuteMessageReceived, object: msg)
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "2-min decode: \(error.localizedDescription)"
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard self.connectedPeerName == nil else { return }
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            if self.connectedPeerName == peerID.displayName {
                self.connectedPeerName = nil
            }
        }
    }
}
