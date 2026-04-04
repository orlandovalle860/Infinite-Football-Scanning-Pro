//
//  TrainingPartnerConnectionCoordinator.swift
//  FootballScanningAI
//
//  PBA V2 — One coach ↔ display pairing per training session: reuse relay (and Multipeer host/browse)
//  across Home, Pathway, iOS springboard, and activity switches until ``endPartnerTrainingSession(reason:notifyPeer:)`` runs
//  (explicit Leave, coach hub end, or ``popToRoot(endingPartnerSession: true)``). iOS background only **suspends** relay.
//

import Foundation
import UIKit

/// Owns shared coach/display transport for one partner **training run** until an explicit end reason.
@MainActor
final class TrainingPartnerConnectionCoordinator {
    static let shared = TrainingPartnerConnectionCoordinator()

    /// Shared relay display session (join code + WebSocket). One instance per app run.
    let relayDisplaySession = PartnerRelayDisplaySession()

    /// Shared coach `RemoteService` for relay WebSocket. Same instance for all activity coach remotes.
    let coachRelayRemoteService = RemoteService(transport: TwoMinuteSessionTransport.makeInitial(for: .relayWebSocket))

    /// True after the first partner pairing starts; cleared only on ``endPartnerTrainingSession(reason:notifyPeer:)`` (explicit Leave,
    /// coach hub end, or ``AppRouter.popToRoot(endingPartnerSession: true)``). **Not** cleared on iOS background.
    private(set) var isPartnerTrainingSessionActive: Bool = false

    /// Last join code the coach successfully used for the shared relay WebSocket. Each activity’s coach remote is a **new** SwiftUI view with empty ``@State`` for the text field — without this, switching e.g. Away From Pressure → Dribble or Pass could not auto-reconnect with the same code.
    /// Cleared when pairing ends or when coach UI explicitly clears the join form after a real disconnect.
    private(set) var lastCoachRelayJoinCode: String?

    /// Bumps on each ``endPartnerTrainingSession`` / ``beginPartnerTrainingSessionIfNeeded`` transition so async relay notify completions cannot tear down a **new** session if the user starts the next run before the send finishes.
    private var relaySessionMutationToken: UInt64 = 0

    private var partnerTrainingEndedObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?

