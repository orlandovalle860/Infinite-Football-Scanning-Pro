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

    /// Latest coach `sessionStarted` snapshot for the **display** (player iPad). Cleared when partner training ends.
    @Published private(set) var displaySessionState: DisplaySessionState?

    /// Bumps when the coach starts a drill so partner display routes can `.id(...)` a fresh engine + UI surface.
    @Published private(set) var partnerDisplaySurfaceId: UUID = UUID()

    /// Coach relay: display has joined the relay room (`peer_joined`). Drives passive link status on iPhone; cleared on disconnect / `peer_left`.
    @Published private(set) var coachRelayDisplayPeerPresent: Bool = false

    /// True after the first partner pairing starts; cleared only on ``endPartnerTrainingSession(reason:notifyPeer:)`` (explicit Leave,
    /// coach hub end, or ``AppRouter.popToRoot(endingPartnerSession: true)``). **Not** cleared on iOS background.
    @Published private(set) var isPartnerTrainingSessionActive: Bool = false

    /// Display (iPad) is showing the 3–2–1–Go overlay (``SessionCountdownModifier`` with coach-message suppression). Coach UI uses this to pause idle haptics.
    @Published private(set) var isPartnerDisplayCountdownActive: Bool = false
    /// Latest timed-session activity id mirrored from display for coach in-place sync.
    @Published private(set) var currentTimedSessionActivityId: String?
    /// Display finished instruction / countdown cue — coach may show TAP TO START (partner only).
    @Published private(set) var isDisplayRepEngineReady: Bool = false
    /// Display sent ``timedSessionActive`` — coach mirrors relay instead of rebroadcasting ``sessionStarted``.
    @Published private(set) var displayTimedSessionAnnounced: Bool = false
    /// Keeps the most recent non-nil activity id so coach UI stays stable during transient relay blips.
    @Published private(set) var lastNonNilActivityId: String?

    /// Last join code the coach successfully used for the shared relay WebSocket. Each activity’s coach remote is a **new** SwiftUI view with empty ``@State`` for the text field — without this, switching e.g. Away From Pressure → Dribble or Pass could not auto-reconnect with the same code.
    /// Cleared when pairing ends or when coach UI explicitly clears the join form after a real disconnect.
    private(set) var lastCoachRelayJoinCode: String?

    /// Session-scoped calibration state (one calibration per active partner training run).
    private(set) var sessionCalibrationResolved: Bool = false
    private(set) var sessionCalibrationAverageTravelTime: Double?
    private(set) var sessionCalibrationMode: TrainingMode?

    /// Bumps on each ``endPartnerTrainingSession`` / ``beginPartnerTrainingSessionIfNeeded`` transition so async relay notify completions cannot tear down a **new** session if the user starts the next run before the send finishes.
    private var relaySessionMutationToken: UInt64 = 0

    private var partnerTrainingEndedObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var willResignActiveObserver: NSObjectProtocol?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var recycleDisplayRelayDueToExpiredCodeObserver: NSObjectProtocol?
    private var coachRelayDisconnectCancellable: AnyCancellable?
    private var midSessionLinkCancellable: AnyCancellable?
    private var bannerAutoHideTask: Task<Void, Never>?
    /// Short grace window around transient system interruptions (e.g. screenshot UI) so brief socket flaps do not force relay recycle.
    private var transientLifecycleInterruptionUntil: Date?

    // MARK: - Mid-session disconnect (drill freeze + recovery)

    /// True only after transport was live **and** drill play had begun this partner run (used for mid-session disconnect eligibility).
    private var hadPartnerTransportLinkLiveThisSession: Bool = false
    /// True after drill play has begun (countdown finished, rep sync, or coach `nextRep`) so we do not show recovery during pairing/setup.
    private var hasStartedAtLeastOneRep: Bool = false
    /// Full-screen recovery UI while partner link drops mid-drill (both devices).
    @Published private(set) var isMidSessionPartnerDisconnect: Bool = false
    private var midSessionDisconnectDebounceToken: UUID?
    /// True after transport dropped while drilling (foreground only); cleared when link returns or session resets.
    private var linkDownSinceDrillUnderway: Bool = false
    /// True while iOS background suspend has torn down relay sockets — avoids treating that as a mid-drill drop for soft rep restart.
    private var partnerRelaySuspendedForBackground: Bool = false
    /// After foreground relay reconnect completes, ignore brief transport flaps that would post ``partnerSoftReconnectRepRestart`` and reset the display rep.
    private var partnerRelayForegroundReconnectCooldownUntil: Date?
    /// Suppresses duplicate `partnerSoftReconnectRepRestart` posts while a soft reconnect is in flight.
    private var isHandlingSoftReconnect: Bool = false
    /// Suppresses concurrent ``startNewPartnerSessionFromDisconnect(router:)`` (double-tap / overlapping Tasks).
    private var isStartingNewSession: Bool = false

    /// Set from ``relayDisplaySession.joinCode`` after a fresh relay mint in ``startNewPartnerSessionFromDisconnect``; `nil` while none / during reset. Prefer ``relayDisplaySession`` in SwiftUI; this nudges coordinator observers.
    @Published private(set) var currentJoinCode: String?

    // MARK: - Soft resume (grace window)

    /// When the relay was suspended (background); used with ``RelaySoftResumeConfig.interruptionGraceSeconds``.
    private var interruptionBeganAt: Date?
    /// Display relay session id captured at suspend; compared after reconnect for the same server session.
    private var relaySessionIdSnapshotAtSuspend: String?
    /// Server session id from display HTTP create or coach HTTP join (same logical session).
    private(set) var trackedRelaySessionId: String?
    /// Last relay server session id known to match the displayed join code (iPad display + coach join). Used after background to detect local/server drift.
    private var lastKnownValidRelaySessionId: String?
    /// Coach iPhone: brief reconnect succeeded; waiting for display ``partnerSessionCheckpoint`` to validate soft resume.
    private(set) var awaitingSoftResumeCheckpointValidation: Bool = false

    /// Call when the relay server session id is known (display session created or coach HTTP join).
    func recordRelaySessionId(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        trackedRelaySessionId = id
        lastKnownValidRelaySessionId = id
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
            Task { @MainActor in
                switch msg {
                case .partnerTrainingEnded:
                    self?.handleIncomingPartnerTrainingEndedFromPeer()
                case .timedSessionActive(let activityId, _):
                    self?.handleIncomingTimedSessionActiveFromDisplay(activityId: activityId)
                case .timedSessionInactive:
                    self?.handleIncomingTimedSessionInactiveFromDisplay()
                case .displayRepEngineReady(let activityId, _):
                    self?.handleIncomingDisplayRepEngineReadyFromDisplay(activityId: activityId)
                case .sessionEnded(let source, _):
                    self?.handleIncomingPartnerTimedSessionEnded(source: source)
                case .activityChanged(let activityId, _):
                    self?.handleIncomingActivityChangedFromCoach(activityId: activityId)
                default:
                    break
                }
            }
        }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.noteTransientLifecycleInterruption()
                await self?.reconnectPartnerRelayAfterForegroundIfNeeded()
            }
        }
        willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.noteTransientLifecycleInterruption()
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
                self?.transientLifecycleInterruptionUntil = nil
                LifecycleReconnectDebug.logBackgroundEntered(source: "UIApplication.didEnterBackgroundNotification")
                self?.suspendPartnerSessionForBackground()
            }
        }
        recycleDisplayRelayDueToExpiredCodeObserver = NotificationCenter.default.addObserver(
            forName: .relayDisplayRecycleRelayDueToExpiredJoinCode,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
                await self.recyclePlayerDisplayRelaySessionKeepingPartnerRun(reason: "coach_join_expired_same_process")
            }
        }
        coachRelayDisconnectCancellable = coachRelayRemoteService.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .disconnected {
                    self.coachRelayDisplayPeerPresent = false
                }
            }
        subscribeMidSessionPartnerLinkMonitoring()
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
        if let recycleDisplayRelayDueToExpiredCodeObserver {
            NotificationCenter.default.removeObserver(recycleDisplayRelayDueToExpiredCodeObserver)
        }
        midSessionDisconnectDebounceToken = nil
        midSessionLinkCancellable?.cancel()
    }

    func setCheckpointDrift(displayRep: Int, coachRep: Int) {
        guard !isTransientLifecycleInterruptionActive() else { return }
        relayLifecycleBanner = .checkpointMismatch(
            hint: "Display reports rep \(displayRep + 1); coach is on rep \(coachRep + 1). Confirm with the player before continuing."
        )
    }

    func clearCheckpointDrift() {
        if case .checkpointMismatch = relayLifecycleBanner {
            relayLifecycleBanner = .hidden
        }
    }

    /// True while relay reconnect / soft restore is in progress (partner training run still active).
    var isPartnerRelayReconnecting: Bool {
        switch relayLifecycleBanner {
        case .reconnecting, .restoringSession:
            return true
        default:
            return false
        }
    }

    /// Coach: HTTP join failed because the relay session or code expired — reset coach relay state and nudge player iPad (same app process only) to mint a new display session.
    @MainActor
    func recoverCoachRelayStateAfterExpiredJoinCode() {
        coachRelayRemoteService.disconnect()
        coachRelayDisplayPeerPresent = false
        clearRecordedCoachRelayJoinCode()
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        awaitingSoftResumeCheckpointValidation = false
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
        NotificationCenter.default.post(name: .relayDisplayRecycleRelayDueToExpiredJoinCode, object: nil)
    }

    /// Forward raw WebSocket text from the coach relay transport so shared UI can track `peer_joined` / `peer_left`.
    func ingestCoachRelayRawControlText(_ text: String) {
        if text.contains("peer_joined") {
            coachRelayDisplayPeerPresent = true
        }
        if text.lowercased().contains("peer_left") {
            coachRelayDisplayPeerPresent = false
        }
        refreshMidSessionPartnerDisconnectState()
    }

    /// Multipeer named peer, relay `peer_joined` on the display socket, or coach relay socket up with display in room.
    var isPartnerTransportLinkLive: Bool {
        guard isPartnerTrainingSessionActive else { return false }
        if ConnectionManager.shared.connectedPeerName != nil { return true }
        if relayDisplaySession.isCoachPaired { return true }
        if coachRelayRemoteService.connectionState == .connected, coachRelayDisplayPeerPresent { return true }
        return false
    }

    private func subscribeMidSessionPartnerLinkMonitoring() {
        let relaySock = relayDisplaySession.$socketConnectionState.map { _ in () }
        let relayPaired = relayDisplaySession.$isCoachPaired.map { _ in () }
        let coachSt = coachRelayRemoteService.$connectionState.map { _ in () }
        let mpSt = ConnectionManager.shared.$connectionState.map { _ in () }
        let mpPeer = ConnectionManager.shared.$connectedPeerName.map { _ in () }
        let coachPeer = $coachRelayDisplayPeerPresent.map { _ in () }
        let sessionActive = $isPartnerTrainingSessionActive.map { _ in () }

        midSessionLinkCancellable = relaySock
            .merge(with: relayPaired)
            .merge(with: coachSt)
            .merge(with: mpSt)
            .merge(with: mpPeer)
            .merge(with: coachPeer)
            .merge(with: sessionActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMidSessionPartnerDisconnectState()
            }
    }

    private func refreshMidSessionPartnerDisconnectState() {
        guard isPartnerTrainingSessionActive else {
            cancelMidSessionDisconnectDebounce()
            if isMidSessionPartnerDisconnect {
                clearMidSessionPartnerDisconnectState()
            }
            return
        }
        let live = isPartnerTransportLinkLive
        if live {
            if linkDownSinceDrillUnderway {
                let foregroundReconnectCooldownActive = partnerRelayForegroundReconnectCooldownUntil.map { Date() < $0 } ?? false
                if !partnerRelaySuspendedForBackground,
                   !foregroundReconnectCooldownActive,
                   !isTransientLifecycleInterruptionActive(),
                   shouldPartnerSoftReconnectPreserveRep() {
                    if isHandlingSoftReconnect {
                        linkDownSinceDrillUnderway = false
                    } else {
                        isHandlingSoftReconnect = true
                        linkDownSinceDrillUnderway = false
                        relayLifecycleBanner = .reconnectedRestartingRep
                        scheduleAutoHideReconnectedRestartingRepBanner()
                        NotificationCenter.default.post(name: .partnerSoftReconnectRepRestart, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                            self?.isHandlingSoftReconnect = false
                        }
                    }
                } else {
                    linkDownSinceDrillUnderway = false
                }
            }
            if hasStartedAtLeastOneRep {
                hadPartnerTransportLinkLiveThisSession = true
            }
            cancelMidSessionDisconnectDebounce()
            if case .reconnecting = relayLifecycleBanner {
                relayLifecycleBanner = .hidden
            }
            if isMidSessionPartnerDisconnect {
                isMidSessionPartnerDisconnect = false
            }
            return
        }
        if hadPartnerTransportLinkLiveThisSession, hasStartedAtLeastOneRep, !partnerRelaySuspendedForBackground {
            linkDownSinceDrillUnderway = true
        }
        guard hadPartnerTransportLinkLiveThisSession, hasStartedAtLeastOneRep else {
            cancelMidSessionDisconnectDebounce()
            return
        }
        guard !isMidSessionPartnerDisconnect else { return }
        scheduleMidSessionDisconnectOverlayIfNeeded()
    }

    private func cancelMidSessionDisconnectDebounce() {
        midSessionDisconnectDebounceToken = nil
    }

    private func scheduleMidSessionDisconnectOverlayIfNeeded() {
        guard midSessionDisconnectDebounceToken == nil else { return }
        let token = UUID()
        midSessionDisconnectDebounceToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.midSessionDisconnectDebounceToken == token else { return }
                self.midSessionDisconnectDebounceToken = nil
                guard self.isPartnerTrainingSessionActive else { return }
                guard !self.isPartnerTransportLinkLive else { return }
                guard self.hadPartnerTransportLinkLiveThisSession else { return }
                guard self.hasStartedAtLeastOneRep else { return }
                guard !self.isMidSessionPartnerDisconnect else { return }
                self.isMidSessionPartnerDisconnect = true
                self.relayDisplaySession.cancelRelayDisconnectRecycleTask()
            }
        }
    }

    private func clearMidSessionPartnerDisconnectState() {
        cancelMidSessionDisconnectDebounce()
        hadPartnerTransportLinkLiveThisSession = false
        hasStartedAtLeastOneRep = false
        isMidSessionPartnerDisconnect = false
        linkDownSinceDrillUnderway = false
        partnerRelaySuspendedForBackground = false
        isHandlingSoftReconnect = false
    }

    /// Whether transport came back with the same relay drill context so the current rep can restart without `CurrentSessionStore` / relay reset.
    @MainActor
    private func shouldPartnerSoftReconnectPreserveRep() -> Bool {
        guard isPartnerTrainingSessionActive else { return false }
        guard hasStartedAtLeastOneRep else { return false }
        guard isPartnerTransportLinkLive else { return false }
        guard let tid = trackedRelaySessionId, !tid.isEmpty else { return false }
        if CoachRemoteSessionStartGate.isPadPlayerRole() {
            guard let rid = relayDisplaySession.relaySessionId, rid == tid else { return false }
            guard relayDisplaySession.joinCode != nil else { return false }
            guard CurrentSessionStore.shared.sessionId != nil,
                  CurrentSessionStore.shared.currentSessionActivityId != nil else { return false }
            guard let dss = displaySessionState, dss.currentRepIndex >= 0 else { return false }
            guard dss.totalReps > 0 else { return false }
            if dss.currentRepIndex >= dss.totalReps { return false }
            return true
        }
        return true
    }

    /// Call when partner drill play has begun (display: countdown finished or rep index sync; coach: `nextRep` sent) so mid-session recovery does not appear before the block is actually running.
    @MainActor
    func markPartnerDrillUnderwayForMidSessionRecovery() {
        guard isPartnerTrainingSessionActive else { return }
        if hasStartedAtLeastOneRep { return }
        hasStartedAtLeastOneRep = true
        if isPartnerTransportLinkLive {
            hadPartnerTransportLinkLiveThisSession = true
        }
        refreshMidSessionPartnerDisconnectState()
    }

    /// Player iPad: **only** path for “Start New Session” after a mid-session disconnect — full local reset, new relay session + join code, Multipeer host restart, pop to root (partner run stays active).
    @MainActor
    func startNewPartnerSessionFromDisconnect(router: AppRouter) async {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard !isStartingNewSession else { return }
        isStartingNewSession = true
        defer { isStartingNewSession = false }

        currentJoinCode = nil
        lastKnownValidRelaySessionId = nil
        CurrentSessionStore.shared.clear()
        displaySessionState = nil
        trackedRelaySessionId = nil
        relaySessionMutationToken += 1
        awaitingSoftResumeCheckpointValidation = false
        clearSoftResumeInterruptionState()
        clearRecordedCoachRelayJoinCode()
        relayLifecycleBanner = .hidden
        partnerDisplaySurfaceId = UUID()
        coachRelayDisplayPeerPresent = false
        clearMidSessionPartnerDisconnectState()

        relayDisplaySession.stopHosting()
        try? await Task.sleep(nanoseconds: 200_000_000)
        await relayDisplaySession.resetSession()

        currentJoinCode = relayDisplaySession.joinCode

        print("NEW SESSION CREATED:", relayDisplaySession.relaySessionId as Any)
        print("NEW JOIN CODE:", relayDisplaySession.joinCode as Any)

        if relayDisplaySession.joinCode == nil {
            #if DEBUG
            print("[Partner] startNewPartnerSessionFromDisconnect: joinCode missing after reset — join prompt may be empty until relay recovers")
            #endif
        }

        NotificationCenter.default.post(name: .partnerDisplayWillStartNewSessionFromDisconnect, object: nil)

        ConnectionManager.shared.stopHosting()
        prepareMultipeerDisplayPartner(connectionManager: ConnectionManager.shared)
        router.navigateToPlayerDisplayJoinPromptAfterPartnerSessionReset()
    }

    /// Player iPad: remote dropped mid-session — forwards to ``startNewPartnerSessionFromDisconnect(router:)``.
    @MainActor
    func handleDisplayStartNewSessionAfterRemoteDisconnect(router: AppRouter) async {
        await startNewPartnerSessionFromDisconnect(router: router)
    }

    /// Coach device: display relay unavailable mid-session — leave drill UI, clear stale relay join state, return to hub join step (pairing run stays active). Does **not** notify the display.
    @MainActor
    func handleCoachEnterCodeAfterDisplayUnavailable(router: AppRouter) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        relaySessionMutationToken += 1
        coachRelayRemoteService.disconnect()
        coachRelayDisplayPeerPresent = false
        clearRecordedCoachRelayJoinCode()
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        awaitingSoftResumeCheckpointValidation = false
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
        displaySessionState = nil
        partnerDisplaySurfaceId = UUID()
        clearMidSessionPartnerDisconnectState()
        ConnectionManager.shared.stopBrowsing()
        prepareMultipeerCoachRemote(connectionManager: ConnectionManager.shared)
        print("[Partner] Coach ready for new code — relay disconnected, cached join code cleared, Multipeer browsing restarted")
        router.popToRoot(endingPartnerSession: false)
    }

    /// Player iPad: replace the display relay with a fresh `/v1/sessions` + join code while keeping the partner training run active.
    @MainActor
    func recyclePlayerDisplayRelaySessionKeepingPartnerRun(reason: String) async {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        if TimedSessionController.shared.isManagingSession,
           CurrentSessionStore.shared.sessionId != nil {
            RelaySoftResumeDebug.logFallbackToRejoin(reason: "\(reason)_skipped_preserve_training_session")
            await relayDisplaySession.startDisplaySessionIfNeeded()
            return
        }
        RelaySoftResumeDebug.logFallbackToRejoin(reason: "\(reason)_ipad_auto_recycle")
        relayDisplaySession.cancelRelayDisconnectRecycleTask()
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
        await forceRegenerateIPadDisplayRelaySessionAfterForeground(reason: "\(reason)_ipad_auto_recycle")
    }

    /// Player iPad: tear down relay and `POST /v1/sessions` so join code + `relaySessionId` stay aligned with the server.
    @MainActor
    private func forceRegenerateIPadDisplayRelaySessionAfterForeground(reason: String) async {
        relayDisplaySession.stopHosting()
        try? await Task.sleep(nanoseconds: 200_000_000)
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        await relayDisplaySession.resetSession()
        await MainActor.run {
            self.currentJoinCode = self.relayDisplaySession.joinCode
        }
        if let rid = relayDisplaySession.relaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
            lastKnownValidRelaySessionId = rid
        }
        #if DEBUG
        print("[RelayWS-DEBUG] iPad relay regen (\(reason)) joinCode=\(relayDisplaySession.joinCode ?? "nil") sessionId=\(relayDisplaySession.relaySessionId ?? "nil")")
        #endif
    }

    /// Player iPad: after foreground reconnect, validate socket + session id vs last known good state; mint a new relay if join code may not match the server session.
    @MainActor
    private func mintFreshIPadDisplayRelaySessionWhenForegroundReconnectStillOffline() async {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        if TimedSessionController.shared.isManagingSession,
           CurrentSessionStore.shared.sessionId != nil {
            await relayDisplaySession.startDisplaySessionIfNeeded()
            return
        }
        let joinTrimmed = relayDisplaySession.joinCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if joinTrimmed.isEmpty {
            await forceRegenerateIPadDisplayRelaySessionAfterForeground(reason: "foreground_missing_join_code")
            return
        }
        if relayDisplaySession.socketConnectionState == .connecting || relayDisplaySession.socketConnectionState == .searching {
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        let curId = relayDisplaySession.relaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let connected = relayDisplaySession.isRelaySocketConnected
        let idMissing = curId.isEmpty

        let idDriftFromLastKnown: Bool = {
            guard let last = lastKnownValidRelaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty else { return false }
            return last != curId
        }()

        let idDriftFromTracked: Bool = {
            guard let t = trackedRelaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
                  !curId.isEmpty else { return false }
            return t != curId
        }()

        let needsRegen = !connected || idMissing || idDriftFromLastKnown || idDriftFromTracked

        if needsRegen {
            await forceRegenerateIPadDisplayRelaySessionAfterForeground(
                reason: "foreground_relay_validation connected=\(connected) idMissing=\(idMissing) driftLast=\(idDriftFromLastKnown) driftTracked=\(idDriftFromTracked)"
            )
            return
        }

        await MainActor.run {
            self.currentJoinCode = self.relayDisplaySession.joinCode
        }
        lastKnownValidRelaySessionId = curId
    }

    private func postRelayForegroundReconnectCompleted(postCheckpointResync: Bool = true) async {
        if postCheckpointResync {
            await mintFreshIPadDisplayRelaySessionWhenForegroundReconnectStillOffline()
        }
        await finalizeRelayForegroundReconnectNotifications(postCheckpointResync: postCheckpointResync)
    }

    /// Posts `relayForegroundReconnectCompleted` and clears background-suspend bookkeeping (without mint/validation).
    private func finalizeRelayForegroundReconnectNotifications(postCheckpointResync: Bool = true) async {
        if postCheckpointResync {
            NotificationCenter.default.post(name: .relayForegroundReconnectCompleted, object: nil)
        }
        partnerRelayForegroundReconnectCooldownUntil = Date().addingTimeInterval(0.75)
        partnerRelaySuspendedForBackground = false
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

    private func noteTransientLifecycleInterruption() {
        transientLifecycleInterruptionUntil = Date().addingTimeInterval(2.5)
    }

    /// True briefly around `willResignActive`/`didBecomeActive` to avoid treating transient system overlays as hard relay drops.
    func shouldSuppressUnexpectedRelayRecycleNow() -> Bool {
        guard let until = transientLifecycleInterruptionUntil else { return false }
        if Date() < until { return true }
        transientLifecycleInterruptionUntil = nil
        return false
    }

    /// Screenshot / control-center style interruption — not a true iOS background suspend.
    func isTransientLifecycleInterruptionActive() -> Bool {
        shouldSuppressUnexpectedRelayRecycleNow() && !partnerRelaySuspendedForBackground
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

    private func scheduleAutoHideReconnectedRestartingRepBanner() {
        bannerAutoHideTask?.cancel()
        bannerAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            if case .reconnectedRestartingRep = self.relayLifecycleBanner {
                self.relayLifecycleBanner = .hidden
            }
        }
    }

    /// After `suspendPartnerSessionForBackground()`, relay sockets are disconnected; reconnect when the app is active again.
    private func reconnectPartnerRelayAfterForegroundIfNeeded() async {
        guard isPartnerTrainingSessionActive else {
            partnerRelaySuspendedForBackground = false
            return
        }
        awaitingSoftResumeCheckpointValidation = false
        let silentTransientReconnect = isTransientLifecycleInterruptionActive()

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

        if hadDisconnect, !silentTransientReconnect {
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
            if silentTransientReconnect {
                await postRelayForegroundReconnectCompleted(postCheckpointResync: false)
                return
            }
            if CoachRemoteSessionStartGate.isPadPlayerRole() {
                await recyclePlayerDisplayRelaySessionKeepingPartnerRun(reason: "display_socket_not_recovered_after_foreground")
            } else {
                RelaySoftResumeDebug.logFallbackToRejoin(reason: "display_socket_not_recovered")
                relayLifecycleBanner = .sessionRequiresRejoin
                clearSoftResumeInterruptionState()
            }
            await postRelayForegroundReconnectCompleted()
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
                if !silentTransientReconnect {
                    relayLifecycleBanner = .sessionRestoredSoft
                    scheduleAutoHideSessionRestoredSoftBanner()
                }
                clearSoftResumeInterruptionState()
                RelaySoftResumeDebug.logSoftResumeOutcome(success: true, reason: "display_session_id_preserved")
                await postRelayForegroundReconnectCompleted(postCheckpointResync: !silentTransientReconnect)
                return
            }
            if CoachRemoteSessionStartGate.isPadPlayerRole() {
                await recyclePlayerDisplayRelaySessionKeepingPartnerRun(reason: "display_relay_session_id_mismatch_after_soft_window")
            } else {
                RelaySoftResumeDebug.logFallbackToRejoin(reason: "display_relay_session_id_mismatch_after_soft_window")
                relayLifecycleBanner = .sessionRequiresRejoin
                clearSoftResumeInterruptionState()
            }
            await postRelayForegroundReconnectCompleted()
            return
        }

        // Coach iPhone: no local display join code; validate via display checkpoint if soft-eligible.
        if !displayHasRelaySession, softEligible, recovered, hadDisconnect {
            awaitingSoftResumeCheckpointValidation = true
            RelaySoftResumeDebug.logSoftResumeOutcome(success: false, reason: "coach_awaiting_checkpoint_validation")
            await postRelayForegroundReconnectCompleted()
            #if DEBUG
            PartnerPersistDebug.log("UIApplication.didBecomeActive — coach soft-resume awaiting checkpoint")
            #endif
            return
        }

        if hadDisconnect, recovered {
            LifecycleReconnectDebug.logReconnectResult(context: "partner_relay", success: true, detail: displayHasRelaySession ? "display_socket_connected" : "coach_socket_connected")
            clearCheckpointDrift()
            if !silentTransientReconnect {
                relayLifecycleBanner = .connectionRestored
                scheduleAutoHideRestoredBanner()
            }
            clearSoftResumeInterruptionState()
        } else if !hadDisconnect {
            relayLifecycleBanner = .hidden
            clearSoftResumeInterruptionState()
        } else {
            LifecycleReconnectDebug.logReconnectResult(context: "partner_relay", success: recovered, detail: "recovery_incomplete")
            if recovered {
                clearCheckpointDrift()
                if !silentTransientReconnect {
                    relayLifecycleBanner = .connectionRestored
                    scheduleAutoHideRestoredBanner()
                }
                clearSoftResumeInterruptionState()
            } else if displayHasRelaySession, afterDisplay == .disconnected {
                if CoachRemoteSessionStartGate.isPadPlayerRole() {
                    await recyclePlayerDisplayRelaySessionKeepingPartnerRun(reason: "display_relay_still_disconnected_long_path")
                } else {
                    relayLifecycleBanner = .sessionRequiresRejoin
                    LifecycleReconnectDebug.logRejoinRequired(reason: "display_relay_still_disconnected")
                    RelaySoftResumeDebug.logFallbackToRejoin(reason: "display_relay_still_disconnected_long_path")
                    clearSoftResumeInterruptionState()
                }
            } else {
                relayLifecycleBanner = .hidden
                clearSoftResumeInterruptionState()
            }
        }

        await postRelayForegroundReconnectCompleted(postCheckpointResync: !silentTransientReconnect)
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

    /// Clears the stored coach join code. Only the coordinator should do this as part of an explicit partner-session end.
    private func clearRecordedCoachRelayJoinCode() {
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
        clearMidSessionPartnerDisconnectState()
        relaySessionMutationToken += 1
        let adoptExistingRelay = relayDisplaySession.hasAdoptableRelaySession
        if !adoptExistingRelay {
            relayDisplaySession.tearDown()
        }
        coachRelayRemoteService.disconnect()
        #if DEBUG
        if adoptExistingRelay {
            PartnerPersistDebug.log("beginPartnerTrainingSessionIfNeeded — adopting existing display relay (coach-link warm-up)")
        } else {
            EndTrainingDebug.log("beginPartnerTrainingSessionIfNeeded — cleared stale relay transports before new run")
        }
        #endif
        if !adoptExistingRelay {
            ConnectionManager.shared.stopHosting()
            ConnectionManager.shared.stopBrowsing()
        }
        isPartnerTrainingSessionActive = true
        isPartnerDisplayCountdownActive = false
        isDisplayRepEngineReady = false
        displayTimedSessionAnnounced = false
        CurrentSessionStore.shared.resetPartnerTimedSessionEndHandled()
        sessionCalibrationResolved = true
        sessionCalibrationAverageTravelTime = PartnerPassTempoCalibrationStore.seededAverageTravelTimeSeconds()
        sessionCalibrationMode = .partner
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
        #if DEBUG
        print("[Multipeer] TrainingPartnerSession: begin — partner training session active (relay + Multipeer reuse allowed)")
        PartnerPersistDebug.log("beginPartnerTrainingSessionIfNeeded — marked partner training session active")
        #endif
        refreshMidSessionPartnerDisconnectState()
    }

    /// Called from ``SessionCountdownModifier`` when the display shows or hides 3–2–1–Go (partner drills with coach suppression).
    func setPartnerDisplayCountdownActive(_ active: Bool) {
        guard isPartnerDisplayCountdownActive != active else { return }
        let wasShowingCountdown = isPartnerDisplayCountdownActive
        isPartnerDisplayCountdownActive = active
        if wasShowingCountdown, !active {
            markPartnerDrillUnderwayForMidSessionRecovery()
        }
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
        clearMidSessionPartnerDisconnectState()
        relaySessionMutationToken += 1
        let endToken = relaySessionMutationToken
        isPartnerTrainingSessionActive = false
        isPartnerDisplayCountdownActive = false
        currentTimedSessionActivityId = nil
        isDisplayRepEngineReady = false
        displayTimedSessionAnnounced = false
        lastNonNilActivityId = nil
        TimedSessionController.shared.prepareCoachRemoteForPartnerDurationSelection()
        currentJoinCode = nil
        displaySessionState = nil
        partnerDisplaySurfaceId = UUID()
        clearRecordedCoachRelayJoinCode()
        sessionCalibrationResolved = false
        sessionCalibrationAverageTravelTime = nil
        sessionCalibrationMode = nil
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
        CurrentSessionStore.shared.clear()

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

    /// Player Display Disconnect from Connected standby — ends an active partner run, or forcibly clears an orphan warm-up link so Home is never trapped.
    @MainActor
    func disconnectPlayerDisplayFromCoach(reason: String = "iPadConnectedStandby.disconnect") {
        if isPartnerTrainingSessionActive {
            endPartnerTrainingSession(reason: reason, notifyPeer: true)
            return
        }
        #if DEBUG
        EndTrainingDebug.log("disconnectPlayerDisplayFromCoach — orphan link teardown reason=\(reason)")
        #endif
        clearMidSessionPartnerDisconnectState()
        relaySessionMutationToken += 1
        isPartnerDisplayCountdownActive = false
        currentTimedSessionActivityId = nil
        isDisplayRepEngineReady = false
        displayTimedSessionAnnounced = false
        lastNonNilActivityId = nil
        TimedSessionController.shared.prepareCoachRemoteForPartnerDurationSelection()
        currentJoinCode = nil
        displaySessionState = nil
        partnerDisplaySurfaceId = UUID()
        clearRecordedCoachRelayJoinCode()
        sessionCalibrationResolved = false
        sessionCalibrationAverageTravelTime = nil
        sessionCalibrationMode = nil
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
        CurrentSessionStore.shared.clear()
        relayDisplaySession.tearDown()
        coachRelayRemoteService.disconnect()
        ConnectionManager.shared.stopHosting()
        ConnectionManager.shared.stopBrowsing()
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

    /// True while background suspend is active or briefly after foreground relay reconnect — skip ``partnerSoftReconnectRepRestart`` so rep index is not reset.
    var isPartnerSoftReconnectRepRestartSuppressed: Bool {
        partnerRelaySuspendedForBackground || (partnerRelayForegroundReconnectCooldownUntil.map { Date() < $0 } ?? false)
    }

    /// Global partner connection state for activity entry gates. True means the existing partner pairing
    /// should be reused and activities should skip fresh role/join flows.
    var isConnected: Bool {
        guard isPartnerTrainingSessionActive else { return false }
        return isPartnerTransportLinkLive
    }

    func markSessionCalibrationResolved(averageTravelTimeSeconds: Double?, trainingMode: TrainingMode?) {
        sessionCalibrationResolved = true
        sessionCalibrationAverageTravelTime = averageTravelTimeSeconds
        sessionCalibrationMode = trainingMode
    }

    // MARK: - Display session (coach sessionStarted)

    /// **Step 1 of display handling:** record authoritative block metadata from the phone. Does **not** navigate.
    func applySessionStartedFromCoach(activityId: String, totalReps: Int, startedAt: Date) {
        let id = UUID()
        partnerDisplaySurfaceId = id
        displaySessionState = DisplaySessionState(
            instanceId: id,
            activityId: activityId,
            totalReps: max(1, totalReps),
            currentRepIndex: 0,
            startedAt: startedAt
        )
    }

    /// Display: keep `currentRepIndex` aligned with the engine for reconnect / UI (best-effort).
    func syncDisplaySessionCurrentRepIndex(_ index: Int, activityId: String) {
        guard var state = displaySessionState, state.activityId == activityId else { return }
        state.currentRepIndex = index
        displaySessionState = state
        markPartnerDrillUnderwayForMidSessionRecovery()
    }

    /// Authoritative rep index (0-based) from the last coach `sessionStarted` + display sync — use after background to realign a recreated engine.
    func authoritativePartnerDisplayRepIndex(for activityId: String) -> Int? {
        guard let s = displaySessionState, s.activityId == activityId else { return nil }
        return s.currentRepIndex
    }

    /// Partner display block size: uses ``displaySessionState`` when it matches this activity; otherwise `soloFallback` (manual / solo entry).
    func partnerBlockTotalReps(activityId: String, soloFallback: Int, mode: TrainingMode) -> Int {
        guard mode.requiresPhoneDisplayRelay,
              let s = displaySessionState,
              s.activityId == activityId else { return soloFallback }
        return max(1, s.totalReps)
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

    /// Coach phone: mirror display timed-session state for rep gating (local + relay).
    func applyCoachTimedSessionMirror(activityId: String) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        currentTimedSessionActivityId = activityId
        lastNonNilActivityId = activityId
        isDisplayRepEngineReady = false
        TimedSessionController.shared.prepareCoachRemoteForPartnerDurationSelection()
    }

    /// Coach device: notify the display to open the partner session UI for this activity (relay WebSocket and/or Multipeer).
    func broadcastSessionStartedFromCoach(activity: ActivityKind, totalReps: Int) {
        applyCoachTimedSessionMirror(activityId: activity.sessionActivityActivityId)
        print("[COACH OUT] sessionStarted activity=\(activity.sessionActivityActivityId)")
        let msg = TwoMinuteMessage.sessionStarted(
            activityId: activity.sessionActivityActivityId,
            totalReps: totalReps,
            timestamp: Date()
        )
        if coachRelayRemoteService.connectionState == .connected {
            coachRelayRemoteService.send(msg, completion: nil)
        }
        if ConnectionManager.shared.connectedPeerName != nil {
            ConnectionManager.shared.sendTwoMinuteMessage(msg)
        }
    }

    /// Coach remote: ensure rep UI is armed before / when broadcasting ``sessionStarted``.
    func prepareCoachRemoteForBroadcastSessionStart(activity: ActivityKind) {
        applyCoachTimedSessionMirror(activityId: activity.sessionActivityActivityId)
    }

    /// Coach remote onAppear: re-enable rep UI when display session mirror is already known.
    func restoreCoachTimedSessionMirrorIfNeeded() {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive, let activityId = currentTimedSessionActivityId else { return }
        lastNonNilActivityId = activityId
        if isDisplayRepEngineReady {
            TimedSessionController.shared.markPartnerDisplaySessionActiveFromRelay()
        }
    }

    /// Timed partner sessions are display-led once the display has an announced **live** timed drill.
    /// Until then, coach must send legacy ``sessionStarted`` so the iPad can leave Home standby.
    /// - Important: do not defer on a stale `displayTimedSessionAnnounced` alone after session end —
    ///   that deadlocks hub Start Session (coach skips `sessionStarted`, iPad waits forever).
    func shouldCoachDeferToDisplayTimedSession() -> Bool {
        guard isPartnerTrainingSessionActive else { return false }
        restoreCoachTimedSessionMirrorIfNeeded()
        guard displayTimedSessionAnnounced else { return false }
        return isDisplayRepEngineReady || TimedSessionController.shared.isSessionActive
    }

    /// Coach hub activity tile — clear stale timed-session flags so `sessionStarted` wakes display standby.
    func beginCoachHubActivityLaunch(activity: ActivityKind) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        displayTimedSessionAnnounced = false
        isDisplayRepEngineReady = false
        CurrentSessionStore.shared.resetPartnerTimedSessionEndHandled()
        applyCoachTimedSessionMirror(activityId: activity.sessionActivityActivityId)
    }

    /// Display (iPad): timed session container is live — coach tracks activity; rep UI waits for ``displayRepEngineReady``.
    func broadcastTimedSessionActiveFromDisplay(activity: ActivityKind) {
        let msg = TwoMinuteMessage.timedSessionActive(
            activityId: activity.sessionActivityActivityId,
            timestamp: Date()
        )
        var sent = false
        if relayDisplaySession.socketConnectionState == .connected {
            relayDisplaySession.sendTwoMinuteMessage(msg)
            sent = true
        }
        if ConnectionManager.shared.connectedPeerName != nil {
            ConnectionManager.shared.sendTwoMinuteMessage(msg)
            sent = true
        }
        if sent {
            print("[DISPLAY OUT] timedSessionActive activity=\(activity.sessionActivityActivityId)")
        } else {
            print("[DISPLAY OUT] timedSessionActive DROPPED — no relay/multipeer transport activity=\(activity.sessionActivityActivityId)")
        }
    }

    /// Re-send timed session active after relay reconnect if display session is still live.
    func rebroadcastTimedSessionActiveFromDisplayIfNeeded() {
        let timed = TimedSessionController.shared
        guard timed.mode == .partner, timed.isManagingSession, timed.isSessionActive else { return }
        guard let activity = timed.currentActivity else { return }
        broadcastTimedSessionActiveFromDisplay(activity: activity)
    }

    /// Display (iPad): instruction / countdown cue finished — coach may show TAP TO START.
    func broadcastDisplayRepEngineReadyFromDisplay(activity: ActivityKind) {
        let msg = TwoMinuteMessage.displayRepEngineReady(
            activityId: activity.sessionActivityActivityId,
            timestamp: Date()
        )
        var sent = false
        if relayDisplaySession.socketConnectionState == .connected {
            relayDisplaySession.sendTwoMinuteMessage(msg)
            sent = true
        }
        if ConnectionManager.shared.connectedPeerName != nil {
            ConnectionManager.shared.sendTwoMinuteMessage(msg)
            sent = true
        }
        if sent {
            print("[DISPLAY OUT] displayRepEngineReady activity=\(activity.sessionActivityActivityId)")
        } else {
            print("[DISPLAY OUT] displayRepEngineReady DROPPED — no relay/multipeer transport activity=\(activity.sessionActivityActivityId)")
        }
    }

    /// Re-send rep-engine-ready after relay reconnect if the display cue already finished.
    func rebroadcastDisplayRepEngineReadyFromDisplayIfNeeded() {
        let timed = TimedSessionController.shared
        guard timed.mode == .partner, timed.isManagingSession, timed.isSessionActive else { return }
        guard SessionStartCueRepGate.shouldBroadcastDisplayRepEngineReady else { return }
        guard let activity = timed.currentActivity else { return }
        broadcastDisplayRepEngineReadyFromDisplay(activity: activity)
    }

    /// Display (iPad): awaiting duration selection or session ended — coach must wait.
    func broadcastTimedSessionInactiveFromDisplay() {
        let msg = TwoMinuteMessage.timedSessionInactive(timestamp: Date())
        if relayDisplaySession.socketConnectionState == .connected {
            relayDisplaySession.sendTwoMinuteMessage(msg)
        }
        if ConnectionManager.shared.connectedPeerName != nil {
            ConnectionManager.shared.sendTwoMinuteMessage(msg)
        }
    }

    /// Coach phone only: display session container live — hold rep UI until instruction cue finishes.
    private func handleIncomingTimedSessionActiveFromDisplay(activityId: String) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        print("[COACH INPUT] timedSessionActive activityId=\(activityId)")
        let sameActivity = currentTimedSessionActivityId == activityId
        currentTimedSessionActivityId = activityId
        lastNonNilActivityId = activityId
        displayTimedSessionAnnounced = true
        CurrentSessionStore.shared.resetPartnerTimedSessionEndHandled()
        Task { await attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(reason: "display_timedSessionActive") }
        // Rebroadcast while coach already unlocked (or mid first-rep wait) must not flash
        // "Waiting for player…" and then TAP TO START again.
        if sameActivity, isDisplayRepEngineReady {
            print("[COACH STATE] timedSessionActive rebroadcast — keeping repEngineReady activityId=\(activityId)")
            return
        }
        isDisplayRepEngineReady = false
        TimedSessionController.shared.prepareCoachRemoteForPartnerDurationSelection()
        print("[COACH STATE] currentTimedSessionActivityId=\(currentTimedSessionActivityId ?? "nil") ready=false")
    }

    /// Coach phone only: display instruction cue finished — unlock TAP TO START.
    private func handleIncomingDisplayRepEngineReadyFromDisplay(activityId: String) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        let repEngineWasReady = isDisplayRepEngineReady
        if isDisplayRepEngineReady, currentTimedSessionActivityId == activityId {
            print("[COACH STATE] displayRepEngineReady duplicate ignored activityId=\(activityId)")
            return
        }
        print("[COACH INPUT] displayRepEngineReady activityId=\(activityId)")
        currentTimedSessionActivityId = activityId
        lastNonNilActivityId = activityId
        isDisplayRepEngineReady = true
        TimedSessionController.shared.markPartnerDisplaySessionActiveFromRelay()
        print("[COACH STATE] currentTimedSessionActivityId=\(currentTimedSessionActivityId ?? "nil") ready=true")
        Task { await attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(reason: "display_repEngineReady") }
        if !repEngineWasReady {
            NotificationCenter.default.post(
                name: .partnerDisplayRepEngineBecameReady,
                object: activityId
            )
        }
    }

    /// Coach phone only: display not ready or session ended.
    private func handleIncomingTimedSessionInactiveFromDisplay() {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        // Ignore only while a fully live drill is running. Stale `timedSessionInactive` after End Session
        // must clear announce flags so the next hub Start Session can send `sessionStarted`.
        if isPartnerTrainingSessionActive,
           isDisplayRepEngineReady,
           currentTimedSessionActivityId != nil {
            print("[COACH STATE] timedSessionInactive ignored — live drill id=\(currentTimedSessionActivityId!)")
            return
        }
        #if DEBUG
        print("[COACH STATE] timedSessionInactive — clearing announce/ready for next hub start")
        #endif
        isDisplayRepEngineReady = false
        displayTimedSessionAnnounced = false
        TimedSessionController.shared.prepareCoachRemoteForPartnerDurationSelection()
    }

    private func handleIncomingSessionEndedForCoachMirror() {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        currentTimedSessionActivityId = nil
        isDisplayRepEngineReady = false
        displayTimedSessionAnnounced = false
        TimedSessionController.shared.prepareCoachRemoteForPartnerDurationSelection()
    }

    /// Timed partner session ended — reset drill state but keep relay, join code, and ``isPartnerTrainingSessionActive``.
    func softResetAfterTimedPartnerSessionEnd() {
        guard isPartnerTrainingSessionActive else { return }
        currentTimedSessionActivityId = nil
        isDisplayRepEngineReady = false
        displayTimedSessionAnnounced = false
        isPartnerDisplayCountdownActive = false
        TimedSessionController.shared.prepareCoachRemoteForPartnerDurationSelection()
        CurrentSessionStore.shared.resetPartnerTimedSessionEndHandled()
        #if DEBUG
        print("[Multipeer] TrainingPartnerSession: softResetAfterTimedPartnerSessionEnd — pairing preserved")
        PartnerPersistDebug.log("softResetAfterTimedPartnerSessionEnd — relay + join code preserved")
        #endif
    }

    /// Broadcast timed partner session end to the peer device.
    func broadcastPartnerTimedSessionEnded(source: PartnerSessionEndSource) {
        let msg = TwoMinuteMessage.sessionEnded(source: source, timestamp: Date())
        print("[RELAY OUT] sessionEnded source=\(source.rawValue)")
        if coachRelayRemoteService.connectionState == .connected {
            coachRelayRemoteService.send(msg, completion: nil)
        }
        if relayDisplaySession.socketConnectionState == .connected {
            relayDisplaySession.sendTwoMinuteMessage(msg)
        }
        if ConnectionManager.shared.connectedPeerName != nil {
            ConnectionManager.shared.sendTwoMinuteMessage(msg)
        }
    }

    private func handleIncomingPartnerTimedSessionEnded(source: PartnerSessionEndSource) {
        print("[RELAY IN] sessionEnded source=\(source.rawValue)")
        if CoachRemoteSessionStartGate.isPadPlayerRole() {
            guard source == .coach else { return }
            // Partner timed session lives on the display TimedSessionController.
            let timed = TimedSessionController.shared
            guard timed.isManagingSession, timed.isSessionActive || SoloTimeBasedSession.isActive else {
                print("[DISPLAY STATE] sessionEnded from coach ignored — no active timed session")
                return
            }
            NotificationCenter.default.post(name: .coachEndTimedSessionRequested, object: nil)
            return
        }
        guard source == .display else { return }
        guard isPartnerTrainingSessionActive else { return }
        // Accept end of the *current* live timed run. Do not ignore when ready/activityId are set —
        // that is exactly when the coach must leave the drill UI. Dedup via tryMark; Train Again
        // resets the flag on the next timedSessionActive.
        guard CurrentSessionStore.shared.tryMarkPartnerTimedSessionEndHandled() else {
            print("[COACH STATE] sessionEnded from display ignored — already handled")
            return
        }
        handleIncomingSessionEndedForCoachMirror()
        NotificationCenter.default.post(name: .partnerTimedSessionEndedFromDisplay, object: nil)
    }

    /// Coach phone: re-join relay using the stored join code (Train Again / hub tap while socket dropped or zombie).
    func attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(reason: String) async {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard let code = lastCoachRelayJoinCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else {
            #if DEBUG
            print("[CoachRelay] auto-reconnect skipped reason=\(reason) — no stored join code")
            #endif
            return
        }

        let linkLive = isPartnerTransportLinkLive
        guard !linkLive else {
            #if DEBUG
            print("[CoachRelay] auto-reconnect skipped reason=\(reason) — transport already live")
            #endif
            return
        }

        if coachRelayRemoteService.connectionState == .connected {
            #if DEBUG
            print("[CoachRelay] stale socket (connected, no peer) — disconnecting before re-join reason=\(reason)")
            #endif
            coachRelayRemoteService.disconnect()
            coachRelayDisplayPeerPresent = false
        }

        #if DEBUG
        print("[CoachRelay] auto-reconnect starting reason=\(reason) joinCode=\(code)")
        #endif
        do {
            let joined = try await WebSocketSessionAPI.joinSession(joinCode: code)
            let wsURL = try joined.webSocketURLForCoach()
            recordRelaySessionId(joined.sessionId)
            let config = WebSocketSessionConfig(url: wsURL, sessionId: joined.sessionId, authToken: joined.coachToken)
            let transport = WebSocketRemoteTransport(config: config)
            let remote = coachRelayRemoteService
            transport.onRawTextReceived = { text in
                TrainingPartnerConnectionCoordinator.shared.ingestCoachRelayRawControlText(text)
                if text.lowercased().contains("peer_left") {
                    Task { @MainActor in
                        remote.disconnect()
                    }
                }
            }
            recordCoachRelayJoinCode(code)
            remote.replaceTransport(transport)
            remote.connect()
            #if DEBUG
            print("[CoachRelay] auto-reconnect ok reason=\(reason) — awaiting peer_joined for live link")
            #endif
        } catch {
            #if DEBUG
            print("[CoachRelay] auto-reconnect failed reason=\(reason) error=\(error.localizedDescription)")
            #endif
            if WebSocketSessionAPI.isInvalidOrExpiredJoinSessionError(error) {
                recoverCoachRelayStateAfterExpiredJoinCode()
            }
        }
    }

    /// Coach phone: switch timed-session activity on the display (coach remote owns the picker).
    @MainActor
    func sendActivityChanged(to activity: ActivityKind, onRetrying: (() -> Void)? = nil) async -> Bool {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return false }
        guard isPartnerTrainingSessionActive, displayTimedSessionAnnounced else { return false }
        let activityId = activity.sessionActivityActivityId
        if currentTimedSessionActivityId == activityId { return true }

        applyCoachTimedSessionMirror(activityId: activityId)
        let msg = TwoMinuteMessage.activityChanged(activityId: activityId, timestamp: Date())

        let maxAttempts = 3
        for attempt in 0..<maxAttempts {
            if hasPartnerActivityChangeTransport {
                transmitActivityChanged(msg, activityId: activityId)
                return true
            }
            if attempt < maxAttempts - 1 {
                onRetrying?()
                await attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(reason: "activity_changed")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        return false
    }

    private var hasPartnerActivityChangeTransport: Bool {
        coachRelayRemoteService.connectionState == .connected
            || ConnectionManager.shared.connectedPeerName != nil
    }

    private func transmitActivityChanged(_ msg: TwoMinuteMessage, activityId: String) {
        print("[COACH OUT] activityChanged activityId=\(activityId)")
        if coachRelayRemoteService.connectionState == .connected {
            coachRelayRemoteService.send(msg, completion: nil)
        }
        if ConnectionManager.shared.connectedPeerName != nil {
            ConnectionManager.shared.sendTwoMinuteMessage(msg)
        }
    }

    private func handleIncomingActivityChangedFromCoach(activityId: String) {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard let activity = ActivityKind.fromSessionActivityId(activityId) else { return }
        let timed = TimedSessionController.shared
        guard timed.mode == .partner, timed.isManagingSession, timed.isSessionActive else { return }
        print("[DISPLAY IN] activityChanged activityId=\(activityId)")
        NotificationCenter.default.post(name: .timedSessionSwitchActivity, object: activity)
    }

    /// Coach phone: end timed partner session — notify display to save + show summary, then return to hub.
    func coachEndTimedSession(router: AppRouter) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard CurrentSessionStore.shared.tryMarkPartnerTimedSessionEndHandled() else { return }
        broadcastPartnerTimedSessionEnded(source: .coach)
        softResetAfterTimedPartnerSessionEnd()
        router.returnToCoachRemoteHubAfterSessionEnd()
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

    /// Warms relay join code + Multipeer display hosting so a coach can connect **before** any activity session
    /// (e.g. iPad Coach Remote required prompt). Does **not** set ``isPartnerTrainingSessionActive`` or start engines.
    func warmUpCoachLinkSurfaceOnPlayerDisplayIfNeeded() async {
        #if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        #else
        return
        #endif
        let raw = UserDefaults.standard.string(forKey: AppRole.storageKey) ?? AppRole.player.rawValue
        guard AppRole.resolved(from: raw) != .coachRemote else { return }
        #if DEBUG
        PartnerPersistDebug.log("warmUpCoachLinkSurfaceOnPlayerDisplayIfNeeded — multipeer host + relay join code")
        #endif
        prepareMultipeerDisplayPartner(connectionManager: ConnectionManager.shared)
        await relayDisplaySession.startDisplaySessionIfNeeded()
    }

    /// Display: call `startDisplaySessionIfNeeded()` on the shared relay.
    /// Coach remotes (phones) must never mint a display join code — they join an existing session.
    func prepareRelayDisplayForActivity() async {
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .phone {
            #if DEBUG
            PartnerPersistDebug.log("prepareRelayDisplayForActivity — skipped on phone (coach remote joins; display hosts)")
            #endif
            return
        }
        #endif
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
        partnerRelaySuspendedForBackground = true
        if interruptionBeganAt == nil {
            let start = Date()
            interruptionBeganAt = start
            RelaySoftResumeDebug.logInterruptionStart(at: start)
        }
        relaySessionIdSnapshotAtSuspend = relayDisplaySession.relaySessionId ?? relaySessionIdSnapshotAtSuspend
        let jc = relayDisplaySession.joinCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sid = relayDisplaySession.relaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !jc.isEmpty, !sid.isEmpty {
            lastKnownValidRelaySessionId = sid
        }
        #if DEBUG
        print("[Multipeer] TrainingPartnerSession: suspend for iOS background — keep pairing; relay soft disconnect (display + coach)")
        #endif
        relayDisplaySession.suspendForAppBackground()
        if coachRelayRemoteService.connectionState != .disconnected {
            coachRelayRemoteService.disconnect()
        }
    }
}
