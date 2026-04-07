//
//  TrainingPartnerConnectionCoordinator.swift
//  FootballScanningAI
//
//  PBA V2 — One coach ↔ display pairing per training session: reuse relay (and Multipeer host/browse)
//  across Home, Pathway, iOS springboard, and activity switches until ``endPartnerTrainingSession(reason:notifyPeer:)`` runs
//  (explicit Leave, coach hub end, or ``popToRoot(endingPartnerSession: true)``). iOS background **suspends** relay sockets;
//  foreground triggers reconnect + optional checkpoint messaging.
//

import Combine
import Foundation
import UIKit

/// Owns shared coach/display transport for one partner **training run** until an explicit end reason.
@MainActor
final class TrainingPartnerConnectionCoordinator: ObservableObject {
    static let shared = TrainingPartnerConnectionCoordinator()

    /// Shared relay display session (join code + WebSocket). One instance per app run.
    let relayDisplaySession = PartnerRelayDisplaySession()

    /// Shared coach `RemoteService` for relay WebSocket. Same instance for all activity coach remotes.
    let coachRelayRemoteService = RemoteService(transport: TwoMinuteSessionTransport.makeInitial(for: .relayWebSocket))

    /// Banner for reconnect / restored / rejoin / checkpoint drift (partner relay).
    @Published private(set) var relayLifecycleBanner: PartnerRelayLifecycleBanner = .hidden

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
    private var willResignActiveObserver: NSObjectProtocol?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var bannerAutoHideTask: Task<Void, Never>?

    // MARK: - Soft resume (grace window)

    /// When the relay was suspended (background); used with ``RelaySoftResumeConfig.interruptionGraceSeconds``.
    private var interruptionBeganAt: Date?
    /// Display relay session id captured at suspend; compared after reconnect for the same server session.
    private var relaySessionIdSnapshotAtSuspend: String?
    /// Server session id from display HTTP create or coach HTTP join (same logical session).
    private(set) var trackedRelaySessionId: String?
    /// Coach iPhone: brief reconnect succeeded; waiting for display ``partnerSessionCheckpoint`` to validate soft resume.
    private(set) var awaitingSoftResumeCheckpointValidation: Bool = false

    /// Call when the relay server session id is known (display session created or coach HTTP join).
    func recordRelaySessionId(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        trackedRelaySessionId = id
    }

    private func clearSoftResumeInterruptionState() {
        interruptionBeganAt = nil
        relaySessionIdSnapshotAtSuspend = nil
        awaitingSoftResumeCheckpointValidation = false
    }

    /// Coach: validate soft resume after display checkpoint (``partnerSessionCheckpoint``).
    func applyCoachSoftResumeCheckpointValidation(relaySessionMatch: Bool, activityMatch: Bool, repMatch: Bool) {
        guard awaitingSoftResumeCheckpointValidation else { return }
        awaitingSoftResumeCheckpointValidation = false
        let passed = relaySessionMatch && activityMatch && repMatch
        RelaySoftResumeDebug.logSessionValidation(
            passed: passed,
            detail: "relay=\(relaySessionMatch) activity=\(activityMatch) rep=\(repMatch)"
        )
        if passed {
            clearCheckpointDrift()
            relayLifecycleBanner = .sessionRestoredSoft
            scheduleAutoHideSessionRestoredSoftBanner()
            clearSoftResumeInterruptionState()
            RelaySoftResumeDebug.logSoftResumeOutcome(success: true, reason: "coach_checkpoint_validated")
        } else {
            relayLifecycleBanner = .sessionRequiresRejoin
            clearSoftResumeInterruptionState()
            RelaySoftResumeDebug.logFallbackToRejoin(reason: "coach_soft_resume_checkpoint_failed")
        }
    }

    /// Non–soft-resume path: checkpoint relay session id disagrees with tracked server session.
    func applyRelaySessionIdMismatchFromCheckpoint() {
        relayLifecycleBanner = .sessionRequiresRejoin
        RelaySoftResumeDebug.logFallbackToRejoin(reason: "checkpoint_relay_session_id_mismatch")
    }

