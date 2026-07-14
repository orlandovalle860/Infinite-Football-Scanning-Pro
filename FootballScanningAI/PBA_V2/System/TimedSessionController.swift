//
//  TimedSessionController.swift
//  FootballScanningAI
//
//  Shared time-based session container for solo + partner: one timer, one session id, one save.
//

import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class TimedSessionController: ObservableObject {
    static let shared = TimedSessionController()

    let sessionTimer = SoloSessionTimerController()

    @Published private(set) var currentActivity: ActivityKind?
    @Published private(set) var isManagingSession = false
    @Published private(set) var isSessionActive = false
    @Published private(set) var trainingMode: TrainingMode = .solo
    @Published private(set) var repTarget: Int?
    @Published private(set) var totalRepCount = 0
    @Published private(set) var activityRepCounts: [String: Int] = [:]
    @Published private(set) var summaryActivityRepCounts: [String: Int] = [:]
    @Published var showCompletionOverlay = false
    @Published var showSummary = false
    @Published private(set) var completionElapsed: TimeInterval = 0
    @Published private(set) var completionRepCount = 0
    @Published private(set) var lastCompletionType: SessionCompletionType?
    @Published private(set) var summaryDurationText = ""
    @Published private(set) var isSessionEnding = false
    @Published private(set) var sessionLocked = false
    /// Bumped on partner Train Again so activity display views recycle (fresh engine + calibration state).
    @Published private(set) var activitySurfaceGeneration = 0
    /// True while ``preparePartnerTrainAgain`` is resetting — blocks per-activity Supabase session creation on appear.
    @Published private(set) var isPartnerTrainAgainBootstrapping = false
    /// Timed partner: first 3–2–1–Go + instruction finished for this run (survives activity switches and Train Again).
    @Published private(set) var partnerSessionStartChromeCompleted = false

    private var primaryActivity: ActivityKind?
    private var blockNumber = 1
    private var playerId: UUID?
    private var hasStartedTimer = false
    private var sessionAlreadySaved = false
    private var timerSink: AnyCancellable?
    private var recordedRepTokens = Set<String>()
    private var currentCycleId: Int = 0
#if canImport(UIKit)
    private var backgroundPersistTaskID: UIBackgroundTaskIdentifier = .invalid
#endif

    private init() {
        timerSink = sessionTimer.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var mode: TrainingMode { trainingMode }

    var sessionRepCount: Int { totalRepCount }

    var sessionId: UUID? {
        CurrentSessionStore.shared.sessionId
    }

    var durationChoice: SoloSessionDurationChoice? {
        SoloTimeBasedSession.config
    }

    /// True after explicit duration selection (`beginSessionContainer`); drives bootstrap → container transition.
    var isTimedSessionConfigured: Bool {
        SoloTimeBasedSession.isActive
    }

    var sessionStartedAt: Date? {
        SoloTimeBasedSession.sessionStartedAt
    }

    /// Countdown remaining for timed sessions; `nil` when free-play elapsed mode.
    var remainingTime: TimeInterval? {
        sessionTimer.remainingTime
    }

    var isFreeMode: Bool {
        durationChoice == .free
    }

    /// User tapped End / long-press stop. Free play is always a normal completion; timed sessions are early only if countdown had time left.
    var userInitiatedEndCompletionType: SessionCompletionType {
        if isFreeMode { return .completed }
        if let remaining = remainingTime, remaining > 0.5 { return .earlyExit }
        return .completed
    }

    /// Human-readable duration for logs and analytics (`free`, `3m`).
    var durationLabel: String {
        durationChoice?.logLabel ?? "unknown"
    }

    var timerDisplayText: String {
        if isFreeMode {
            return SoloSessionTimeFormat.mmss(sessionTimer.elapsedSeconds())
        }
        if let remaining = remainingTime {
            return SoloSessionTimeFormat.mmss(remaining)
        }
        return sessionTimer.displayText
    }

    var isHostDevice: Bool {
        ConnectionManager.shared.isHost
    }

    /// iPad display (relay partner) may write Supabase session rows; coach iPhone does not.
    var mayWriteSupabase: Bool {
        SupabaseSessionWriteGate.mayWriteSessionData
    }

    /// True while the timed session accepts rep, timer, and activity mutations.
    var canAcceptSessionMutations: Bool {
        !sessionLocked && isSessionActive
    }

    private var canMutateSession: Bool {
        guard canAcceptSessionMutations else { return false }
        return isManagingSession && !sessionAlreadySaved
    }

    /// True when display views should skip creating their own Supabase session row on appear.
    var shouldSkipActivitySessionCreation: Bool {
        isManagingSession || isPartnerTrainAgainBootstrapping
    }

    /// Central idempotent rep counter for timed solo + partner sessions.
    func recordRepIfNeeded(activityId: String, repIndex: Int) {
        guard canMutateSession else { return }
        guard let token = repDedupeToken(for: repIndex) else { return }
        guard recordedRepTokens.insert(token).inserted else { return }
        totalRepCount += 1
        activityRepCounts[activityId, default: 0] += 1
        CurrentSessionStore.shared.incrementCurrentSegmentRepCount()
    }

    /// Stable dedupe key for the current segment + engine cycle + rep index.
    func repDedupeToken(for repIndex: Int) -> String? {
        guard let segmentId = CurrentSessionStore.shared.currentSessionActivitySegmentId else { return nil }
        return "\(segmentId.uuidString)-\(currentCycleId)-\(repIndex)"
    }

    /// Timed engine loop boundary only (10/12 rep chunk restart), not reconnect/switch.
    func advanceCycleIfNeeded() {
        guard canMutateSession else { return }
        currentCycleId += 1
    }

    func beginIfNeeded(
        initialActivity: ActivityKind,
        mode: TrainingMode,
        playerId: UUID?
    ) async {
        guard durationChoice != nil, SoloTimeBasedSession.isActive else {
            print("[TimedSession] beginIfNeeded skipped — duration inactive (choice=\(durationChoice?.rawValue ?? "nil") active=\(SoloTimeBasedSession.isActive))")
            return
        }
        guard !sessionLocked else {
            print("[TimedSession] beginIfNeeded skipped — session locked")
            return
        }

        trainingMode = mode
        repTarget = SoloTimeBasedSession.config?.repTarget
        print("[TimedSession] beginIfNeeded activity=\(initialActivity.sessionActivityActivityId) mode=\(mode) managing=\(isManagingSession) mayWriteSupabase=\(mayWriteSupabase)")

        guard !isManagingSession else {
            await ensureSupabaseActivitySegmentIfNeeded(for: currentActivity ?? initialActivity)
            notifyPartnerCoachDisplaySessionIsActive(activity: currentActivity ?? initialActivity)
            return
        }

        if CurrentSessionStore.shared.sessionId != nil {
            CurrentSessionStore.shared.clear()
        }
        CurrentSessionStore.shared.resetPartnerTimedSessionEndHandled()

        isManagingSession = true
        isSessionActive = true
        sessionAlreadySaved = false
        sessionLocked = false
        totalRepCount = 0
        activityRepCounts = [:]
        recordedRepTokens.removeAll()
        currentCycleId = 0
        primaryActivity = initialActivity
        currentActivity = initialActivity
        self.playerId = playerId
        blockNumber = 1
        hasStartedTimer = false
        if !isPartnerTrainAgainBootstrapping {
            partnerSessionStartChromeCompleted = false
        }

        // Notify coach immediately — must not wait on Supabase or segment inserts.
        notifyPartnerCoachDisplaySessionIsActive(activity: initialActivity)

        guard mayWriteSupabase else {
            print("[TimedSession] beginIfNeeded supabase skipped — mayWriteSupabase=false")
            return
        }

        guard CurrentSessionStore.shared.sessionId == nil else {
            print("[TimedSession] beginIfNeeded supabase skipped — sessionId already exists")
            return
        }

        guard let sessionId = await SupabaseSessionService.shared.createSessionForDrill(
            activity: initialActivity,
            blockSize: TimedSessionEnginePolicy.supabaseSessionBlockSize,
            playerId: playerId,
            mode: SessionAnalyticsMode.from(trainingMode: mode),
            startedAt: Date()
        ) else {
            print("[TimedSession] beginIfNeeded supabase create failed — coach already notified")
            return
        }

        print("[TimedSession] supabase session created id=\(sessionId.uuidString.lowercased())")

        CurrentSessionStore.shared.setSessionIdOnly(
            sessionId,
            mode: SessionAnalyticsMode.from(trainingMode: mode),
            startAnalyticsClock: mode != .solo,
            supabaseStartedAt: Date()
        )
        await registerActivitySegment(for: initialActivity)
    }

    /// Display iPad: tell coach remote the timed session container is live (rep gating).
    private func notifyPartnerCoachDisplaySessionIsActive(activity: ActivityKind) {
        guard trainingMode == .partner, isManagingSession, isSessionActive else { return }
        TrainingPartnerConnectionCoordinator.shared.broadcastTimedSessionActiveFromDisplay(activity: activity)
    }

    /// Explicit duration choice from the picker — does not start Supabase session until ``beginIfNeeded``.
    func beginSessionContainer(
        mode: TrainingMode,
        durationChoice choice: SoloSessionDurationChoice,
        style: SoloTrainingStyle
    ) {
        guard isSessionActive == false else {
            print("[TimedSession] beginSessionContainer skipped — session already active")
            return
        }
        guard !isManagingSession else {
            print("[TimedSession] beginSessionContainer skipped — already managing session")
            return
        }
        if CurrentSessionStore.shared.sessionId != nil {
            CurrentSessionStore.shared.clear()
        }
        activityRepCounts = [:]
        recordedRepTokens.removeAll()
        currentCycleId = 0
        SoloTimeBasedSession.begin(duration: choice, style: style)
        trainingMode = mode
        repTarget = choice.repTarget
        PBASessionFlowPolicy.persistTrainingMode(mode)
        print("[TimedSession] beginSessionContainer mode=\(mode) duration=\(choice.rawValue)")
        objectWillChange.send()
    }

    /// iPad partner display: coach sent ``sessionStarted`` — begin with last-selected duration (free or 3-minute block) without an extra Start tap.
    func beginPartnerSessionFromCoachIfNeeded() {
        guard !isManagingSession, !isSessionActive else { return }
        guard !SoloTimeBasedSession.isActive else { return }
        let duration = SoloSessionDurationChoice.loadLastSelected()
        beginSessionContainer(
            mode: .partner,
            durationChoice: duration,
            style: SoloTrainingStyle.loadLastSelected()
        )
        print("[TimedSession] partner auto-start from coach duration=\(duration.rawValue)")
    }

    /// Partner coach `sessionStarted`: clear stale duration config so bootstrap shows the picker (no auto-start).
    func prepareForPartnerDurationSelection() {
        guard !isManagingSession else { return }
        guard SoloTimeBasedSession.isActive else { return }
        SoloTimeBasedSession.clear()
        objectWillChange.send()
    }

    func prepareActivitySegment(activity: ActivityKind) {
        guard canAcceptSessionMutations else { return }
        CurrentSessionStore.shared.resetDecisionTimingCalibrationForNewDrillBlock(
            activityId: activity.sessionActivityActivityId
        )
    }

    func onCalibrationReadyForCurrentActivity() {
        guard canMutateSession else { return }
        guard SoloTimeBasedSession.isActive, let config = SoloTimeBasedSession.config else { return }
        if trainingMode == .solo {
            guard SoloSessionUserStartGate.hasConfirmedUserStart else { return }
        }
        startOrResumeSessionTimer(choice: config)
    }

    func onUserConfirmedSessionStart() {
        guard canMutateSession else { return }
        onCalibrationReadyForCurrentActivity()
    }

    private func startOrResumeSessionTimer(choice: SoloSessionDurationChoice) {
        guard canMutateSession else { return }
        if SoloTimeBasedSession.sessionStartedAt == nil {
            SoloTimeBasedSession.beginSessionClock()
        }
        let startedAt = SoloTimeBasedSession.sessionStartedAt ?? Date()
        #if DEBUG
        print("[TIMER DEBUG] start=\(startedAt)")
        #endif
        // Always resume from canonical sessionStartedAt; never recreate on activity switch.
        sessionTimer.resume(choice: choice, sessionStartedAt: startedAt)
        hasStartedTimer = true
    }

    func switchActivity(to activity: ActivityKind) async {
        guard canMutateSession else { return }
        guard isManagingSession, activity != currentActivity else { return }
        SessionStartCueRepGate.prepareDrillSurface()
        if mayWriteSupabase {
            await closeCurrentActivitySegmentInSupabase()
        }
        currentActivity = activity
        if trainingMode == .partner {
            activitySurfaceGeneration += 1
        }
        if let config = SoloTimeBasedSession.config {
            // Activity switches must never restart/reset timer; keep shared timer running.
            startOrResumeSessionTimer(choice: config)
        }
        if trainingMode == .partner {
            TrainingPartnerConnectionCoordinator.shared.broadcastTimedSessionActiveFromDisplay(activity: activity)
        }
        guard mayWriteSupabase else { return }
        blockNumber += 1
        await registerActivitySegment(for: activity)
    }

    /// Ensures the open Supabase segment exists for the current activity (resume / view recycle). Never reverts activity.
    func ensureSupabaseActivitySegmentIfNeeded(for activity: ActivityKind) async {
        guard isManagingSession, isSessionActive, !sessionAlreadySaved else { return }
        guard mayWriteSupabase, CurrentSessionStore.shared.sessionId != nil else { return }
        let store = CurrentSessionStore.shared
        let expectedActivityId = activity.sessionActivityActivityId
        if let openActivityId = store.currentSegmentActivityId,
           store.currentSessionActivitySegmentId != nil,
           openActivityId != expectedActivityId {
            await closeCurrentActivitySegmentInSupabase()
        }
        guard store.currentSessionActivitySegmentId == nil else { return }
        await registerActivitySegment(for: activity)
    }

    func requestEnd(completionType: SessionCompletionType, freeze: @escaping () -> Void) {
        guard isSessionActive, SoloTimeBasedSession.isActive, !showCompletionOverlay, !showSummary, !isSessionEnding, !sessionLocked else { return }
        SoloSessionEndTransition.beginUserEnd(
            setEnding: { self.isSessionEnding = true },
            freeze: freeze,
            presentOverlay: {
                self.finishSession(completionType: completionType)
            },
            clearEnding: { self.isSessionEnding = false }
        )
    }

    func finishSession(
        completionType: SessionCompletionType,
        showsSummary: Bool = true,
        onPersisted: (() -> Void)? = nil,
        peerInitiated: Bool = false
    ) {
        guard !sessionLocked else { return }

        guard isSessionActive, SoloTimeBasedSession.isActive, !showCompletionOverlay, !showSummary else {
            if !showsSummary { onPersisted?() }
            return
        }
        guard !sessionAlreadySaved else {
            if !showsSummary { onPersisted?() }
            return
        }

        if trainingMode == .partner, isManagingSession, completionType != .abandoned {
            guard CurrentSessionStore.shared.tryMarkPartnerTimedSessionEndHandled() else { return }
            if !peerInitiated {
                TrainingPartnerConnectionCoordinator.shared.broadcastPartnerTimedSessionEnded(source: .display)
            }
        }

        sessionLocked = true
        sessionAlreadySaved = true

        let exitReason: SessionExitReason = {
            switch completionType {
            case .earlyExit: return .userEnd
            case .abandoned: return .appBackgrounded
            case .completed:
                return isFreeMode ? .userEnd : .timerExpired
            }
        }()
        SessionStartCueRepGate.endSession(reason: exitReason)

        let timerElapsedBeforeStop = sessionTimer.elapsedSeconds()
        sessionTimer.stop()
        let timerElapsedAfterStop = sessionTimer.elapsedSeconds()
        let fallbackElapsed = sessionStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        completionElapsed = max(timerElapsedBeforeStop, timerElapsedAfterStop, fallbackElapsed)
        completionRepCount = totalRepCount
        summaryActivityRepCounts = activityRepCounts
        recordedRepTokens.removeAll()
        currentCycleId = 0
        CurrentSessionStore.shared.markSessionCompletionType(completionType)

        print("[SESSION COMPLETE] id=\(sessionId?.uuidString ?? "nil") mode=\(mode) reps=\(totalRepCount) duration=\(durationLabel) completion=\(completionType) host=\(isHostDevice)")

        lastCompletionType = completionType
        summaryDurationText = SoloSessionTimeFormat.mmss(completionElapsed)

        if trainingMode == .partner, !mayWriteSupabase {
            ActivityStatsStore.shared.ingestSessionCounts(summaryActivityRepCounts)
            isSessionActive = false
            TrainingPartnerConnectionCoordinator.shared.broadcastTimedSessionInactiveFromDisplay()
            if showsSummary {
                showSummary = true
            } else {
                // End Session / Home: drop the timed shell immediately so the next coach
                // `sessionStarted` can navigate from Connected standby (pairing stays live).
                releaseShellAfterEndWithoutSummary(then: onPersisted)
            }
            return
        }

        if showsSummary {
            persistSessionSummary(completionType: completionType)
            if trainingMode == .solo {
                FirstSessionOnboardingStore.prepareLoginPromptAfterSoloTimedSessionIfNeeded(
                    repCount: completionRepCount,
                    elapsedSeconds: completionElapsed
                )
            }
            isSessionActive = false
            if trainingMode == .partner {
                TrainingPartnerConnectionCoordinator.shared.broadcastTimedSessionInactiveFromDisplay()
            }
            showSummary = true
            return
        }

        // Persist first (needs CurrentSessionStore), then clear the managing shell.
        persistSessionSummary(completionType: completionType, onPersisted: { [weak self] in
            guard let self else { return }
            // A new coach-started session may already be managing — don't wipe it.
            if self.isManagingSession {
                onPersisted?()
                return
            }
            self.releaseShellAfterEndWithoutSummary(then: onPersisted)
        })
        isSessionActive = false
        // Unlock navigation immediately — don't wait on Supabase before the next sessionStarted.
        isManagingSession = false
        sessionLocked = false
        if trainingMode == .partner {
            TrainingPartnerConnectionCoordinator.shared.broadcastTimedSessionInactiveFromDisplay()
            TrainingPartnerConnectionCoordinator.shared.softResetAfterTimedPartnerSessionEnd()
        }
    }

    /// Clears the timed-session shell after End Session without summary. Pairing is preserved.
    private func releaseShellAfterEndWithoutSummary(then onPersisted: (() -> Void)?) {
        let wasPartner = trainingMode == .partner
        clear()
        if wasPartner {
            TrainingPartnerConnectionCoordinator.shared.softResetAfterTimedPartnerSessionEnd()
        }
        onPersisted?()
    }

    func completeSummaryDone(popToRoot: () -> Void) {
        if trainingMode == .solo {
            FirstSessionOnboardingStore.completeSoloTimedFeedbackDismiss(
                clearSession: { self.clear() },
                dismissOverlay: { self.showSummary = false },
                popToRoot: popToRoot
            )
        } else {
            showSummary = false
            clear()
            popToRoot()
        }
    }

    func completeSummaryTrainAgain(route: () -> Void) {
        showSummary = false
        clear()
        route()
    }

    /// Partner timed session: dismiss summary and restart on the same relay pairing (no navigation reset).
    func preparePartnerTrainAgain(
        initialActivity: ActivityKind,
        playerId: UUID?
    ) {
        guard trainingMode == .partner else { return }

        isPartnerTrainAgainBootstrapping = true
        showSummary = false
        sessionLocked = false
        sessionAlreadySaved = false
        isSessionEnding = false
        showCompletionOverlay = false
        completionElapsed = 0
        completionRepCount = 0
        lastCompletionType = nil
        summaryDurationText = ""
        summaryActivityRepCounts = [:]
        totalRepCount = 0
        activityRepCounts = [:]
        recordedRepTokens.removeAll()
        currentCycleId = 0
        blockNumber = 1
        hasStartedTimer = false
        isManagingSession = false
        isSessionActive = false
        currentActivity = initialActivity
        primaryActivity = initialActivity
        self.playerId = playerId

        sessionTimer.stop()
        if SoloTimeBasedSession.config != nil {
            SoloTimeBasedSession.restartSessionClock()
        }
        CurrentSessionStore.shared.clear()
        CurrentSessionStore.shared.resetPartnerTimedSessionEndHandled()
        TrainingPartnerConnectionCoordinator.shared.softResetAfterTimedPartnerSessionEnd()
        SessionStartCueRepGate.preparePartnerTimedTrainAgain()

        Task { @MainActor in
            defer { isPartnerTrainAgainBootstrapping = false }
            print("[TimedSession] partner trainAgain bootstrap started activity=\(initialActivity.sessionActivityActivityId)")
            await beginIfNeeded(
                initialActivity: initialActivity,
                mode: .partner,
                playerId: playerId
            )

            guard let config = SoloTimeBasedSession.config else {
                SessionStartCueRepGate.abortPartnerTrainAgainBootstrap()
                print("[TimedSession] partner trainAgain aborted — no duration config")
                return
            }

            activitySurfaceGeneration += 1
            // Let recycled drill surfaces finish onAppear before unlocking reps / coach.
            await Task.yield()

            SoloTimeBasedSession.restartSessionClock()
            startOrResumeSessionTimer(choice: config)
            SessionStartCueRepGate.completePartnerTimedTrainAgain()

            print("[TimedSession] partner trainAgain complete activity=\(currentActivity?.sessionActivityActivityId ?? "nil") timer=\(timerDisplayText) reps=\(totalRepCount)")
        }
    }

    func completeFeedbackDismiss(popToRoot: () -> Void) {
        if trainingMode == .solo {
            FirstSessionOnboardingStore.completeSoloTimedFeedbackDismiss(
                clearSession: { self.clear() },
                dismissOverlay: { self.showCompletionOverlay = false },
                popToRoot: popToRoot
            )
        } else {
            clear()
            showCompletionOverlay = false
            popToRoot()
        }
    }

    /// Coach device: display timed container is live (duration chosen, session begun).
    func markPartnerDisplaySessionActiveFromRelay() {
        isSessionActive = true
    }

    func markPartnerSessionStartChromeCompleted() {
        partnerSessionStartChromeCompleted = true
    }

    /// Coach device: display awaiting duration or session ended — hold rep UI / haptics.
    func prepareCoachRemoteForPartnerDurationSelection() {
        isSessionActive = false
    }

    /// Background or app termination — persist partial session without requiring End Session.
    func abandonSessionDueToAppLifecycle() {
        guard isManagingSession, isSessionActive, SoloTimeBasedSession.isActive else { return }
        guard !sessionAlreadySaved, !sessionLocked else { return }

        sessionLocked = true
        sessionAlreadySaved = true

        sessionTimer.stop()
        let timerElapsed = sessionTimer.elapsedSeconds()
        let fallbackElapsed = sessionStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        completionElapsed = max(timerElapsed, fallbackElapsed)

        CurrentSessionStore.shared.markSessionCompletionType(.abandoned)
        SessionStartCueRepGate.endSession(reason: .appBackgrounded)

        print("[SESSION ABANDON] id=\(sessionId?.uuidString ?? "nil") mode=\(mode) reps=\(totalRepCount) duration=\(SoloSessionTimeFormat.mmss(completionElapsed))")

        let wasPartner = trainingMode == .partner
        isSessionActive = false

        if wasPartner {
            TrainingPartnerConnectionCoordinator.shared.broadcastTimedSessionInactiveFromDisplay()
        }

        guard mayWriteSupabase, CurrentSessionStore.shared.sessionId != nil else {
            clear()
            return
        }

        beginBackgroundPersistIfNeeded()
        persistSessionSummary(completionType: .abandoned) { [weak self] in
            self?.endBackgroundPersist()
            self?.clear()
        }
    }

    func clear() {
        let wasPartner = trainingMode == .partner
        SessionStartCueRepGate.endSession(reason: .sessionCleared)
        SoloTimeBasedSession.clear()
        sessionTimer.stop()
        isManagingSession = false
        isSessionActive = false
        sessionLocked = false
        currentActivity = nil
        primaryActivity = nil
        hasStartedTimer = false
        sessionAlreadySaved = false
        showCompletionOverlay = false
        showSummary = false
        isSessionEnding = false
        completionElapsed = 0
        completionRepCount = 0
        lastCompletionType = nil
        summaryDurationText = ""
        totalRepCount = 0
        activityRepCounts = [:]
        summaryActivityRepCounts = [:]
        recordedRepTokens.removeAll()
        currentCycleId = 0
        blockNumber = 1
        playerId = nil
        repTarget = nil
        partnerSessionStartChromeCompleted = false
        CurrentSessionStore.shared.clear()
        if wasPartner {
            TrainingPartnerConnectionCoordinator.shared.broadcastTimedSessionInactiveFromDisplay()
        }
    }

    /// Reattach container UI to an existing Supabase session (reconnect / foreground) without creating a new row.
    private func resumeManagingSession(
        initialActivity: ActivityKind,
        mode: TrainingMode,
        playerId: UUID?,
        existingSessionId: UUID
    ) {
        trainingMode = mode
        repTarget = SoloTimeBasedSession.config?.repTarget
        isManagingSession = true
        isSessionActive = true
        sessionLocked = false
        sessionAlreadySaved = false
        primaryActivity = primaryActivity ?? initialActivity
        currentActivity = initialActivity
        self.playerId = playerId ?? self.playerId
        if CurrentSessionStore.shared.sessionId != existingSessionId {
            CurrentSessionStore.shared.setSessionIdOnly(
                existingSessionId,
                mode: SessionAnalyticsMode.from(trainingMode: mode),
                startAnalyticsClock: mode != .solo
            )
        } else if CurrentSessionStore.shared.analyticsMode == nil {
            CurrentSessionStore.shared.setAnalyticsMode(SessionAnalyticsMode.from(trainingMode: mode))
        }
        objectWillChange.send()
    }

    private func registerActivitySegment(for activity: ActivityKind) async {
        prepareActivitySegment(activity: activity)
        guard mayWriteSupabase else {
            print("[TimedSession] registerActivitySegment skipped — mayWriteSupabase=false activity=\(activity.sessionActivityActivityId)")
            return
        }
        guard let sessionId = CurrentSessionStore.shared.sessionId else {
            print("[TimedSession] registerActivitySegment skipped — no sessionId activity=\(activity.sessionActivityActivityId)")
            return
        }
        let block = await SupabaseSessionService.shared.openSessionActivityBlock(
            sessionId: sessionId,
            activityId: activity.sessionActivityActivityId,
            blockNumber: blockNumber
        )
        if let activityId = block.sessionActivityId {
            CurrentSessionStore.shared.setCurrentSessionActivityId(activityId)
        }
        if let segmentId = block.segmentId {
            CurrentSessionStore.shared.setCurrentSessionActivitySegmentId(
                segmentId,
                activityId: activity.sessionActivityActivityId
            )
            currentCycleId = 0
        }
        print("[TimedSession] segment opened activity=\(activity.sessionActivityActivityId) block=\(blockNumber) segmentId=\(block.segmentId?.uuidString ?? "nil")")
    }

    private func closeCurrentActivitySegmentInSupabase() async {
        guard mayWriteSupabase else { return }
        let store = CurrentSessionStore.shared
        if let segmentId = store.currentSessionActivitySegmentId {
            let reps = store.currentSegmentRepCount
            let activityId = store.currentSegmentActivityId ?? "unknown"
            await SupabaseSessionService.shared.endSessionActivitySegment(
                segmentId: segmentId,
                activityId: activityId,
                repCount: reps
            )
            store.clearCurrentSessionActivitySegment()
        }
        if let activityId = store.currentSessionActivityId {
            await SupabaseSessionService.shared.endSessionActivity(sessionActivityId: activityId)
        }
    }

    private func persistSessionSummary(
        completionType: SessionCompletionType,
        onPersisted: (() -> Void)? = nil
    ) {
        guard mayWriteSupabase else {
            onPersisted?()
            return
        }
        guard let sessionId = CurrentSessionStore.shared.sessionId else {
            print("[SESSION SAVE] skipped — no session id (mode=\(trainingMode) host=\(isHostDevice))")
            onPersisted?()
            return
        }
        Task {
            await closeCurrentActivitySegmentInSupabase()
            let segmentCounts = await SupabaseSessionService.shared.fetchAggregatedSegmentRepCounts(sessionId: sessionId)
            await MainActor.run {
                if let segmentCounts, !segmentCounts.isEmpty {
                    self.summaryActivityRepCounts = segmentCounts
                    ActivityStatsStore.shared.ingestSessionCounts(segmentCounts)
                } else {
                    ActivityStatsStore.shared.ingestSessionCounts(self.activityRepCounts)
                }
                self.writeSessionRecordToSupabase(
                    sessionId: sessionId,
                    completionType: completionType,
                    onSynced: onPersisted
                )
            }
        }
    }

    private func writeSessionRecordToSupabase(
        sessionId: UUID,
        completionType: SessionCompletionType,
        onSynced: (() -> Void)? = nil
    ) {
        let activity = primaryActivity ?? currentActivity ?? .awayFromPressure
        let repCount = max(totalRepCount, 0)
        print("[SESSION SAVE] mode=\(trainingMode) host=\(isHostDevice) reps=\(repCount) completion=\(completionType.rawValue)")
        let endedAt = Date()
        let record = SessionRecord(
            id: sessionId,
            date: endedAt,
            activity: activity,
            gridSize: .fiveByFive,
            difficulty: .standard,
            reps: repCount,
            decisionsCompleted: repCount,
            correct: 0,
            forwardCorrect: nil,
            speedBucket: nil,
            bias: nil,
            avgLatency: nil,
            profile: nil,
            playerId: playerId
        )
        SupabaseSessionService.shared.saveSession(
            record: record,
            decisions: [],
            sessionMode: SessionAnalyticsMode.from(trainingMode: trainingMode),
            durationSeconds: Int(completionElapsed.rounded()),
            endedAt: endedAt,
            onSynced: onSynced
        )
    }

#if canImport(UIKit)
    private func beginBackgroundPersistIfNeeded() {
        guard backgroundPersistTaskID == .invalid else { return }
        backgroundPersistTaskID = UIApplication.shared.beginBackgroundTask(withName: "TimedSessionPersist") { [weak self] in
            self?.endBackgroundPersist()
        }
    }

    private func endBackgroundPersist() {
        guard backgroundPersistTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundPersistTaskID)
        backgroundPersistTaskID = .invalid
    }
#else
    private func beginBackgroundPersistIfNeeded() {}
    private func endBackgroundPersist() {}
#endif
}
