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

    /// Coach WebSocket credentials from the last successful HTTP join (same training run). Used for same-room reconnect without POST /join.
    private var retainedCoachWebSocketSessionConfig: WebSocketSessionConfig?

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
    private var networkReachabilityCancellable: AnyCancellable?
    private var bannerAutoHideTask: Task<Void, Never>?
    /// Bounded same-room display WebSocket reconnect while Partner is active and the socket is down (no new room / join code).
    private var displaySameRoomReconnectRetryTask: Task<Void, Never>?
    private var displaySameRoomReconnectAttemptCount: Int = 0
    /// Low-frequency same-room display reconnect after the fast burst (no new room / join code).
    private var displaySameRoomSlowReconnectRetryTask: Task<Void, Never>?
    private var displaySameRoomSlowReconnectAttemptCount: Int = 0
    /// Bounded same-room coach WebSocket reconnect using retained sessionId/token (no POST /join).
    private var coachSameRoomReconnectRetryTask: Task<Void, Never>?
    private var coachSameRoomReconnectAttemptCount: Int = 0
    /// Low-frequency coach same-room reconnect after the fast burst (keeps trying until display peer returns).
    private var coachSameRoomSlowReconnectRetryTask: Task<Void, Never>?
    private var coachSameRoomSlowReconnectAttemptCount: Int = 0
    /// Short grace window around transient system interruptions (e.g. screenshot UI) so brief socket flaps do not force relay recycle.
    private var transientLifecycleInterruptionUntil: Date?

    // MARK: - Mid-session disconnect (drill freeze + recovery)

    /// True only after transport was live **and** drill play had begun this partner run (used for mid-session disconnect eligibility).
    private var hadPartnerTransportLinkLiveThisSession: Bool = false
    /// True after drill play has begun (countdown finished, rep sync, or coach `nextRep`) so we do not show recovery during pairing/setup.
    private var hasStartedAtLeastOneRep: Bool = false
    /// Coach phone: next TAP index surviving view remount / reconnect (not cleared by mid-session transport flaps).
    private var coachPersistedNextRepIndex: Int = 0
    private var coachPersistedNextRepActivityId: String?
    /// Full-screen recovery UI while partner link drops mid-drill (legacy flag; transport loss no longer sets this).
    @Published private(set) var isMidSessionPartnerDisconnect: Bool = false
    /// Transient transport/peer loss mid-drill — non-destructive reconnecting scrim on coach + display (not session end).
    @Published private(set) var isTransientPartnerLinkLossReconnecting: Bool = false
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
        networkReachabilityCancellable = NetworkReachabilityObserver.shared.reachableSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.pokeDisplaySameRoomReconnectFromNetworkPathSatisfied()
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
        networkReachabilityCancellable?.cancel()
        displaySameRoomReconnectRetryTask?.cancel()
        displaySameRoomSlowReconnectRetryTask?.cancel()
        coachSameRoomReconnectRetryTask?.cancel()
        coachSameRoomSlowReconnectRetryTask?.cancel()
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
        let classified = HotspotBaselineLog.classifyRelayFrame(text)
        if classified == "control.peer_joined" || classified == "control.peer_left" || classified.hasPrefix("DISPLAY_") || classified.hasPrefix("COACH_") || classified == "control.error" || classified == "INVALID_TOKEN" || classified == "INVALID_JOIN_CODE" || classified == "SESSION_NOT_FOUND" || classified == "SESSION_EXPIRED" {
            HotspotBaselineLog.emit(
                "COACH relay_frame kind=\(classified) partnerActive=\(isPartnerTrainingSessionActive) activityId=\(currentTimedSessionActivityId ?? lastNonNilActivityId ?? "nil") coachSocket=\(coachRelayRemoteService.connectionState.rawValue) displayPeerPresent=\(coachRelayDisplayPeerPresent) midSessionDisconnect=\(isMidSessionPartnerDisconnect) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(trackedRelaySessionId))"
            )
        }
        if text.contains("peer_joined") {
            coachRelayDisplayPeerPresent = true
        }
        if text.lowercased().contains("peer_left") {
            coachRelayDisplayPeerPresent = false
        }
        if text.contains("control.ack"), text.contains("peerPresent") {
            let peerPresent = text.contains("\"peerPresent\":true") || text.contains("\"peerPresent\": true")
            if peerPresent != coachRelayDisplayPeerPresent {
                HotspotBaselineLog.emit(
                    "COACH displayPeerPresent \(coachRelayDisplayPeerPresent)->\(peerPresent) reason=control_ack_peerPresent sessionSuffix=\(HotspotBaselineLog.sessionSuffix(trackedRelaySessionId))"
                )
                coachRelayDisplayPeerPresent = peerPresent
            }
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
            if isMidSessionPartnerDisconnect || isTransientPartnerLinkLossReconnecting {
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
                        HotspotBaselineLog.emit(
                            "COACH soft_reconnect_rep_restart activityId=\(currentTimedSessionActivityId ?? lastNonNilActivityId ?? "nil") sessionSuffix=\(HotspotBaselineLog.sessionSuffix(trackedRelaySessionId))"
                        )
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
            // Coach mid-session soft-resume: PARTNER LINK LIVE is enough to leave "Restoring session…".
            // Do not wait for partnerSessionCheckpoint (display only emits that on its own foreground path).
            if !CoachRemoteSessionStartGate.isPadPlayerRole(),
               retainedCoachWebSocketSessionConfig != nil,
               case .restoringSession = relayLifecycleBanner,
               awaitingSoftResumeCheckpointValidation {
                awaitingSoftResumeCheckpointValidation = false
                HotspotBaselineLog.emit(
                    "COACH soft_resume_checkpoint_wait_cleared reason=partner_link_live sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
                )
                clearCheckpointDrift()
                relayLifecycleBanner = .sessionRestoredSoft
                scheduleAutoHideSessionRestoredSoftBanner()
                clearSoftResumeInterruptionState()
                HotspotBaselineLog.emit(
                    "COACH restore_complete reason=partner_link_live activityId=\(currentTimedSessionActivityId ?? lastNonNilActivityId ?? "nil") sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
                )
                cancelCoachSameRoomReconnectRetry(reason: "partner_link_live")
            }
            if isTransientPartnerLinkLossReconnecting {
                HotspotBaselineLog.emit(
                    "TRANSPORT_LOSS reconnecting cleared reason=link_live_again role=\(CoachRemoteSessionStartGate.isPadPlayerRole() ? "display" : "coach") activityId=\(currentTimedSessionActivityId ?? lastNonNilActivityId ?? "nil")"
                )
                isTransientPartnerLinkLossReconnecting = false
                cancelDisplaySameRoomReconnectRetry(reason: "connected")
                cancelCoachSameRoomReconnectRetry(reason: "partner_link_live")
            }
            if isMidSessionPartnerDisconnect {
                HotspotBaselineLog.emit(
                    "COACH midSessionDisconnect true->false reason=link_live_again activityId=\(currentTimedSessionActivityId ?? lastNonNilActivityId ?? "nil")"
                )
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
        scheduleTransientPartnerLinkLossReconnectingIfNeeded()
    }

    private func cancelMidSessionDisconnectDebounce() {
        midSessionDisconnectDebounceToken = nil
    }

    /// Temporary peer/socket loss while a partner drill is underway.
    /// Shows reconnecting UI only — does **not** treat transport loss as session end
    /// (no ``isMidSessionPartnerDisconnect`` / “Session ended” / join-screen path).
    private func scheduleTransientPartnerLinkLossReconnectingIfNeeded() {
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
                guard !self.isTransientPartnerLinkLossReconnecting else {
                    self.relayLifecycleBanner = .reconnecting
                    if CoachRemoteSessionStartGate.isPadPlayerRole() {
                        self.startDisplaySameRoomReconnectRetryLoopIfNeeded(trigger: "transient_link_loss_already_active")
                    } else {
                        self.startCoachSameRoomReconnectRetryLoopIfNeeded(trigger: "transient_link_loss_already_active")
                    }
                    return
                }
                let role = CoachRemoteSessionStartGate.isPadPlayerRole() ? "display" : "coach"
                let trackedSuffix = HotspotBaselineLog.sessionSuffix(self.trackedRelaySessionId)
                let displaySuffix = HotspotBaselineLog.sessionSuffix(self.relayDisplaySession.relaySessionId)
                HotspotBaselineLog.emit(
                    "TRANSPORT_LOSS reconnecting_not_session_ended fn=scheduleTransientPartnerLinkLossReconnectingIfNeeded role=\(role) activityId=\(self.currentTimedSessionActivityId ?? self.lastNonNilActivityId ?? "nil") partnerActive=\(self.isPartnerTrainingSessionActive) coachSocket=\(self.coachRelayRemoteService.connectionState.rawValue) displayPeerPresent=\(self.coachRelayDisplayPeerPresent) displaySocket=\(self.relayDisplaySession.socketConnectionState.rawValue) isCoachPaired=\(self.relayDisplaySession.isCoachPaired) linkLive=\(self.isPartnerTransportLinkLive) sessionSuffix=\(trackedSuffix) displaySessionSuffix=\(displaySuffix)"
                )
                self.isTransientPartnerLinkLossReconnecting = true
                self.relayLifecycleBanner = .reconnecting
                self.relayDisplaySession.cancelRelayDisconnectRecycleTask()
                if CoachRemoteSessionStartGate.isPadPlayerRole() {
                    self.startDisplaySameRoomReconnectRetryLoopIfNeeded(trigger: "transient_link_loss")
                } else {
                    self.startCoachSameRoomReconnectRetryLoopIfNeeded(trigger: "transient_link_loss")
                }
            }
        }
    }

    /// Display mid-session recovery: socket up alone is not enough — need `peer_joined` (coach present).
    @MainActor
    private var isDisplayRelayCoachLinkRestored: Bool {
        relayDisplaySession.socketConnectionState == .connected && relayDisplaySession.isCoachPaired
    }

    /// Display: unexpected WebSocket drop while Partner is active — start same-room reconnect retries (no new room).
    @MainActor
    func noteDisplayRelaySocketUnexpectedDisconnect() {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard relayDisplaySession.hasAdoptableRelaySession else { return }
        // Heal identity if beginPartnerTrainingSession wiped it after warm-up (legacy path).
        if trackedRelaySessionId == nil,
           let sid = relayDisplaySession.relaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sid.isEmpty {
            recordRelaySessionId(sid)
        }
        startDisplaySameRoomReconnectRetryLoopIfNeeded(trigger: "unexpected_socket_disconnect")
    }

    /// Display WebSocket became connected — only stop retries once the coach peer is back.
    @MainActor
    func noteDisplayRelaySocketConnectedForReconnectRetry() {
        if isDisplayRelayCoachLinkRestored || isPartnerTransportLinkLive {
            cancelDisplaySameRoomReconnectRetry(reason: "connected")
            return
        }
        // Connected without coach: keep slow force-fresh retries (do not treat socket-up as success).
        guard isPartnerTrainingSessionActive, relayDisplaySession.hasAdoptableRelaySession else { return }
        HotspotBaselineLog.emit(
            "DISPLAY socket_connected_without_coach keep_retrying sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId)) joinSuffix=\(HotspotBaselineLog.joinSuffix(relayDisplaySession.joinCode))"
        )
        startDisplaySameRoomSlowReconnectRetryLoopIfNeeded(trigger: "connected_without_coach")
    }

    /// Path becomes satisfied again — cancel sleepy backoff and immediately force a fresh same-room socket.
    @MainActor
    private func pokeDisplaySameRoomReconnectFromNetworkPathSatisfied() {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else {
            pokeCoachSameRoomReconnectFromNetworkPathSatisfied()
            return
        }
        guard isPartnerTrainingSessionActive else { return }
        guard relayDisplaySession.hasAdoptableRelaySession else { return }
        guard !isDisplayRelayCoachLinkRestored else { return }

        HotspotBaselineLog.emit(
            "DISPLAY path_satisfied_reconnect poke priorSocket=\(relayDisplaySession.socketConnectionState.rawValue) coachPaired=\(relayDisplaySession.isCoachPaired) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId ?? trackedRelaySessionId)) joinSuffix=\(HotspotBaselineLog.joinSuffix(relayDisplaySession.joinCode))"
        )
        // Drop in-flight 8s/12s sleeps so recovery isn't gated by an offline-era backoff.
        cancelDisplaySameRoomReconnectRetry(reason: "path_satisfied_restart")
        cancelDisplaySameRoomSlowReconnectRetry(reason: "path_satisfied_restart")
        startDisplaySameRoomReconnectRetryLoopIfNeeded(trigger: "path_satisfied")
        Task { @MainActor in
            // Burst a few immediate attempts — first radio-up often still fails once.
            for i in 0..<4 {
                if i > 0 {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                }
                guard self.isPartnerTrainingSessionActive else { return }
                guard !self.isDisplayRelayCoachLinkRestored else { return }
                await self.performDisplaySameRoomReconnectAttempt(
                    label: "path_satisfied_\(i)",
                    forceFreshSocket: true
                )
                if self.isDisplayRelayCoachLinkRestored { return }
            }
        }
    }

    @MainActor
    private func pokeCoachSameRoomReconnectFromNetworkPathSatisfied() {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard coachRelayRemoteService.connectionState != .connected else { return }
        guard retainedCoachWebSocketSessionConfig != nil else { return }

        HotspotBaselineLog.emit(
            "COACH path_satisfied_reconnect poke sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
        )
        cancelCoachSameRoomReconnectRetry(reason: "path_satisfied_restart")
        startCoachSameRoomReconnectRetryLoopIfNeeded(trigger: "path_satisfied")
        Task { @MainActor in
            for i in 0..<4 {
                if i > 0 {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                }
                guard self.isPartnerTrainingSessionActive else { return }
                guard self.coachRelayRemoteService.connectionState != .connected else { return }
                self.performCoachSameRoomReconnectAttempt(label: "path_satisfied_\(i)")
                if self.coachRelayRemoteService.connectionState == .connected { return }
            }
        }
    }

    /// Bounded backoff reconnect of the **existing** display relay transport (no POST /v1/sessions).
    @MainActor
    private func startDisplaySameRoomReconnectRetryLoopIfNeeded(trigger: String) {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard relayDisplaySession.hasAdoptableRelaySession else { return }
        guard displaySameRoomReconnectRetryTask == nil else { return }

        HotspotBaselineLog.emit(
            "DISPLAY reconnect_retry_scheduled trigger=\(trigger) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId))"
        )

        displaySameRoomReconnectRetryTask = Task { @MainActor [weak self] in
            // Modest exponential backoff; cancel only when coach peer is back (not socket-up alone).
            let delaysNs: [UInt64] = [
                500_000_000,
                1_000_000_000,
                2_000_000_000,
                4_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000
            ]
            for delay in delaysNs {
                try? await Task.sleep(nanoseconds: delay)
                guard let self else { return }
                guard !Task.isCancelled else { return }

                if !self.isPartnerTrainingSessionActive {
                    self.cancelDisplaySameRoomReconnectRetry(reason: "session_end")
                    return
                }
                if self.isDisplayRelayCoachLinkRestored || self.isPartnerTransportLinkLive {
                    self.cancelDisplaySameRoomReconnectRetry(reason: "connected")
                    return
                }
                if !self.relayDisplaySession.hasAdoptableRelaySession {
                    self.cancelDisplaySameRoomReconnectRetry(reason: "invalid_session")
                    return
                }
                // Still mid-session recovery context (or socket still down / coach missing while Partner active).
                guard self.isTransientPartnerLinkLossReconnecting
                    || self.relayDisplaySession.socketConnectionState == .disconnected
                    || !self.relayDisplaySession.isCoachPaired else {
                    self.cancelDisplaySameRoomReconnectRetry(reason: "connected")
                    return
                }

                await self.performDisplaySameRoomReconnectAttempt(label: nil, forceFreshSocket: true)

                if self.isDisplayRelayCoachLinkRestored || self.isPartnerTransportLinkLive {
                    self.cancelDisplaySameRoomReconnectRetry(reason: "connected")
                    return
                }
            }
            // Fast burst exhausted — keep Partner session on the same room with low-frequency retries.
            guard let self else { return }
            self.displaySameRoomReconnectRetryTask = nil
            self.displaySameRoomReconnectAttemptCount = 0
            if self.isPartnerTrainingSessionActive,
               !self.isDisplayRelayCoachLinkRestored,
               self.relayDisplaySession.hasAdoptableRelaySession {
                self.startDisplaySameRoomSlowReconnectRetryLoopIfNeeded(trigger: "fast_burst_exhausted")
            }
        }
    }

    @MainActor
    private func performDisplaySameRoomReconnectAttempt(label: String?, forceFreshSocket: Bool = true) async {
        guard isPartnerTrainingSessionActive else {
            cancelDisplaySameRoomReconnectRetry(reason: "session_end")
            return
        }
        guard relayDisplaySession.hasAdoptableRelaySession else {
            cancelDisplaySameRoomReconnectRetry(reason: "invalid_session")
            return
        }
        if isDisplayRelayCoachLinkRestored || isPartnerTransportLinkLive {
            cancelDisplaySameRoomReconnectRetry(reason: "connected")
            return
        }

        displaySameRoomReconnectAttemptCount += 1
        let n = displaySameRoomReconnectAttemptCount
        let labelPart = label.map { " label=\($0)" } ?? ""
        HotspotBaselineLog.emit(
            "DISPLAY reconnect_retry_attempt number=\(n)\(labelPart) forceFresh=\(forceFreshSocket) coachPaired=\(relayDisplaySession.isCoachPaired) socket=\(relayDisplaySession.socketConnectionState.rawValue) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId))"
        )

        // Force a new WebSocket task even if prior attempt is stuck in `.connecting` or connected-without-coach.
        await relayDisplaySession.reconnectSameRoomTransport(forceFreshSocket: forceFreshSocket)

        // Brief settle so connecting→connected / peer_joined can land before we log result.
        try? await Task.sleep(nanoseconds: 350_000_000)
        let state = relayDisplaySession.socketConnectionState
        HotspotBaselineLog.emit(
            "DISPLAY reconnect_retry_result state=\(state.rawValue) coachPaired=\(relayDisplaySession.isCoachPaired) number=\(n) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId))"
        )
        if isDisplayRelayCoachLinkRestored || isPartnerTransportLinkLive {
            cancelDisplaySameRoomReconnectRetry(reason: "connected")
        }
    }

    /// After the aggressive burst: retry the same retained room every ~3s until coach peer_joined returns.
    @MainActor
    private func startDisplaySameRoomSlowReconnectRetryLoopIfNeeded(trigger: String) {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard relayDisplaySession.hasAdoptableRelaySession else { return }
        guard displaySameRoomSlowReconnectRetryTask == nil else { return }
        guard !isDisplayRelayCoachLinkRestored else { return }

        HotspotBaselineLog.emit(
            "DISPLAY reconnect_slow_retry_scheduled trigger=\(trigger) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId)) joinSuffix=\(HotspotBaselineLog.joinSuffix(relayDisplaySession.joinCode))"
        )

        displaySameRoomSlowReconnectRetryTask = Task { @MainActor [weak self] in
            let delayNs: UInt64 = 3_000_000_000
            while true {
                try? await Task.sleep(nanoseconds: delayNs)
                guard let self else { return }
                guard !Task.isCancelled else { return }

                if !self.isPartnerTrainingSessionActive {
                    self.cancelDisplaySameRoomSlowReconnectRetry(reason: "session_end")
                    return
                }
                if self.isDisplayRelayCoachLinkRestored || self.isPartnerTransportLinkLive {
                    self.cancelDisplaySameRoomSlowReconnectRetry(reason: "connected")
                    return
                }
                if !self.relayDisplaySession.hasAdoptableRelaySession {
                    self.cancelDisplaySameRoomSlowReconnectRetry(reason: "invalid_session")
                    return
                }

                self.displaySameRoomSlowReconnectAttemptCount += 1
                let n = self.displaySameRoomSlowReconnectAttemptCount
                HotspotBaselineLog.emit(
                    "DISPLAY reconnect_slow_retry_attempt number=\(n) coachPaired=\(self.relayDisplaySession.isCoachPaired) socket=\(self.relayDisplaySession.socketConnectionState.rawValue) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(self.relayDisplaySession.relaySessionId)) joinSuffix=\(HotspotBaselineLog.joinSuffix(self.relayDisplaySession.joinCode))"
                )
                await self.relayDisplaySession.reconnectSameRoomTransport(forceFreshSocket: true)
                try? await Task.sleep(nanoseconds: 350_000_000)
                if self.isDisplayRelayCoachLinkRestored || self.isPartnerTransportLinkLive {
                    self.cancelDisplaySameRoomSlowReconnectRetry(reason: "connected")
                    return
                }
            }
        }
    }

    @MainActor
    private func cancelDisplaySameRoomSlowReconnectRetry(reason: String) {
        let hadTask = displaySameRoomSlowReconnectRetryTask != nil
        let hadAttempts = displaySameRoomSlowReconnectAttemptCount > 0
        displaySameRoomSlowReconnectRetryTask?.cancel()
        displaySameRoomSlowReconnectRetryTask = nil
        if hadTask || hadAttempts {
            HotspotBaselineLog.emit(
                "DISPLAY reconnect_slow_retry_cancel reason=\(reason) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId))"
            )
        }
        displaySameRoomSlowReconnectAttemptCount = 0
    }

    @MainActor
    private func cancelDisplaySameRoomReconnectRetry(reason: String) {
        let hadTask = displaySameRoomReconnectRetryTask != nil
        let hadAttempts = displaySameRoomReconnectAttemptCount > 0
        displaySameRoomReconnectRetryTask?.cancel()
        displaySameRoomReconnectRetryTask = nil
        if hadTask || hadAttempts {
            HotspotBaselineLog.emit(
                "DISPLAY reconnect_retry_cancel reason=\(reason) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId))"
            )
        }
        displaySameRoomReconnectAttemptCount = 0
        // Connected / session end / invalid also stop the slow loop.
        if reason == "connected" || reason == "session_end" || reason == "invalid_session" {
            cancelDisplaySameRoomSlowReconnectRetry(reason: reason)
        }
    }

    /// Bounded backoff coach reconnect using retained same-session WebSocket credentials (no POST /join).
    @MainActor
    private func startCoachSameRoomReconnectRetryLoopIfNeeded(trigger: String) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard retainedCoachWebSocketSessionConfig != nil else { return }
        guard coachSameRoomReconnectRetryTask == nil else { return }

        HotspotBaselineLog.emit(
            "COACH reconnect_retry_scheduled trigger=\(trigger) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
        )

        coachSameRoomReconnectRetryTask = Task { @MainActor [weak self] in
            let delaysNs: [UInt64] = [
                500_000_000,
                1_000_000_000,
                2_000_000_000,
                4_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000,
                8_000_000_000
            ]
            for delay in delaysNs {
                try? await Task.sleep(nanoseconds: delay)
                guard let self else { return }
                guard !Task.isCancelled else { return }

                if !self.isPartnerTrainingSessionActive {
                    self.cancelCoachSameRoomReconnectRetry(reason: "session_end")
                    return
                }
                // Success requires PARTNER LINK LIVE (socket connected + display peerPresent), not socket-open alone.
                if self.isPartnerTransportLinkLive {
                    self.cancelCoachSameRoomReconnectRetry(reason: "partner_link_live")
                    return
                }
                if self.retainedCoachWebSocketSessionConfig == nil {
                    self.cancelCoachSameRoomReconnectRetry(reason: "invalid_session")
                    return
                }

                self.performCoachSameRoomReconnectAttempt(label: nil)

                // Allow connecting → connected / peer_joined to settle.
                try? await Task.sleep(nanoseconds: 350_000_000)
                HotspotBaselineLog.emit(
                    "COACH reconnect_retry_result state=\(self.coachRelayRemoteService.connectionState.rawValue) peerPresent=\(self.coachRelayDisplayPeerPresent) linkLive=\(self.isPartnerTransportLinkLive) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(self.retainedCoachWebSocketSessionConfig?.sessionId ?? self.trackedRelaySessionId))"
                )
                if self.isPartnerTransportLinkLive {
                    self.cancelCoachSameRoomReconnectRetry(reason: "partner_link_live")
                    return
                }
            }
            // Fast burst exhausted — keep trying; a connected-without-peer socket used to no-op forever.
            guard let self else { return }
            self.coachSameRoomReconnectRetryTask = nil
            self.coachSameRoomReconnectAttemptCount = 0
            if self.isPartnerTrainingSessionActive,
               !self.isPartnerTransportLinkLive,
               self.retainedCoachWebSocketSessionConfig != nil {
                self.startCoachSameRoomSlowReconnectRetryLoopIfNeeded(trigger: "fast_burst_exhausted")
            }
        }
    }

    @MainActor
    private func performCoachSameRoomReconnectAttempt(label: String?) {
        guard isPartnerTrainingSessionActive else {
            cancelCoachSameRoomReconnectRetry(reason: "session_end")
            return
        }
        guard retainedCoachWebSocketSessionConfig != nil else {
            cancelCoachSameRoomReconnectRetry(reason: "invalid_session")
            return
        }
        if isPartnerTransportLinkLive {
            cancelCoachSameRoomReconnectRetry(reason: "partner_link_live")
            return
        }

        coachSameRoomReconnectAttemptCount += 1
        let n = coachSameRoomReconnectAttemptCount
        let labelPart = label.map { " label=\($0)" } ?? ""
        HotspotBaselineLog.emit(
            "COACH reconnect_retry_attempt number=\(n)\(labelPart) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
        )
        HotspotBaselineLog.emit(
            "COACH reconnect_same_session number=\(n) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
        )
        reconnectCoachRelayWebSocketFromRetainedConfigIfNeeded(reason: "coach_same_room_retry_\(n)")
    }

    /// After the aggressive burst: retry every ~3s until the display peer is back (same retained room).
    @MainActor
    private func startCoachSameRoomSlowReconnectRetryLoopIfNeeded(trigger: String) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }
        guard retainedCoachWebSocketSessionConfig != nil else { return }
        guard coachSameRoomSlowReconnectRetryTask == nil else { return }
        guard !isPartnerTransportLinkLive else { return }

        HotspotBaselineLog.emit(
            "COACH reconnect_slow_retry_scheduled trigger=\(trigger) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
        )

        coachSameRoomSlowReconnectRetryTask = Task { @MainActor [weak self] in
            let delayNs: UInt64 = 3_000_000_000
            while true {
                try? await Task.sleep(nanoseconds: delayNs)
                guard let self else { return }
                guard !Task.isCancelled else { return }

                if !self.isPartnerTrainingSessionActive {
                    self.cancelCoachSameRoomSlowReconnectRetry(reason: "session_end")
                    return
                }
                if self.isPartnerTransportLinkLive {
                    self.cancelCoachSameRoomSlowReconnectRetry(reason: "partner_link_live")
                    return
                }
                if self.retainedCoachWebSocketSessionConfig == nil {
                    self.cancelCoachSameRoomSlowReconnectRetry(reason: "invalid_session")
                    return
                }

                self.coachSameRoomSlowReconnectAttemptCount += 1
                let n = self.coachSameRoomSlowReconnectAttemptCount
                HotspotBaselineLog.emit(
                    "COACH reconnect_slow_retry_attempt number=\(n) peerPresent=\(self.coachRelayDisplayPeerPresent) socket=\(self.coachRelayRemoteService.connectionState.rawValue) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(self.retainedCoachWebSocketSessionConfig?.sessionId ?? self.trackedRelaySessionId))"
                )
                self.reconnectCoachRelayWebSocketFromRetainedConfigIfNeeded(reason: "coach_same_room_slow_retry_\(n)")
                try? await Task.sleep(nanoseconds: 350_000_000)
                if self.isPartnerTransportLinkLive {
                    self.cancelCoachSameRoomSlowReconnectRetry(reason: "partner_link_live")
                    return
                }
            }
        }
    }

    @MainActor
    private func cancelCoachSameRoomSlowReconnectRetry(reason: String) {
        let hadTask = coachSameRoomSlowReconnectRetryTask != nil
        let hadAttempts = coachSameRoomSlowReconnectAttemptCount > 0
        coachSameRoomSlowReconnectRetryTask?.cancel()
        coachSameRoomSlowReconnectRetryTask = nil
        if hadTask || hadAttempts {
            HotspotBaselineLog.emit(
                "COACH reconnect_slow_retry_cancel reason=\(reason) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
            )
        }
        coachSameRoomSlowReconnectAttemptCount = 0
    }

    @MainActor
    private func cancelCoachSameRoomReconnectRetry(reason: String) {
        let hadTask = coachSameRoomReconnectRetryTask != nil
        let hadAttempts = coachSameRoomReconnectAttemptCount > 0
        coachSameRoomReconnectRetryTask?.cancel()
        coachSameRoomReconnectRetryTask = nil
        if hadTask || hadAttempts {
            HotspotBaselineLog.emit(
                "COACH reconnect_retry_cancel reason=\(reason) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
            )
        }
        coachSameRoomReconnectAttemptCount = 0
        if reason == "partner_link_live" || reason == "session_end" || reason == "invalid_session"
            || reason == "path_satisfied_restart" {
            cancelCoachSameRoomSlowReconnectRetry(reason: reason)
        }
    }

    /// True after the partner drill has begun (used to suppress initial “waiting for coach” pairing UI during mid-session link loss).
    var isPartnerDrillUnderway: Bool { hasStartedAtLeastOneRep }

    /// Coach relay: display left the room (`control.peer_left`).
    /// During an active partner run, keep the coach WebSocket attached so the same room can recover when the display returns.
    /// Only disconnect when pairing is already inactive (standby / join flow).
    @MainActor
    func shouldPreserveCoachRelaySocketOnDisplayPeerLeft() -> Bool {
        isPartnerTrainingSessionActive
    }

    /// True when coach has same-session WebSocket credentials (or join code while mid-reconnect) to restore without POST `/join`.
    @MainActor
    var hasRetainedCoachRelayReconnectIdentity: Bool {
        if retainedCoachWebSocketSessionConfig != nil { return true }
        guard let code = lastCoachRelayJoinCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            return false
        }
        return isTransientPartnerLinkLossReconnecting
            || isMidSessionPartnerDisconnect
            || hasStartedAtLeastOneRep
            || currentTimedSessionActivityId != nil
            || lastNonNilActivityId != nil
    }

    /// Mid-session coach transport loss: keep activity remote UI mounted (do not swap to join-code screen).
    /// Requires an active partner run **and** reconnect identity / live drill — not partner-active alone
    /// (that wrongly skipped the hub join screen on cold launch / stale session flags).
    @MainActor
    var shouldKeepCoachActivityRemoteMountedAcrossTransientLinkLoss: Bool {
        guard isPartnerTrainingSessionActive else { return false }
        if hasRetainedCoachRelayReconnectIdentity { return true }
        if currentTimedSessionActivityId != nil || lastNonNilActivityId != nil { return true }
        return isTransientPartnerLinkLossReconnecting || isMidSessionPartnerDisconnect
    }

    /// Coach hub: live display peer on the coach relay WebSocket (relay product path — not Multipeer).
    @MainActor
    var isCoachRelayDisplayLinkLive: Bool {
        coachRelayRemoteService.connectionState == .connected && coachRelayDisplayPeerPresent
    }

    private func clearMidSessionPartnerDisconnectState() {
        cancelMidSessionDisconnectDebounce()
        cancelDisplaySameRoomReconnectRetry(reason: "session_end")
        cancelDisplaySameRoomSlowReconnectRetry(reason: "session_end")
        cancelCoachSameRoomReconnectRetry(reason: "session_end")
        hadPartnerTransportLinkLiveThisSession = false
        hasStartedAtLeastOneRep = false
        isMidSessionPartnerDisconnect = false
        isTransientPartnerLinkLossReconnecting = false
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
        HotspotBaselineLog.emit(
            "COACH leave_live_activity fn=handleCoachEnterCodeAfterDisplayUnavailable will_call_remote.disconnect clear_pairing=true navigate=popToRoot activityId=\(currentTimedSessionActivityId ?? lastNonNilActivityId ?? "nil") joinSuffix=\(HotspotBaselineLog.joinSuffix(lastCoachRelayJoinCode)) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(trackedRelaySessionId))"
        )
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
        HotspotBaselineLog.emit("COACH navigation popToRoot endingPartnerSession=false after display_unavailable Enter Code")
        router.popToRoot(endingPartnerSession: false)
    }

    /// Player iPad: replace the display relay with a fresh `/v1/sessions` + join code while keeping the partner training run active.
    /// Mid-session automatic recovery must **not** mint a new room while the existing relay identity is still retained.
    @MainActor
    func recyclePlayerDisplayRelaySessionKeepingPartnerRun(reason: String) async {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }

        if shouldPreserveDisplayRelaySameRoomForActivePartnerSession(reason: reason) {
            await preserveActivePartnerDisplayRelaySameRoom(trigger: reason)
            return
        }

        HotspotBaselineLog.emit(
            "DISPLAY recycle_will_force_new_room reason=\(reason) priorSessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId)) priorJoinSuffix=\(HotspotBaselineLog.joinSuffix(relayDisplaySession.joinCode))"
        )
        RelaySoftResumeDebug.logFallbackToRejoin(reason: "\(reason)_ipad_auto_recycle")
        relayDisplaySession.cancelRelayDisconnectRecycleTask()
        trackedRelaySessionId = nil
        lastKnownValidRelaySessionId = nil
        clearSoftResumeInterruptionState()
        relayLifecycleBanner = .hidden
        await forceRegenerateIPadDisplayRelaySessionAfterForeground(reason: "\(reason)_ipad_auto_recycle")
    }

    /// Authoritative mid-session protection: Partner training active + retained display relay identity.
    /// Does **not** depend on Supabase ``CurrentSessionStore.sessionId``.
    /// Definitive invalid/expired reasons may still force a new room.
    @MainActor
    func shouldBlockAutomaticNewDisplayRelayRoom() -> Bool {
        shouldPreserveDisplayRelaySameRoomForActivePartnerSession(reason: "mint_guard")
    }

    @MainActor
    private func isDefinitiveDisplayRelayInvalidationReason(_ reason: String) -> Bool {
        let r = reason.lowercased()
        return r.contains("expired")
            || r.contains("session_not_found")
            || r.contains("invalid_join")
            || r.contains("invalid_token")
            || r.contains("session_expired")
    }

    @MainActor
    private func shouldPreserveDisplayRelaySameRoomForActivePartnerSession(reason: String) -> Bool {
        guard isPartnerTrainingSessionActive else { return false }
        if isDefinitiveDisplayRelayInvalidationReason(reason) { return false }

        let joinOK: Bool = {
            guard let raw = relayDisplaySession.joinCode?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !raw.isEmpty
        }()
        let sessionKnown =
            (relayDisplaySession.relaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            || (trackedRelaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            || (lastKnownValidRelaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

        // Prefer live adoptable transport+code; also preserve when join/session identity remains after a transient drop.
        if relayDisplaySession.hasAdoptableRelaySession { return true }
        if joinOK && sessionKnown { return true }
        if joinOK { return true }
        return false
    }

    @MainActor
    private func preserveActivePartnerDisplayRelaySameRoom(trigger: String) async {
        HotspotBaselineLog.emit(
            "DISPLAY recycle_blocked reason=active_partner_session_same_room_preserved trigger=\(trigger) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(relayDisplaySession.relaySessionId)) joinSuffix=\(HotspotBaselineLog.joinSuffix(relayDisplaySession.joinCode))"
        )
        RelaySoftResumeDebug.logFallbackToRejoin(reason: "\(trigger)_same_room_preserved")
        relayDisplaySession.cancelRelayDisconnectRecycleTask()
        switch relayLifecycleBanner {
        case .reconnecting, .restoringSession, .sessionRestoredSoft, .connectionRestored, .reconnectedRestartingRep:
            break
        default:
            if relayDisplaySession.socketConnectionState != .connected {
                relayLifecycleBanner = .reconnecting
            }
        }
        await relayDisplaySession.reconnectSameRoomTransport(forceFreshSocket: true)
        startDisplaySameRoomReconnectRetryLoopIfNeeded(trigger: "recycle_blocked_\(trigger)")
        if displaySameRoomReconnectRetryTask == nil,
           relayDisplaySession.socketConnectionState != .connected,
           relayDisplaySession.hasAdoptableRelaySession {
            startDisplaySameRoomSlowReconnectRetryLoopIfNeeded(trigger: "recycle_blocked_\(trigger)")
        }
    }

    /// Player iPad: tear down relay and `POST /v1/sessions` so join code + `relaySessionId` stay aligned with the server.
    @MainActor
    private func forceRegenerateIPadDisplayRelaySessionAfterForeground(reason: String) async {
        if shouldPreserveDisplayRelaySameRoomForActivePartnerSession(reason: reason) {
            await preserveActivePartnerDisplayRelaySameRoom(trigger: reason)
            return
        }
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
        if shouldPreserveDisplayRelaySameRoomForActivePartnerSession(reason: "foreground_mint_check") {
            await preserveActivePartnerDisplayRelaySameRoom(trigger: "foreground_mint_check")
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
            LifecycleReconnectDebug.logReconnectAttempt(context: "coach.reconnectWebSocketFromRetainedConfig")
            reconnectCoachRelayWebSocketFromRetainedConfigIfNeeded(reason: "foreground_didBecomeActive")
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
            // If PARTNER LINK LIVE already (connected + peerPresent), exit restoring without waiting for checkpoint.
            refreshMidSessionPartnerDisconnectState()
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

    /// Persist coach WebSocket credentials after a successful HTTP join so same-room reconnect can rebuild without POST /join.
    func recordCoachRelayWebSocketSessionConfig(_ config: WebSocketSessionConfig) {
        retainedCoachWebSocketSessionConfig = config
        recordRelaySessionId(config.sessionId)
        HotspotBaselineLog.emit(
            "COACH retained_ws_config sessionSuffix=\(HotspotBaselineLog.sessionSuffix(config.sessionId))"
        )
    }

    /// Clears the stored coach join code. Only the coordinator should do this as part of an explicit partner-session end.
    private func clearRecordedCoachRelayJoinCode() {
        lastCoachRelayJoinCode = nil
        clearRetainedCoachWebSocketSessionConfig()
    }

    private func clearRetainedCoachWebSocketSessionConfig() {
        retainedCoachWebSocketSessionConfig = nil
    }

    /// Same-room coach reconnect without POST /join. Rebuilds `WebSocketRemoteTransport` when the installed transport is Pending/unusable.
    /// Also force-refreshes when the socket is `.connected` but the display peer is missing (common hotspot hang:
    /// cellular socket stays up, retries no-op'd, overlay stuck for minutes).
    @MainActor
    func reconnectCoachRelayWebSocketFromRetainedConfigIfNeeded(reason: String) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }

        let connectedWithoutDisplayPeer = coachRelayRemoteService.connectionState == .connected
            && !coachRelayDisplayPeerPresent
        if connectedWithoutDisplayPeer {
            HotspotBaselineLog.emit(
                "COACH reconnect force_fresh reason=\(reason) connected_without_peer sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retainedCoachWebSocketSessionConfig?.sessionId ?? trackedRelaySessionId))"
            )
            coachRelayRemoteService.disconnect()
            coachRelayDisplayPeerPresent = false
        } else if coachRelayRemoteService.connectionState == .connected {
            return
        }

        let retained = retainedCoachWebSocketSessionConfig
        let hasRetained = retained != nil
        let transportKind = coachRelayRemoteService.installedTransportKindForDiagnostics
        let usableWS = coachRelayRemoteService.hasUsableWebSocketRemoteTransport

        HotspotBaselineLog.emit(
            "COACH reconnect path reason=\(reason) retainedConfig=\(hasRetained) installedTransport=\(transportKind) rebuildingTransport=\(!usableWS && hasRetained) sessionSuffix=\(HotspotBaselineLog.sessionSuffix(retained?.sessionId ?? trackedRelaySessionId))"
        )

        guard let config = retained else {
            HotspotBaselineLog.emit("COACH reconnect aborted reason=\(reason) missing_retained_ws_config")
            return
        }

        if usableWS {
            HotspotBaselineLog.emit(
                "COACH reconnect connect_started reuse_existing_ws_transport sessionSuffix=\(HotspotBaselineLog.sessionSuffix(config.sessionId))"
            )
            coachRelayRemoteService.connect()
            return
        }

        HotspotBaselineLog.emit(
            "COACH reconnect connect_started rebuilding_ws_transport from_retained_config sessionSuffix=\(HotspotBaselineLog.sessionSuffix(config.sessionId))"
        )
        installCoachRelayWebSocketTransportFromRetainedConfig(config, reason: reason)
    }

    /// Installs a fresh coach WebSocket from retained same-session credentials (no HTTP /join).
    @MainActor
    private func installCoachRelayWebSocketTransportFromRetainedConfig(_ config: WebSocketSessionConfig, reason: String) {
        let transport = WebSocketRemoteTransport(config: config)
        let remote = coachRelayRemoteService
        transport.onRawTextReceived = { text in
            TrainingPartnerConnectionCoordinator.shared.ingestCoachRelayRawControlText(text)
            if text.lowercased().contains("peer_left") {
                Task { @MainActor in
                    let preserve = TrainingPartnerConnectionCoordinator.shared.shouldPreserveCoachRelaySocketOnDisplayPeerLeft()
                    HotspotBaselineLog.emit(
                        "COACH peer_left HANDLER site=retainedConfigReconnect preserveSocket=\(preserve) reason=\(reason)"
                    )
                    if !preserve {
                        remote.disconnect()
                    }
                }
            }
        }
        remote.replaceTransport(transport)
        remote.connect()
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
        clearPersistedCoachNextRepProgress(reason: "begin_partner_training_session")
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
        // Warm-up already created the display room + recorded its id; wiping here broke mid-session
        // soft-reconnect (`trackedRelaySessionId` was nil in TRANSPORT_LOSS logs).
        if adoptExistingRelay,
           let sid = relayDisplaySession.relaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sid.isEmpty {
            trackedRelaySessionId = sid
            lastKnownValidRelaySessionId = sid
            HotspotBaselineLog.emit(
                "DISPLAY adopt_tracked_session sessionSuffix=\(HotspotBaselineLog.sessionSuffix(sid)) joinSuffix=\(HotspotBaselineLog.joinSuffix(relayDisplaySession.joinCode))"
            )
        } else {
            trackedRelaySessionId = nil
            lastKnownValidRelaySessionId = nil
        }
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
        clearPersistedCoachNextRepProgress(reason: "end_partner_training_session")
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

        // FIRST READY / NEW BLOCK: notify coach remotes (may reset currentRepIndex to 0).
        // READY REBROADCAST after transient reconnect into the SAME live drill: do not notify —
        // that incorrectly triggered applyPartnerTrainAgainCoachRemoteReset → nextRep 0.
        //
        // Do NOT require TimedSessionController.isManagingSession — that is true on the display
        // iPad, not the coach iPhone, so it always failed the preserve check on coach.
        let sameLiveDrillReadyRebroadcast =
            repEngineWasReady == false
            && isPartnerTrainingSessionActive
            && hasStartedAtLeastOneRep

        if !repEngineWasReady {
            if sameLiveDrillReadyRebroadcast {
                HotspotBaselineLog.emit(
                    "COACH displayRepEngineReady rebroadcast preserved_rep_progress skip_trainAgainReset activityId=\(activityId) drillUnderway=\(hasStartedAtLeastOneRep)"
                )
            } else {
                HotspotBaselineLog.emit(
                    "COACH displayRepEngineReady first_ready_or_new_block post_trainAgainReset activityId=\(activityId) drillUnderway=\(hasStartedAtLeastOneRep)"
                )
                NotificationCenter.default.post(
                    name: .partnerDisplayRepEngineBecameReady,
                    object: activityId
                )
            }
        }
    }

    /// Coach remotes: true only for genuine first-ready / Train Again (drill not underway).
    /// Same-live-session reconnect rebroadcasts must not reset ``currentRepIndex``.
    @MainActor
    func shouldApplyCoachTrainAgainRepReset() -> Bool {
        guard isPartnerTrainingSessionActive else { return false }
        if hasStartedAtLeastOneRep {
            return false
        }
        // Survives `hasStartedAtLeastOneRep` being cleared incorrectly during transport flaps.
        if let aid = currentTimedSessionActivityId ?? lastNonNilActivityId,
           coachPersistedNextRepActivityId == aid,
           coachPersistedNextRepIndex > 0 {
            return false
        }
        return true
    }

    /// Record the coach TAP / in-flight rep index so reconnect or SwiftUI remount can restore it.
    @MainActor
    func notePersistedCoachNextRepIndex(_ index: Int, activityId: String) {
        guard isPartnerTrainingSessionActive else { return }
        guard !activityId.isEmpty else { return }
        let clamped = max(0, index)
        coachPersistedNextRepActivityId = activityId
        coachPersistedNextRepIndex = clamped
        HotspotBaselineLog.emit(
            "COACH persisted_rep_note index=\(clamped) activityId=\(activityId)"
        )
    }

    /// If local `@State` lagged (remount / Train Again false positive), return a higher persisted index.
    @MainActor
    func suggestedCoachRepIndexRestore(current: Int, activityId: String) -> Int? {
        guard coachPersistedNextRepActivityId == activityId else { return nil }
        guard coachPersistedNextRepIndex > current else { return nil }
        return coachPersistedNextRepIndex
    }

    @MainActor
    func clearPersistedCoachNextRepProgress(reason: String) {
        guard coachPersistedNextRepIndex != 0 || coachPersistedNextRepActivityId != nil else { return }
        HotspotBaselineLog.emit(
            "COACH persisted_rep_clear reason=\(reason) wasIndex=\(coachPersistedNextRepIndex) wasActivity=\(coachPersistedNextRepActivityId ?? "nil")"
        )
        coachPersistedNextRepIndex = 0
        coachPersistedNextRepActivityId = nil
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
        // Next displayRepEngineReady is a first-ready / new-block event (Train Again), not a reconnect rebroadcast.
        hasStartedAtLeastOneRep = false
        hadPartnerTransportLinkLiveThisSession = false
        linkDownSinceDrillUnderway = false
        isTransientPartnerLinkLossReconnecting = false
        clearPersistedCoachNextRepProgress(reason: "soft_reset_timed_session_end")
        cancelMidSessionDisconnectDebounce()
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

    /// Coach phone: restore relay socket using retained same-session WebSocket credentials (no POST /join).
    func attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(reason: String) async {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard isPartnerTrainingSessionActive else { return }

        let linkLive = isPartnerTransportLinkLive
        guard !linkLive else {
            #if DEBUG
            print("[CoachRelay] auto-reconnect skipped reason=\(reason) — transport already live")
            #endif
            return
        }

        if coachRelayRemoteService.connectionState == .connected {
            #if DEBUG
            print("[CoachRelay] stale socket (connected, no peer) — disconnecting before reconnect reason=\(reason)")
            #endif
            coachRelayRemoteService.disconnect()
            coachRelayDisplayPeerPresent = false
        }

        // Same-session reconnect only: rebuild/reuse WebSocket from retained config — never POST /join (COACH_SLOT_TAKEN).
        guard retainedCoachWebSocketSessionConfig != nil else {
            #if DEBUG
            print("[CoachRelay] auto-reconnect skipped reason=\(reason) — no retained ws config")
            #endif
            HotspotBaselineLog.emit("COACH reconnect aborted reason=\(reason) missing_retained_ws_config")
            return
        }
        reconnectCoachRelayWebSocketFromRetainedConfigIfNeeded(reason: reason)
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