    private func scheduleAutoHideSessionRestoredSoftBanner() {
        bannerAutoHideTask?.cancel()
        bannerAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            if case .sessionRestoredSoft = self.relayLifecycleBanner {
                self.relayLifecycleBanner = .hidden
            }
        }
    }

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
        willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                LifecycleReconnectDebug.logWillResignActive()
                self?.scheduleBannerHiddenIfReconnecting()
            }
        }
        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                LifecycleReconnectDebug.logBackgroundEntered(source: "UIApplication.didEnterBackgroundNotification")
                self?.suspendPartnerSessionForBackground()
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
        if let willResignActiveObserver {
            NotificationCenter.default.removeObserver(willResignActiveObserver)
        }
        if let didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(didEnterBackgroundObserver)
        }
    }

    func setCheckpointDrift(displayRep: Int, coachRep: Int) {
        relayLifecycleBanner = .checkpointMismatch(
            hint: "Display reports rep \(displayRep + 1); coach is on rep \(coachRep + 1). Confirm with the player before continuing."
        )
    }

    func clearCheckpointDrift() {
        if case .checkpointMismatch = relayLifecycleBanner {
            relayLifecycleBanner = .hidden
        }
    }

    private func scheduleBannerHiddenIfReconnecting() {
        switch relayLifecycleBanner {
        case .reconnecting, .restoringSession:
            break
        default:
            return
        }
        bannerAutoHideTask?.cancel()
        bannerAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            switch self.relayLifecycleBanner {
            case .reconnecting, .restoringSession:
                self.relayLifecycleBanner = .hidden
            default:
                break
            }
        }
    }

    private func scheduleAutoHideRestoredBanner() {
        bannerAutoHideTask?.cancel()
        bannerAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            if case .connectionRestored = self.relayLifecycleBanner {
                self.relayLifecycleBanner = .hidden
            }
        }
    }

    /// After `suspendPartnerSessionForBackground()`, relay sockets are disconnected; reconnect when the app is active again.
    private func reconnectPartnerRelayAfterForegroundIfNeeded() async {
        guard isPartnerTrainingSessionActive else { return }
        awaitingSoftResumeCheckpointValidation = false

        LifecycleReconnectDebug.logForegroundEntered(source: "UIApplication.didBecomeActiveNotification")
        let beforeCoach = coachRelayRemoteService.connectionState
        let beforeDisplay = relayDisplaySession.socketConnectionState
        LifecycleReconnectDebug.logSocketState(role: "coach", before: beforeCoach.rawValue, after: "pending")
        LifecycleReconnectDebug.logSocketState(role: "display", before: beforeDisplay.rawValue, after: "pending")

        let displayHasRelaySession = relayDisplaySession.joinCode != nil
        let grace = RelaySoftResumeConfig.interruptionGraceSeconds
        let now = Date()
        let duration: TimeInterval = {
            guard let start = interruptionBeganAt else { return -1 }
            return now.timeIntervalSince(start)
        }()
        let softEligible = interruptionBeganAt != nil && duration >= 0 && duration <= grace
        RelaySoftResumeDebug.logInterruptionResume(
            duration: duration,
            graceSeconds: grace,
            eligible: softEligible
        )

        let hadDisconnect: Bool = displayHasRelaySession
            ? (beforeDisplay != .connected)
            : (beforeCoach != .connected)

        if hadDisconnect {
            relayLifecycleBanner = softEligible ? .restoringSession : .reconnecting
        }

        LifecycleReconnectDebug.logReconnectAttempt(context: "display.startDisplaySessionIfNeeded")
        await relayDisplaySession.startDisplaySessionIfNeeded()

        if coachRelayRemoteService.connectionState != .connected {
            LifecycleReconnectDebug.logReconnectAttempt(context: "coach.RemoteService.connect")
            coachRelayRemoteService.connect()
        }

        try? await Task.sleep(nanoseconds: 350_000_000)

        let afterCoach = coachRelayRemoteService.connectionState
        let afterDisplay = relayDisplaySession.socketConnectionState
        LifecycleReconnectDebug.logSocketState(role: "coach", before: beforeCoach.rawValue, after: afterCoach.rawValue)
        LifecycleReconnectDebug.logSocketState(role: "display", before: beforeDisplay.rawValue, after: afterDisplay.rawValue)

        let recovered: Bool = displayHasRelaySession
            ? (afterDisplay == .connected)
            : (afterCoach == .connected)

        RelaySoftResumeDebug.logReconnectOutcome(success: recovered, detail: displayHasRelaySession ? "display" : "coach")

        let socketDeadAfterForeground = displayHasRelaySession && afterDisplay == .disconnected && beforeDisplay == .connected
        if socketDeadAfterForeground {
            RelaySoftResumeDebug.logFallbackToRejoin(reason: "display_socket_not_recovered")
            relayLifecycleBanner = .sessionRequiresRejoin
            clearSoftResumeInterruptionState()
            NotificationCenter.default.post(name: .relayForegroundReconnectCompleted, object: nil)
            return
        }

        // Display (iPad): same relay session id after brief interrupt → soft resume without rejoin.
        if displayHasRelaySession, softEligible, recovered, hadDisconnect {
            let curId = relayDisplaySession.relaySessionId
            let idOK: Bool = {
                guard let snap = relaySessionIdSnapshotAtSuspend else { return true }
                guard let cur = curId else { return false }
                return snap == cur
            }()
            RelaySoftResumeDebug.logSessionValidation(
                passed: idOK,
                detail: "display_relay_session snapshot=\(relaySessionIdSnapshotAtSuspend ?? "nil") current=\(curId ?? "nil")"
            )
            if idOK {
                clearCheckpointDrift()
                relayLifecycleBanner = .sessionRestoredSoft
                scheduleAutoHideSessionRestoredSoftBanner()
                clearSoftResumeInterruptionState()
                RelaySoftResumeDebug.logSoftResumeOutcome(success: true, reason: "display_session_id_preserved")
                NotificationCenter.default.post(name: .relayForegroundReconnectCompleted, object: nil)
                return
            }
            RelaySoftResumeDebug.logFallbackToRejoin(reason: "display_relay_session_id_mismatch_after_soft_window")
            relayLifecycleBanner = .sessionRequiresRejoin
            clearSoftResumeInterruptionState()
            NotificationCenter.default.post(name: .relayForegroundReconnectCompleted, object: nil)
            return
        }

        // Coach iPhone: no local display join code; validate via display checkpoint if soft-eligible.
        if !displayHasRelaySession, softEligible, recovered, hadDisconnect {
            awaitingSoftResumeCheckpointValidation = true
            RelaySoftResumeDebug.logSoftResumeOutcome(success: false, reason: "coach_awaiting_checkpoint_validation")
            NotificationCenter.default.post(name: .relayForegroundReconnectCompleted, object: nil)
            #if DEBUG
            PartnerPersistDebug.log("UIApplication.didBecomeActive — coach soft-resume awaiting checkpoint")
            #endif
            return
        }

        if hadDisconnect, recovered {
            LifecycleReconnectDebug.logReconnectResult(context: "partner_relay", success: true, detail: displayHasRelaySession ? "display_socket_connected" : "coach_socket_connected")
            clearCheckpointDrift()
            relayLifecycleBanner = .connectionRestored
            scheduleAutoHideRestoredBanner()
            clearSoftResumeInterruptionState()
        } else if !hadDisconnect {
            relayLifecycleBanner = .hidden
            clearSoftResumeInterruptionState()
        } else {
            LifecycleReconnectDebug.logReconnectResult(context: "partner_relay", success: recovered, detail: "recovery_incomplete")
            if recovered {
                clearCheckpointDrift()
                relayLifecycleBanner = .connectionRestored
                scheduleAutoHideRestoredBanner()
                clearSoftResumeInterruptionState()
            } else if displayHasRelaySession, afterDisplay == .disconnected {
                relayLifecycleBanner = .sessionRequiresRejoin
                LifecycleReconnectDebug.logRejoinRequired(reason: "display_relay_still_disconnected")
                RelaySoftResumeDebug.logFallbackToRejoin(reason: "display_relay_still_disconnected_long_path")
                clearSoftResumeInterruptionState()
            } else {
                relayLifecycleBanner = .hidden
                clearSoftResumeInterruptionState()
            }
        }

        NotificationCenter.default.post(name: .relayForegroundReconnectCompleted, object: nil)
        #if DEBUG
        PartnerPersistDebug.log("UIApplication.didBecomeActive — reconnectPartnerRelayAfterForegroundIfNeeded complete")
        #endif
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
        trackedRelaySessionId = nil
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
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
        trackedRelaySessionId = nil
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden

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

    /// iOS background (springboard / multitasking / Siri / phone call): disconnect relay sockets — **keep** join code and training flag
    /// so the next drill can reconnect without a new join code. Does **not** send `sessionEnded` to coach.
    func suspendPartnerSessionForBackground() {
        guard isPartnerTrainingSessionActive else { return }
        if interruptionBeganAt == nil {
            let start = Date()
            interruptionBeganAt = start
            RelaySoftResumeDebug.logInterruptionStart(at: start)
        }
        relaySessionIdSnapshotAtSuspend = relayDisplaySession.relaySessionId ?? relaySessionIdSnapshotAtSuspend
        #if DEBUG
        print("[Multipeer] TrainingPartnerSession: suspend for iOS background — keep pairing; relay soft disconnect (display + coach)")
        #endif
        relayDisplaySession.suspendForAppBackground()
        if coachRelayRemoteService.connectionState != .disconnected {
            coachRelayRemoteService.disconnect()
        }
    }
}