    private init() {
        partnerTrainingEndedObserver = NotificationCenter.default.addObserver(
            forName: .twoMinuteMessageReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let msg = notification.object as? TwoMinuteMessage else { return }
            guard case .partnerTrainingEnded = msg else { return }
            Task { @MainActor in
                self?.handleIncomingPartnerTrainingEndedFromPeer()
            }
        }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reconnectPartnerRelayAfterForegroundIfNeeded()
            }
        }
    }

    deinit {
        if let partnerTrainingEndedObserver {
            NotificationCenter.default.removeObserver(partnerTrainingEndedObserver)
        }
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    /// After `suspendPartnerSessionForBackground()`, relay sockets are disconnected; reconnect when the app is active again.
    private func reconnectPartnerRelayAfterForegroundIfNeeded() async {
        guard isPartnerTrainingSessionActive else { return }
        #if DEBUG
        PartnerPersistDebug.log("UIApplication.didBecomeActive — reconnectPartnerRelayAfterForegroundIfNeeded")
        #endif
        await relayDisplaySession.startDisplaySessionIfNeeded()
        if coachRelayRemoteService.connectionState != .connected {
            #if DEBUG
            PartnerPersistDebug.log("coach relay not connected after foreground — RemoteService.connect()")
            #endif
            coachRelayRemoteService.connect()
        }
    }

    /// Call after a successful HTTP join so any subsequent activity coach screen can restore the same one-time code.
    func recordCoachRelayJoinCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastCoachRelayJoinCode = trimmed
    }

    /// Clears the stored coach join code (e.g. when the coach join UI is reset after a real session end).
    func clearRecordedCoachRelayJoinCode() {
        lastCoachRelayJoinCode = nil
    }

    /// Call when entering the partner training flow (first relay display or first coach relay join).
    func beginPartnerTrainingSessionIfNeeded() {
        guard !isPartnerTrainingSessionActive else {
            #if DEBUG
            PartnerPersistDebug.log("beginPartnerTrainingSessionIfNeeded — already active (no-op)")
            #endif
            return
        }
        relaySessionMutationToken += 1
        relayDisplaySession.tearDown()
        coachRelayRemoteService.disconnect()
        #if DEBUG
        EndTrainingDebug.log("beginPartnerTrainingSessionIfNeeded — cleared stale relay transports before new run")
        #endif
        ConnectionManager.shared.stopHosting()
        ConnectionManager.shared.stopBrowsing()
        isPartnerTrainingSessionActive = true
        #if DEBUG
        print("[Multipeer] TrainingPartnerSession: begin — partner training session active (relay + Multipeer reuse allowed)")
        PartnerPersistDebug.log("beginPartnerTrainingSessionIfNeeded — marked partner training session active")
        #endif
    }

    /// Ends pairing for this training run: optionally notify the peer so **both** devices invalidate relay state, then tear down locally.
    /// - Parameters:
    ///   - reason: Logged in DEBUG.
    ///   - notifyPeer: When `true`, sends ``TwoMinuteMessage/partnerTrainingEnded`` over relay (if connected) or Multipeer before local teardown. Set `false` when handling the same message from the peer to avoid an echo loop.
    func endPartnerTrainingSession(reason: String = "unspecified", notifyPeer: Bool = true) {
        guard isPartnerTrainingSessionActive else {
            #if DEBUG
            EndTrainingDebug.log("endPartnerTrainingSession skipped (already inactive) reason=\(reason)")
            print("[Multipeer] TrainingPartnerSession: endPartnerTrainingSession skipped (already inactive) reason=\(reason)")
            #endif
            return
        }
        #if DEBUG
        EndTrainingDebug.log("explicit end requested reason=\(reason) notifyPeer=\(notifyPeer) — clearing active + stored join code before peer notify")
        #endif
        relaySessionMutationToken += 1
        let endToken = relaySessionMutationToken
        isPartnerTrainingSessionActive = false
        lastCoachRelayJoinCode = nil

        let finishLocalTeardown: () -> Void = { [weak self] in
            guard let self else { return }
            guard endToken == self.relaySessionMutationToken else {
                #if DEBUG
                EndTrainingDebug.log("local teardown skipped (stale token \(endToken) vs current \(self.relaySessionMutationToken)) — new run already started")
                #endif
                return
            }
            self.relayDisplaySession.tearDown()
            self.coachRelayRemoteService.disconnect()
            ConnectionManager.shared.stopHosting()
            ConnectionManager.shared.stopBrowsing()
            #if DEBUG
            EndTrainingDebug.log("local transport teardown complete reason=\(reason)")
            PartnerPersistDebug.log("endPartnerTrainingSession(reason: \(reason)) — pairing ended")
            print("[Multipeer] TrainingPartnerSession: END pairing — reason=\(reason) — relay tearDown (DEBUG) + Multipeer stopHosting/stopBrowsing")
            #endif
        }

        guard notifyPeer else {
            finishLocalTeardown()
            return
        }

        notifyPeerOfPartnerTrainingEndedIfNeeded {
            finishLocalTeardown()
        }
    }

    private func handleIncomingPartnerTrainingEndedFromPeer() {
        guard isPartnerTrainingSessionActive else {
            #if DEBUG
            EndTrainingDebug.log("incoming partnerTrainingEnded ignored (already inactive)")
            #endif
            return
        }
        #if DEBUG
        EndTrainingDebug.log("incoming partnerTrainingEnded from peer — ending locally without echo")
        #endif
        endPartnerTrainingSession(reason: "relay.peerPartnerTrainingEnded", notifyPeer: false)
    }

    /// Sends ``partnerTrainingEnded`` on whichever transport is connected, then invokes `completion` on the main queue.
    private func notifyPeerOfPartnerTrainingEndedIfNeeded(completion: @escaping @Sendable () -> Void) {
        let msg = TwoMinuteMessage.partnerTrainingEnded(timestamp: Date())
        if coachRelayRemoteService.connectionState == .connected {
            #if DEBUG
            EndTrainingDebug.log("notifyPeer: sending partnerTrainingEnded via coach relay WebSocket")
            #endif
            coachRelayRemoteService.send(msg, completion: completion)
            return
        }
        if relayDisplaySession.socketConnectionState == .connected {
            #if DEBUG
            EndTrainingDebug.log("notifyPeer: sending partnerTrainingEnded via display relay WebSocket")
            #endif
            relayDisplaySession.sendTwoMinuteMessage(msg, completion: completion)
            return
        }
        if ConnectionManager.shared.connectedPeerName != nil {
            #if DEBUG
            EndTrainingDebug.log("notifyPeer: sending partnerTrainingEnded via Multipeer")
            #endif
            ConnectionManager.shared.sendTwoMinuteMessage(msg)
            DispatchQueue.main.async(execute: completion)
            return
        }
        #if DEBUG
        EndTrainingDebug.log("notifyPeer: no relay/Multipeer path connected — local teardown only")
        #endif
        completion()
    }

    /// When `true`, activity screens should not tear down relay or disconnect coach on `onDisappear` (activity transition).
    var shouldPersistPartnerPairing: Bool { isPartnerTrainingSessionActive }

    /// Explicit Multipeer state: partner training is active **and** Multipeer has a named peer (coach ↔ display).
    var isMultipeerPartnerConnected: Bool {
        isPartnerTrainingSessionActive && ConnectionManager.shared.connectedPeerName != nil
    }

    /// Display (iPad) partner drills: call after ``beginPartnerTrainingSessionIfNeeded()`` — `ConnectionManager` may skip `startHosting` if already connected.
    func prepareMultipeerDisplayPartner(connectionManager: ConnectionManager) {
        #if DEBUG
        if connectionManager.isAdvertising, connectionManager.connectedPeerName != nil {
            print("[Multipeer] TrainingPartnerSession: display — reusing host (advertising + connected peer)")
        } else if connectionManager.isAdvertising {
            print("[Multipeer] TrainingPartnerSession: display — startHosting (advertising, peer not connected yet)")
        }
        #endif
        connectionManager.startHosting()
    }

    /// Coach remote (iPhone): call after ``beginPartnerTrainingSessionIfNeeded()`` — `ConnectionManager` may skip `startBrowsing` if already connected.
    func prepareMultipeerCoachRemote(connectionManager: ConnectionManager) {
        #if DEBUG
        if connectionManager.isBrowsing, connectionManager.connectedPeerName != nil {
            print("[Multipeer] TrainingPartnerSession: coach — reusing browse session (connected)")
        }
        #endif
        connectionManager.startBrowsing()
    }

    /// Display: call `startDisplaySessionIfNeeded()` on the shared relay.
    func prepareRelayDisplayForActivity() async {
        #if DEBUG
        PartnerPersistDebug.log("prepareRelayDisplayForActivity — enter (will begin session if needed + startDisplaySessionIfNeeded)")
        #endif
        beginPartnerTrainingSessionIfNeeded()
        await relayDisplaySession.startDisplaySessionIfNeeded()
    }

    /// iOS background (springboard / multitasking): disconnect relay socket only — **keep** join code and training flag
    /// so the next drill can reconnect without a new join code. Does **not** send `sessionEnded` to coach.
    func suspendPartnerSessionForBackground() {
        guard isPartnerTrainingSessionActive else { return }
        #if DEBUG
        print("[Multipeer] TrainingPartnerSession: suspend for iOS background — keep pairing; relay soft disconnect only")
        #endif
        relayDisplaySession.suspendForAppBackground()
    }
}
