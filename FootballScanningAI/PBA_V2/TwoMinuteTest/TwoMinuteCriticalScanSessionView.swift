//
//  TwoMinuteCriticalScanSessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Display: same layout as Dribble or Pass (center X, four slots). Ball appears at one slot when coach triggers PASS.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine

/// Holds path for the results fullScreenCover so "Start Training" → role selection → Display → training mode → setup works inside the cover.
private final class ResultsCoverPathHolder: ObservableObject {
    @Published var path = NavigationPath()
    func push(_ route: AppRoute) {
        path.append(route)
    }
}

private func routeForActivity(_ activity: ActivityKind, trainingMode: TrainingMode) -> AppRoute {
    switch activity {
    case .twoMinuteTest:
        return .twoMinuteGetReady(mode: trainingMode)
    case .awayFromPressure:
        return .awayFromPressureSetup(mode: trainingMode)
    case .dribbleOrPass:
        return .dribbleOrPassSetup(mode: trainingMode)
    case .oneTouchPassing:
        return .oneTouchPassingSetup(mode: trainingMode)
    }
}

struct TwoMinuteCriticalScanSessionView: View {
    let config: TwoMinuteTestConfig
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @StateObject private var engine: TwoMinuteCriticalScanEngine
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController
    @Environment(\.scenePhase) private var scenePhase
    @State private var testResultItem: TwoMinuteResultItem?
    @State private var nextRepIndex = 0
    @StateObject private var sessionManager = TwoMinuteSessionManager()
    @StateObject private var resultsCoverPathHolder = ResultsCoverPathHolder()
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var currentSessionStore = CurrentSessionStore.shared
    @State private var pendingTrainingRoute: AppRoute?
    @State private var hasSentSessionEnded = false
    /// True while ``SessionCountdownModifier`` shows 3–2–1–Go; coach drill messages must not advance the engine until the drill is visible.
    @State private var blockCoachDrillDuringSessionCountdown = false
    /// Latest coach `nextRep` deferred until countdown ends or engine reaches ``CriticalScanPhase/waitingForNextRep``.
    @State private var pendingNextRepIndex: Int?
    @State private var isTearingDownForNewSession: Bool = false
    /// Tracks applied coach reps for stale detection (debug); coach index is authoritative when advancing.
    @State private var partnerCoachRepGate = PartnerCoachRepSequenceGate()
    @StateObject private var repController = RepStateController()
    /// Solo: post-beep delay uses shared `AppStorageKeys.soloReturnTime` (same key as wall calibration), not `calibratedReturnTime` alone.
    @StateObject private var soloWallCalibration = SoloWallCalibrationController()
    @StateObject private var soloLoopRunner = SoloLoopRunner()
    @State private var isSoloRunning = false
    /// Display-side relay (join code, WebSocket, coach paired). Used when `partnerTransportMode == .relayWebSocket`.
    /// Conforms to ``PartnerRelayDisplayControlling``; concrete type is ``PartnerRelayDisplaySession``.
    @ObservedObject private var partnerRelaySession: PartnerRelayDisplaySession
    @State private var hasCompletedPassTempoCalibration = false
    @State private var showPassTempoCalibration = false
    @State private var showCalibrationChoicePrompt = false
    @State private var partnerCalibration = PartnerPassTempoCalibrationTracker()
    @State private var showConnectedConfirmation = false
    @State private var hasStartedConnectedToCalibrationTransition = false
    @State private var startedWithoutSavedCalibration = false
    @State private var justCompletedCalibrationThisSession = false
    @State private var soloRepTimingScheduler = SoloRepTimingScheduler()
    /// Solo: wall time when the current rep's beep fired; anchors pass tolerance window.
    @State private var soloRepBeepWallTime: Date?
    @State private var soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.totalReps(for: .twoMinuteTest)
    @State private var soloLifetimeRecordedRepIndices = Set<Int>()
    @StateObject private var soloSessionTimer = SoloSessionTimerController()
    @StateObject private var soloActionIdleCue = SoloActionIdleCueState()
    @State private var sessionStartCueContent: ActivitySessionStartCueContent?
    @State private var hasPresentedSessionStartCue = false
    @State private var sessionStartCueHeight: CGFloat = 0
    @State private var showSoloTimedComplete = false
    @State private var isSoloSessionEnding = false
    @State private var soloTimedCompleteElapsed: TimeInterval = 0
    @State private var soloTimedCompleteReps = 0
    @State private var soloWallBootResolved = false

    private var showsDrillFocalLayout: Bool {
        SoloWallCalibrationDisplayPolicy.showsDrillFocalLayout(
            mode: mode,
            isCalibrating: soloWallCalibration.isCalibrating,
            bootResolved: soloWallBootResolved
        )
    }

    init(config: TwoMinuteTestConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        let repCount = SoloTimeBasedSession.blockRepCount(
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
            soloFallback: 10,
            mode: mode
        )
        _engine = StateObject(wrappedValue: TwoMinuteCriticalScanEngine(
            config: config,
            trainingMode: mode,
            repPlans: TwoMinuteRepPlanner.generatePlan(forBlockSize: repCount)
        ))
        _partnerRelaySession = ObservedObject(wrappedValue: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession)
    }

    private var blockTotalReps: Int {
        SoloTimeBasedSession.blockRepCount(
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
            soloFallback: 10,
            mode: mode
        )
    }

    private var effectiveUsesAutoLoop: Bool {
        SoloTimeBasedDisplaySessionSupport.effectiveUsesAutoLoop(mode: mode)
    }

    private var isSoloDrillInputFrozen: Bool {
        SoloTimeBasedDisplaySessionSupport.shouldBlockSoloDrillInput(
            isEnding: isSoloSessionEnding,
            showComplete: showSoloTimedComplete
        )
    }

    private var sessionTransportMode: SessionTransportMode {
        PartnerTransportPolicy.transportMode(for: .twoMinute, trainingMode: mode)
    }

    private var showsBetweenRepPlayerText: Bool {
        DisplaySessionPlayerTextPolicy.showsBetweenRepPlayerText(for: engine.phase)
    }

    private var isBallVisible: Bool {
        if case .ballVisible = engine.phase { return true }
        return false
    }

    private var sessionStack: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showsDrillFocalLayout {
                dribbleOrPassLayout
            }
            if SoloWallCalibrationDisplayPolicy.showsTrainingSessionChrome(
                mode: mode,
                isCalibrating: soloWallCalibration.isCalibrating,
                bootResolved: soloWallBootResolved
            ) {
                statusOverlay
                    .opacity(isBallVisible ? 0.25 : 1)
            }
            waitingForCoachOverlay
            if mode != .solo, showsBetweenRepPlayerText {
                repCountOverlay
            }
            if mode == .partner, showExitLogButtons, let repIndex = repIndexForExit {
                twoMinuteExitLogOverlay(repIndex: repIndex)
                    .zIndex(2)
            }
            if mode.requiresPhoneDisplayRelay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }
            }
            if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
            }
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(125)
            SoloWallCalibrationGetReadyOverlay(mode: mode, calibration: soloWallCalibration)
            if mode == .solo, soloActionIdleCue.showTapHint, !soloWallCalibration.isCalibrating {
                SoloActionTapHintView()
                    .zIndex(50)
                    .transition(.opacity)
            }
        }
    }

    private var sessionContentWithCover: some View {
        sessionStack
            .contentShape(Rectangle())
            .onTapGesture {
                if SoloWallCalibrationInput.handleIfSoloCalibrating(
                    mode: mode,
                    controller: soloWallCalibration,
                    soundEnabled: settingsViewModel.soundEnabled,
                    activateAudio: { activateAudioSession() },
                    preloadBeep: { preloadBeepAssetsForInstantReveal() },
                    onCompletedThreePass: onTwoMinuteSoloWallCalibrationFinished
                ) { return }
                guard !isSoloDrillInputFrozen else { return }
                if mode == .solo, !effectiveUsesAutoLoop { handleWallSoloTrigger() }
            }
            .soloSessionTimerOverlay(
                isVisible: mode == .solo && !soloWallCalibration.isCalibrating && soloSessionTimer.isVisible,
                text: soloSessionTimer.displayText,
                onFreePlayEnd: soloFreeModeEndAction
            )
            .soloSessionCompleteOverlay(
                isPresented: showSoloTimedComplete,
                elapsedSeconds: soloTimedCompleteElapsed,
                repCount: soloTimedCompleteReps,
                onDone: {
                    SoloTimeBasedSession.clear()
                    showSoloTimedComplete = false
                    router.popToRoot()
                }
            )
            .fullScreenCover(item: $testResultItem) { item in
                NavigationStack(path: $resultsCoverPathHolder.path) {
                    TwoMinuteTestResultsView(
                        result: item.result,
                        repLogs: item.logs,
                        profileManager: profileManager,
                        settingsViewModel: settingsViewModel,
                        onDismissCover: { testResultItem = nil },
                        onStartTraining: { activity in
                            let route = routeForActivity(activity, trainingMode: mode)
                            #if DEBUG
                            print("[PBA-Debug] TwoMinute StartTraining tapped: selectedPlayerId=\(playerStore.selectedPlayerId?.uuidString ?? "nil"), route=\(route)")
                            #endif
                            pendingTrainingRoute = route
                            testResultItem = nil
                        },
                        showTimingAdaptationFeedback: item.showTimingAdaptationFeedback,
                        trainingMode: mode
                    )
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
                    .environmentObject(coachRemoteRequiredPrompt)
                }
                .navigationDestination(for: AppRoute.self) { route in
                    resultsCoverRouteView(route, pathHolder: resultsCoverPathHolder)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            }
    }

    /// Split from `body` so the SwiftUI type checker can finish in reasonable time.
    private var sessionContentWithSessionModifiers: some View {
        sessionContentWithCover
            .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main), perform: handleTwoMinuteMessage)
            .onReceive(NotificationCenter.default.publisher(for: .partnerSoftReconnectRepRestart).receive(on: RunLoop.main)) { _ in
                guard !TrainingPartnerConnectionCoordinator.shared.isPartnerSoftReconnectRepRestartSuppressed else { return }
                applyPartnerSoftReconnectAfterTransportRestoreTwoMinute()
            }
            .onReceive(NotificationCenter.default.publisher(for: .partnerDisplayWillStartNewSessionFromDisconnect).receive(on: RunLoop.main)) { _ in
                applyPartnerStartNewSessionLocalTeardownTwoMinute()
            }
            .onChange(of: engine.currentRepIndex) { _, newValue in
                guard mode.requiresPhoneDisplayRelay else { return }
                TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                    newValue,
                    activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId
                )
            }
            .onChange(of: engine.phase) { oldPhase, newPhase in
                handlePhaseChange(oldPhase, newPhase)
            }
            .onChange(of: testResultItem) { old, new in
                handleTestResultItemChange(old: old, new: new)
                if new == nil { resultsCoverPathHolder.path = NavigationPath() }
            }
            .onChange(of: popToRootTrigger.request, handlePopToRootChange)
            .onAppear(perform: handleOnAppear)
            .onDisappear(perform: handleOnDisappear)
            .onChange(of: scenePhase, handleScenePhaseChange)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                scheduleTwoMinutePartnerSuspendForBackgroundNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification)) { _ in
                scheduleTwoMinutePartnerSuspendForBackgroundNotification()
            }
            .onChange(of: connectionManager.connectedPeerName, handleConnectedPeerChange)
            .onChange(of: coachConnectedForCalibration) { _, connected in
                guard mode.requiresPhoneDisplayRelay else { return }
                if connected {
                    beginConnectedToCalibrationTransitionIfNeeded()
                } else {
                    showConnectedConfirmation = false
                    hasStartedConnectedToCalibrationTransition = false
                    showPassTempoCalibration = false
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
    }

    var body: some View {
        sessionContentWithSessionModifiers
            .sessionCountdown(
                waitForPartnerReady: mode.requiresPhoneDisplayRelay,
                partnerReady: partnerReadyForCountdown,
                suppressCoachMessagesDuringCountdown: $blockCoachDrillDuringSessionCountdown,
                isEnabled: !effectiveUsesAutoLoop
            )
            .onChange(of: blockCoachDrillDuringSessionCountdown) { old, new in
                if old == true, new == false {
                    tryPresentSessionStartCue()
                }
                tryStartSoloAutoloop()
                SoloActionIdleCue.handleCountdownEnded(
                    mode: mode,
                    wasBlocking: old,
                    isBlocking: new,
                    isWaitingForNextRep: { if case .waitingForNextRep = engine.phase { true } else { false } }(),
                    cue: soloActionIdleCue
                )
                guard mode.requiresPhoneDisplayRelay, old == true, new == false else { return }
                flushPendingCoachNextRepAfterCountdown()
            }
            .onChange(of: soloWallCalibration.isCalibrating) { _, isCalibrating in
                guard !isCalibrating else { return }
                tryPresentSessionStartCue()
                tryStartSoloAutoloop()
            }
            .onChange(of: hasCompletedPassTempoCalibration) { _, completed in
                guard completed else { return }
                tryPresentSessionStartCue()
                if mode == .solo {
                    onSoloCalibrationReadyIfNeeded()
                } else {
                    tryStartSoloAutoloop()
                }
            }
            .onChange(of: showPassTempoCalibration) { old, new in
                guard old == true, new == false else { return }
                if mode == .solo {
                    onSoloCalibrationReadyIfNeeded()
                } else {
                    tryStartSoloAutoloop()
                }
            }
            .onChange(of: showCalibrationChoicePrompt) { old, new in
                guard old == true, new == false else { return }
                if mode == .solo {
                    onSoloCalibrationReadyIfNeeded()
                } else {
                    tryStartSoloAutoloop()
                }
            }
            .fullScreenCover(isPresented: $showCalibrationChoicePrompt) {
                TwoMinuteCalibrationPromptView(
                    hasExistingCalibration: PartnerPassTempoCalibrationStore.hasSavedCalibration,
                    onStartCalibration: {
                        showCalibrationChoicePrompt = false
                        showPassTempoCalibration = true
                    },
                    onSkip: {
                        showCalibrationChoicePrompt = false
                        if PBASessionFlowPolicy.shouldPromptCalibration(for: mode) {
                            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nil)
                        }
                    }
                )
                .interactiveDismissDisabled()
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { showPassTempoCalibration && !mode.requiresPhoneDisplayRelay },
                    set: { showPassTempoCalibration = $0 }
                )
            ) {
                PassTempoCalibrationScreen { calibrated in
                    CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(calibrated)
                    if let calibrated {
                        PartnerPassTempoCalibrationStore.save(averageTravelTimeSeconds: calibrated, trainingMode: mode)
                        justCompletedCalibrationThisSession = true
                    }
                    hasCompletedPassTempoCalibration = true
                    showPassTempoCalibration = false
                }
                .interactiveDismissDisabled()
            }
            .onReceive(NotificationCenter.default.publisher(for: .relayForegroundReconnectCompleted)) { _ in
                guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket else { return }
                alignEngineRepWithCoordinatorSnapshotAfterRelayForegroundTwoMinute()
                engine.synchronizeTimersAfterEnteringForeground()
                PartnerRelayCheckpointDisplaySend.sendIfReady(
                    engine: engine,
                    activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
                    relay: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                      type == .ended else { return }
                activateAudioSession()
            }
    }

    private func handleTwoMinuteMessage(_ notification: Notification) {
        guard mode.requiresPhoneDisplayRelay, let msg = notification.object as? TwoMinuteMessage else { return }
        switch msg {
        case .calibrationPassTapped(let timestamp):
            partnerCalibration.handlePassTap(timestamp: timestamp)
            return
        case .calibrationArrivalTapped(let timestamp):
            partnerCalibration.handleArrivalTap(timestamp: timestamp)
            if partnerCalibration.reachedTarget {
                completePartnerCalibration(averageTravelTime: partnerCalibration.averageTravelTime)
            }
            return
        case .calibrationFinished(let averageTravelTimeSeconds):
            completePartnerCalibration(averageTravelTime: averageTravelTimeSeconds)
            return
        case .startNextBlock:
            print("[DISPLAY] Received startNextBlock activity=twoMinuteTest")
            twoMinuteApplyCoachStartNextBlock()
            return
        default:
            break
        }
        if !hasCompletedPassTempoCalibration && !mode.requiresPhoneDisplayRelay { return }
        let shouldBlockCoachDrillMessages = blockCoachDrillDuringSessionCountdown && !coachConnectedForCalibration
        if PartnerCountdownCoachMessagePolicy.shouldDeferWhileCountdown(
            msg: msg,
            isBlockingDrillMessagesFromCoach: shouldBlockCoachDrillMessages,
            pendingNextRepIndex: &pendingNextRepIndex
        ) {
            return
        }
        switch msg {
        case .repStarted:
            return
        case .nextRep(let repIndex):
            applyPartnerCoachNextRep(repIndex: repIndex)
        case .passTriggered(let repIndex, let timestamp):
            guard twoMTAllowsPassTrigger(repIndex: repIndex) else { return }
            guard repController.state == .preBeep || repController.state == .decisionWindow else { return }
            guard !repController.hasLoggedTap else { return }
            repController.registerTap()
            #if DEBUG
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .twoMinuteTest, kind: "passTriggered", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            #endif
            twoMinuteApplyPassTrigger(repIndex: repIndex, passTimestamp: timestamp)
        case .exitLogged(let repIndex, let gate, let timestamp):
            guard twoMTAllowsExitLogged(repIndex: repIndex) else { return }
            guard repController.canAcceptSwipe() else { return }
            #if DEBUG
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .twoMinuteTest, kind: "exitLogged", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .twoMinuteTest, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "exitLogged")
            #endif
            if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                repController.registerSwipe()
                syncRepController(with: engine.phase)
                saveDecisionForRep(log: log)
            }
        case .incorrectDecision(let repIndex, let timestamp):
            guard twoMTAllowsIncorrectDecision(repIndex: repIndex) else { return }
            guard repController.canAcceptSwipe() else { return }
            #if DEBUG
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .twoMinuteTest, kind: "incorrectDecision", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .twoMinuteTest, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "incorrectDecision")
            #endif
            if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                repController.registerSwipe()
                syncRepController(with: engine.phase)
                saveDecisionForRep(log: log)
            }
        case .firstTouchLogged:
            break
        case .coachPaired:
            break
        case .sessionEnded:
            break
        case .partnerTrainingEnded:
            break
        case .partnerSessionCheckpoint:
            break
        case .sessionStarted:
            break
        case .beepArmed:
            // Display is the sender; ignore any echo that comes back.
            break
        case .calibrationPassTapped, .calibrationArrivalTapped, .calibrationFinished:
            break
        case .startNextBlock:
            break
        }
    }

    private func alignEngineRepWithCoordinatorSnapshotAfterRelayForegroundTwoMinute() {
        guard mode.requiresPhoneDisplayRelay else { return }
        let activityId = ActivityKind.twoMinuteTest.sessionActivityActivityId
        guard let stored = TrainingPartnerConnectionCoordinator.shared.authoritativePartnerDisplayRepIndex(for: activityId) else { return }
        engine.partnerForegroundResumeAlignRepIndex(blockRepCount: blockTotalReps, authoritativeRepIndex: stored)
        let safeRepIndex = max(0, min(stored, blockTotalReps - 1))
        var gate = partnerCoachRepGate
        gate.alignExpectedNextForCoachSoftReconnectReplay(repIndex: safeRepIndex)
        partnerCoachRepGate = gate
        TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(safeRepIndex, activityId: activityId)
        repController.completeRepCycleEnd()
        syncRepController(with: engine.phase)
    }

    private func applyPartnerSoftReconnectAfterTransportRestoreTwoMinute() {
        guard mode.requiresPhoneDisplayRelay else { return }
        pendingNextRepIndex = nil
        engine.partnerSoftAbandonCurrentRepAwaitCoachRedo(blockRepCount: blockTotalReps)
        let safeRepIndex = max(0, min(engine.currentRepIndex, blockTotalReps - 1))
        var gate = partnerCoachRepGate
        gate.alignExpectedNextForCoachSoftReconnectReplay(repIndex: safeRepIndex)
        partnerCoachRepGate = gate
        TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
            safeRepIndex,
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId
        )
        repController.completeRepCycleEnd()
        syncRepController(with: engine.phase)
    }

    private func applyPartnerStartNewSessionLocalTeardownTwoMinute() {
        guard !isTearingDownForNewSession else { return }
        isTearingDownForNewSession = true
        defer { isTearingDownForNewSession = false }
        pendingNextRepIndex = nil
        blockCoachDrillDuringSessionCountdown = false
        cancelStimulusAfterBeepWork()
        stopSoloAutoloop()
        soloWallCalibration.cancelPendingBeeps()
        engine.invalidateAllTimers()
        repController.resetForNewSession()
    }

    /// Coach hub “Start Next Block”: leave results / complete phase and reset without dropping relay.
    private func twoMinuteApplyCoachStartNextBlock() {
        testResultItem = nil
        nextRepIndex = 0
        pendingNextRepIndex = nil
        hasSentSessionEnded = false
        repController.reset()
        if mode.requiresPhoneDisplayRelay {
            partnerCoachRepGate.reset()
        }
        engine.restartBlockFromBeginning()
        syncRepController(with: engine.phase)
    }

    private func flushPendingCoachNextRepAfterCountdown() {
        guard let idx = pendingNextRepIndex else { return }
        pendingNextRepIndex = nil
        applyPartnerCoachNextRep(repIndex: idx)
    }

    /// Applies a single coach-originated rep start: coach is source of truth for rep index; display only buffers until `waitingForNextRep`.
    private func applyPartnerCoachNextRep(repIndex: Int) {
        guard sessionManager.isConnected else { return }
        #if DEBUG
        if repIndex > partnerCoachRepGate.expectedNextCoachRepIndex {
            print("[PartnerCoach][2MT] nextRep coach ahead of displayTrackedNext: coach=\(repIndex) displayNext=\(partnerCoachRepGate.expectedNextCoachRepIndex)")
        }
        #endif
        if case .complete = engine.phase { return }
        if case .waitingForNextRep = engine.phase, repIndex < partnerCoachRepGate.expectedNextCoachRepIndex {
            if repIndex + 1 == partnerCoachRepGate.expectedNextCoachRepIndex {
                sendRepStartedAck(repIndex: repIndex)
                #if DEBUG
                print("[PartnerCoach][2MT] duplicate nextRep \(repIndex) (already applied) — re-sent repStarted")
                #endif
            } else {
                #if DEBUG
                print("[PartnerCoach][2MT] ignoring stale nextRep \(repIndex) (displayTrackedNext=\(partnerCoachRepGate.expectedNextCoachRepIndex))")
                #endif
            }
            return
        }
        guard case .waitingForNextRep = engine.phase else {
            print("[NEXTREP] received repIndex=\(repIndex) while phase=\(engine.phase) currentRepIndex=\(engine.currentRepIndex)")
            engine.forceReadyForIncomingCoachNextRep()
            repController.completeRepCycleEnd()
            _ = tryCommitPartnerCoachNextRep(repIndex: repIndex)
            return
        }
        _ = tryCommitPartnerCoachNextRep(repIndex: repIndex)
    }

    private func twoMTDisplayEngineIsMidRep(repIndex: Int) -> Bool {
        switch engine.phase {
        case .armedScanning(let r, _, _), .beepedAwaitingPass(let r, _), .ballVisible(let r, _, _), .awaitingExitLog(let r, _):
            return r == repIndex
        case .waitingForNextRep, .complete:
            return false
        }
    }

    @discardableResult
    private func tryCommitPartnerCoachNextRep(repIndex: Int) -> Bool {
        print("[NEXTREP] received repIndex=\(repIndex) while phase=\(engine.phase) currentRepIndex=\(engine.currentRepIndex)")
        if repIndex < partnerCoachRepGate.expectedNextCoachRepIndex {
            if repIndex + 1 == partnerCoachRepGate.expectedNextCoachRepIndex, case .waitingForNextRep = engine.phase {
                sendRepStartedAck(repIndex: repIndex)
                pendingNextRepIndex = nil
                return true
            }
            if repIndex + 1 == partnerCoachRepGate.expectedNextCoachRepIndex {
                print("[NEXTREP BLOCKED] phase=\(engine.phase) expected=waitingForNextRep")
            }
            pendingNextRepIndex = nil
            return false
        }
        if repIndex < engine.currentRepIndex {
            pendingNextRepIndex = nil
            return false
        }
        if repIndex == engine.currentRepIndex {
            guard case .waitingForNextRep = engine.phase else {
                print("[NEXTREP BLOCKED] phase=\(engine.phase) expected=waitingForNextRep")
                return false
            }
        }
        if repIndex > engine.currentRepIndex {
            guard case .waitingForNextRep = engine.phase else {
                print("[NEXTREP BLOCKED] phase=\(engine.phase) expected=waitingForNextRep")
                return false
            }
        }
        repController.completeRepCycleEnd()
        if !repController.acceptIncomingNextRepAllowingCoachOverride() {
            if twoMTDisplayEngineIsMidRep(repIndex: repIndex) {
                sendRepStartedAck(repIndex: repIndex)
                pendingNextRepIndex = nil
                return true
            }
            return false
        }
        let wasWaitingForNextRep: Bool
        if case .waitingForNextRep = engine.phase {
            wasWaitingForNextRep = true
        } else {
            wasWaitingForNextRep = false
        }
        print("[NEXTREP APPLY] attempting repIndex=\(repIndex) from phase=\(engine.phase)")
        engine.onNextRep(repIndex: repIndex)
        print("[NEXTREP RESULT] phase now=\(engine.phase)")
        if wasWaitingForNextRep, case .waitingForNextRep = engine.phase {
            repController.completeRepCycleEnd()
            #if DEBUG
            print("[PartnerCoach][2MT] onNextRep did not arm (phase still waiting) — reverting repController; no ack")
            #endif
            return false
        }
        var gate = partnerCoachRepGate
        gate.recordNextRepSuccessfullyApplied(repIndex)
        partnerCoachRepGate = gate
        sendRepStartedAck(repIndex: repIndex)
        pendingNextRepIndex = nil
        return true
    }

    private func flushPendingPartnerCoachNextRepIfNeeded() {
        guard let idx = pendingNextRepIndex else { return }
        guard sessionManager.isConnected else { return }
        guard case .waitingForNextRep = engine.phase else { return }
        _ = tryCommitPartnerCoachNextRep(repIndex: idx)
    }

    private func twoMTAllowsPassTrigger(repIndex: Int, at passTime: Date = Date()) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .beepedAwaitingPass(let r, _):
            guard r == repIndex else { return false }
        case .armedScanning(let r, _, _):
            guard r == repIndex else { return false }
            if mode == .solo { return false }
        default:
            return false
        }
        if mode == .solo {
            guard let beepTime = soloRepBeepWallTime else { return false }
            // Tolerance window is measured from the beep (`soloRepBeepWallTime` in `playBeep`), not scan start.
            return SoloRepTiming.fromCalibration(soloWallCalibration.calibratedReturnTime)
                .acceptsPass(at: passTime, beepTime: beepTime)
        }
        return true
    }

    private func twoMTAllowsExitLogged(repIndex: Int) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .ballVisible(let r, _, _), .awaitingExitLog(let r, _):
            return r == repIndex
        case .waitingForNextRep:
            // Solo auto-exit runs after ball hide timer → `waitingForNextRep` (see `applySoloTwoMinuteAutoExitIfNeeded`).
            return mode == .solo && !mode.requiresPhoneDisplayRelay
        default:
            return false
        }
    }

    private func twoMTAllowsIncorrectDecision(repIndex: Int) -> Bool {
        twoMTAllowsExitLogged(repIndex: repIndex)
    }

    private func handlePhaseChange(_ oldPhase: CriticalScanPhase, _ newPhase: CriticalScanPhase) {
        if case .beepedAwaitingPass = oldPhase {
            if case .beepedAwaitingPass = newPhase { }
            else {
                cancelStimulusAfterBeepWork()
            }
        }
        syncRepController(with: newPhase)
        if case .complete = newPhase {
            cancelStimulusAfterBeepWork()
            stopSoloAutoloop()
            PlayerFirstRunGuidanceStore.markCompletedFirstRun(activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId)
            pendingNextRepIndex = nil
            if mode.requiresPhoneDisplayRelay {
                TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                    blockTotalReps,
                    activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId
                )
            }
            DispatchQueue.main.async {
                if mode == .solo, SoloTimeBasedSession.isActive {
                    finishSoloTimeBasedSession()
                } else {
                    testResultItem = TwoMinuteResultItem(
                        result: TwoMinuteTestResult.from(logs: engine.repLogs, difficulty: config.difficulty),
                        logs: engine.repLogs,
                        showTimingAdaptationFeedback: false
                    )
                    AnalyticsManager.shared.track(.twoMinuteTestCompleted, playerId: playerStore.selectedPlayerId)
                }
            }
        }
        if case .armedScanning = newPhase {
            preloadBeepAssetsForInstantReveal()
        }
        if case .beepedAwaitingPass = newPhase {
            if mode != .solo || !soloWallCalibration.isCalibrating {
                playBeep()
            }
        }
        let wasWaitingForNextRep = if case .waitingForNextRep = oldPhase { true } else { false }
        let isWaitingForNextRep = if case .waitingForNextRep = newPhase { true } else { false }
        SoloActionIdleCue.applyPhaseTransition(
            mode: mode,
            wasWaitingForNextRep: wasWaitingForNextRep,
            isWaitingForNextRep: isWaitingForNextRep,
            cue: soloActionIdleCue
        )
        if case .waitingForNextRep = newPhase {
            cancelStimulusAfterBeepWork()
            if mode == .solo, SoloTimeBasedSession.isActive, soloSessionTimer.pendingEndAfterCurrentRep {
                finishSoloTimeBasedSession()
            } else {
                SoloTimeBasedDisplaySessionSupport.notifyQuickRepAdvanceIfNeeded(mode: mode, soloLoopRunner: soloLoopRunner)
            }
        }
        if mode == .solo, !mode.requiresPhoneDisplayRelay,
           case .waitingForNextRep = newPhase,
           case .ballVisible(let oldR, let oldB, _) = oldPhase {
            DispatchQueue.main.async {
                self.applySoloTwoMinuteAutoExitIfNeeded(repIndex: oldR, ballGate: oldB)
            }
        }
    }

    /// Solo: partner-only exit arrows — auto-log the displayed ball gate so the rep scores and `nextRepIndex` advances.
    private func applySoloTwoMinuteAutoExitIfNeeded(repIndex: Int, ballGate: Gate) {
        guard mode == .solo, !mode.requiresPhoneDisplayRelay else { return }
        guard case .waitingForNextRep = engine.phase else { return }
        guard engine.currentRepIndex == repIndex else { return }
        logExit(repIndex: repIndex, gate: ballGate)
    }

    private func cancelStimulusAfterBeepWork() {
        soloRepTimingScheduler.cancelAll()
        soloRepBeepWallTime = nil
    }

    private func startRepSolo() {
        guard isSoloRunning, !isSoloDrillInputFrozen else { return }
        guard sessionStartCueContent == nil else { return }
        handleWallSoloTrigger()
    }

    private func tryStartSoloAutoloop() {
        guard effectiveUsesAutoLoop else { return }
        guard !isSoloDrillInputFrozen else { return }
        guard !soloWallCalibration.isCalibrating else { return }
        guard hasCompletedPassTempoCalibration else { return }
        guard !blockCoachDrillDuringSessionCountdown else { return }
        guard sessionStartCueContent == nil else { return }
        guard !soloLoopRunner.isRunning else { return }
        if case .complete = engine.phase { return }
        guard nextRepIndex < blockTotalReps else { return }
        isSoloRunning = true
        soloLoopRunner.start(settings: SoloTimingSettings.soloAutoloopSettings(wallController: soloWallCalibration)) { startRepSolo() }
    }

    private func startSoloLoop() {
        onSoloCalibrationReadyIfNeeded()
        tryStartSoloAutoloop()
    }

    private func stopSoloAutoloop() {
        isSoloRunning = false
        soloLoopRunner.stop()
    }

    /// Partner / relay pass → ball. Solo uses ``handleWallSoloTrigger`` via autoloop (same as AFP/DOP).
    private func twoMinuteApplyPassTrigger(repIndex: Int, passTimestamp: Date) {
        guard mode != .solo else { return }
        twoMinuteEnginePassTrigger(repIndex: repIndex, passTimestamp: passTimestamp)
    }

    private func twoMinuteEnginePassTrigger(repIndex: Int, passTimestamp: Date) {
        if mode == .solo, case .armedScanning = engine.phase { return }
        PBAFlowDebugLog.passReceived(repId: repIndex, timestamp: passTimestamp)
        #if DEBUG
        let wallBeforeEngine = Date()
        DecisionSpeedDebugLog.logDisplayBeforeEnginePass(activity: .twoMinuteTest, repIndex: repIndex, embeddedPass: passTimestamp, displayWallBeforeEngine: wallBeforeEngine)
        #endif
        engine.onPassTrigger(repIndex: repIndex, timestamp: passTimestamp)
        PBAFlowDebugLog.reveal(repId: repIndex, timestamp: Date())
    }

    private func handleTestResultItemChange(old: TwoMinuteResultItem?, new: TwoMinuteResultItem?) {
        if old != nil && new == nil {
            if let route = pendingTrainingRoute {
                pendingTrainingRoute = nil
                router.popToRoot()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    router.push(route)
                }
            } else {
                router.popToRoot()
            }
        }
    }

    private func handlePopToRootChange(old: Bool, new: Bool) {
        if new { dismiss() }
    }

    /// When the display loads: SessionManager creates session in Supabase and generates pairing code; UI shows pairing screen. Test does not start until coach connects.
    private func handleOnAppear() {
        if mode == .solo {
            soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.totalReps(for: .twoMinuteTest)
        }
        #if DEBUG
        PartnerPersistDebug.log("TwoMinuteCriticalScanSessionView onAppear")
        #endif
        onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        hasCompletedPassTempoCalibration = false
        showCalibrationChoicePrompt = false
        showPassTempoCalibration = false
        startedWithoutSavedCalibration = !PartnerPassTempoCalibrationStore.hasSavedCalibration
        justCompletedCalibrationThisSession = false
        partnerCalibration.reset()
        showConnectedConfirmation = false
        hasStartedConnectedToCalibrationTransition = false
        beginConnectedToCalibrationTransitionIfNeeded()
        if mode != .solo {
            soloWallCalibration.resetForNonSoloSession()
        }
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        if mode.requiresPhoneDisplayRelay {
            let partnerNeedsCalibration = PBASessionFlowPolicy.shouldPromptCalibration(for: .partner) && !coordinator.sessionCalibrationResolved
            if partnerNeedsCalibration {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nil)
            } else {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(
                    coordinator.sessionCalibrationAverageTravelTime ?? PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds()
                )
                hasCompletedPassTempoCalibration = true
            }
        } else if mode == .solo {
            let nominal = config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
            SoloSessionStart.applySoloWallCalibrationBoot(
                trainingMode: mode,
                controller: soloWallCalibration,
                nominalWallTravelSeconds: nominal,
                setHasCompletedPassTempoCalibration: { hasCompletedPassTempoCalibration = $0 },
                soundEnabled: settingsViewModel.soundEnabled,
                activateAudio: { activateAudioSession() },
                preloadBeep: { preloadBeepAssetsForInstantReveal() },
                onInlineCalibrationFinished: onTwoMinuteSoloWallCalibrationFinished
            )
        } else if let saved = PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds() {
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(saved)
            hasCompletedPassTempoCalibration = true
        } else {
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nil)
        }
        hasSentSessionEnded = false
        if mode.requiresPhoneDisplayRelay {
            TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
            if sessionTransportMode == .multipeer {
                TrainingPartnerConnectionCoordinator.shared.prepareMultipeerDisplayPartner(connectionManager: connectionManager)
            }
        }
        activateAudioSession()
        preloadBeepAssetsForInstantReveal()
        AnalyticsManager.shared.track(.twoMinuteTestStarted, playerId: playerStore.selectedPlayerId)
        // Relay: start join-code + WebSocket immediately (parallel with Supabase); no intentional delay before code.
        if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
            #if DEBUG
            print("[RelayWS-DEBUG] about to start relay partner session")
            #endif
            partnerRelaySession.onCoachPairingChanged = { connected in
                sessionManager.setConnected(connected)
            }
            Task {
                await TrainingPartnerConnectionCoordinator.shared.prepareRelayDisplayForActivity()
                await MainActor.run {
                    if partnerRelaySession.isCoachPaired {
                        sessionManager.setConnected(true)
                    }
                    #if DEBUG
                    PartnerPersistDebug.log("TwoMinuteCriticalScanSessionView prepareRelayDisplayForActivity finished (synced sessionManager if relay already paired)")
                    #endif
                }
            }
        }
        Task {
            await sessionManager.startSession(
                activity: .twoMinuteTest,
                blockSize: blockTotalReps,
                playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
            )
        }
        if mode == .solo, effectiveUsesAutoLoop {
            isSoloRunning = true
        }
        if effectiveUsesAutoLoop {
            tryPresentSessionStartCue()
        }
        if !mode.requiresPhoneDisplayRelay {
            configureCalibrationStartFlowForCurrentMode()
        }
        if mode == .solo {
            if effectiveUsesAutoLoop {
                syncRepController(with: engine.phase)
                if !soloWallCalibration.isCalibrating {
                    startSoloLoop()
                }
            }
            onSoloCalibrationReadyIfNeeded()
        }
        soloWallBootResolved = true
    }

    private func handleOnDisappear() {
        soloWallCalibration.cancelPendingBeeps()
        cancelStimulusAfterBeepWork()
        stopSoloAutoloop()
        pendingNextRepIndex = nil
        if mode.requiresPhoneDisplayRelay {
            // Do not send sessionEnded while persisting — coach app treats it as a full disconnect (clears join / hub).
            if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    print("[RelayWS-DEBUG] persist partner pairing — skip sessionEnded + relay tearDown (Home / next activity)")
                }
                if sessionTransportMode == .multipeer {
                    print("[Multipeer] TrainingPartnerSession: display onDisappear — skip sessionEnded + stopHosting (training session active)")
                }
                #endif
            } else {
                sendSessionEndedIfNeeded()
                partnerRelaySession.tearDown()
                if sessionTransportMode == .multipeer {
                    connectionManager.stopHosting()
                }
            }
        }
        let preserveCoachConnection =
            mode.requiresPhoneDisplayRelay
            && TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing
            && sessionTransportMode == .relayWebSocket
            && partnerRelaySession.isCoachPaired
        #if DEBUG
        PartnerPersistDebug.log("TwoMinuteCriticalScanSessionView onDisappear — sessionManager.clear(preserveCoachConnection: \(preserveCoachConnection))")
        #endif
        sessionManager.clear(preserveCoachConnection: preserveCoachConnection)
        if testResultItem == nil { currentSessionStore.clear() }
    }

    private func handleScenePhaseChange(old: ScenePhase, new: ScenePhase) {
        if new == .background {
            if mode == .solo {
                cancelStimulusAfterBeepWork()
                stopSoloAutoloop()
                if soloWallCalibration.isCalibrating {
                    soloWallCalibration.cancelPendingBeeps()
                }
            }
            engine.applicationDidEnterBackground()
        } else if new == .active {
            engine.synchronizeTimersAfterEnteringForeground()
            tryStartSoloAutoloop()
        }
    }

    /// iOS Home / app switcher: soft-suspend relay only (keep join code / pairing).
    private func scheduleTwoMinutePartnerSuspendForBackgroundNotification() {
        guard mode.requiresPhoneDisplayRelay else { return }
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "TwoMinutePartnerSuspend") {
            if backgroundTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskId)
                backgroundTaskId = .invalid
            }
        }
        TrainingPartnerConnectionCoordinator.shared.suspendPartnerSessionForBackground()
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
        }
    }

    private func handleConnectedPeerChange(old: String?, name: String?) {
        guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .multipeer, name != nil else { return }
        sessionManager.setConnected(true)
        let flag = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
        connectionManager.sendDisplaySessionInfo(hasCompletedInitialTest: flag)
    }

    @ViewBuilder
    private func resultsCoverRouteView(_ route: AppRoute, pathHolder: ResultsCoverPathHolder) -> some View {
        switch route {
        case .awayFromPressureRoleSelection:
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .awayFromPressureTrainingModeSelection:
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .awayFromPressureSetup(let routeMode):
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: routeMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .dribbleOrPassRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassSetup(let routeMode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: routeMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingSetup(let routeMode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: routeMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPass(let routeMode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: routeMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassing(let routeMode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: routeMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .awayFromPressure(let routeMode):
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: routeMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .twoMinuteTest(let routeMode):
            TwoMinuteCriticalScanSessionView(config: TwoMinuteTestConfig.baseline, mode: routeMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
        default:
            EmptyView()
        }
    }

    private func onTwoMinuteSoloWallCalibrationFinished(_: Double) {
        hasCompletedPassTempoCalibration = true
        justCompletedCalibrationThisSession = true
        showCalibrationChoicePrompt = false
        showPassTempoCalibration = false
        tryPresentSessionStartCue()
        startSoloLoop()
    }

    private func handleWallSoloTrigger() {
        if SoloWallCalibrationInput.handleIfSoloCalibrating(
            mode: mode,
            controller: soloWallCalibration,
            soundEnabled: settingsViewModel.soundEnabled,
            activateAudio: { activateAudioSession() },
            preloadBeep: { preloadBeepAssetsForInstantReveal() },
            onCompletedThreePass: onTwoMinuteSoloWallCalibrationFinished
        ) { return }
        guard !isSoloDrillInputFrozen else { return }
        switch engine.phase {
        case .waitingForNextRep:
            soloActionIdleCue.onUserTapToStart()
            repController.completeRepCycleEnd()
            guard repController.acceptIncomingNextRep() else { return }
            engine.onNextRep(repIndex: nextRepIndex)
        case .beepedAwaitingPass(let r, _):
            guard twoMTAllowsPassTrigger(repIndex: r) else { return }
            guard !repController.hasLoggedTap else { return }
            repController.registerTap()
            twoMinuteEnginePassTrigger(repIndex: r, passTimestamp: Date())
        default:
            break
        }
    }

    private var showExitLogButtons: Bool {
        guard !mode.requiresPhoneDisplayRelay else { return false }
        if case .awaitingExitLog = engine.phase { return true }
        if case .ballVisible = engine.phase { return true }
        return false
    }

    private var repIndexForExit: Int? {
        switch engine.phase {
        case .awaitingExitLog(let ri, _), .ballVisible(let ri, _, _): return ri
        default: return nil
        }
    }

    private func twoMinuteExitLogOverlay(repIndex: Int) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Button { logExit(repIndex: repIndex, gate: .up) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 56)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                HStack(spacing: 16) {
                    Button { logExit(repIndex: repIndex, gate: .left) } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 70, height: 56)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button { logExit(repIndex: repIndex, gate: .down) } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 70, height: 56)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button { logExit(repIndex: repIndex, gate: .right) } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 70, height: 56)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 8)
            Spacer().frame(height: 80)
        }
        .padding(.bottom, 32)
    }

    private func logExit(repIndex: Int, gate: Gate) {
        guard twoMTAllowsExitLogged(repIndex: repIndex) else { return }
        guard !repController.hasLoggedSwipe else { return }
        #if DEBUG
        let soloExit = Date()
        DecisionSpeedDebugLog.logSoloDisplayExitTrigger(activity: .twoMinuteTest, repIndex: repIndex, gate: gate, displayWallExitTS: soloExit)
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: soloExit) != nil, let log = engine.repLogs.last {
            repController.registerSwipe()
            syncRepController(with: engine.phase)
            saveDecisionForRep(log: log)
        }
        #else
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let log = engine.repLogs.last {
            repController.registerSwipe()
            syncRepController(with: engine.phase)
            saveDecisionForRep(log: log)
        }
        #endif
        nextRepIndex = repIndex + 1
    }

    private func syncRepController(with phase: CriticalScanPhase) {
        switch phase {
        case .waitingForNextRep:
            repController.completeRepCycleEnd()
        case .armedScanning:
            repController.startRep()
        case .beepedAwaitingPass:
            // Solo: decision window opens via SoloRepTimingScheduler in `playBeep()`. Partner: at beep.
            break
        case .ballVisible:
            break
        case .awaitingExitLog:
            // Partner: window opened in `playBeep()`; solo: after the unified post-beep delay in `playBeep()`.
            break
        case .complete:
            repController.completeRepCycleEnd()
        }
        if mode.requiresPhoneDisplayRelay, case .waitingForNextRep = phase {
            flushPendingPartnerCoachNextRepIfNeeded()
        }
    }

    private func saveDecisionForRep(log: RepLog) {
        recordSoloLifetimeRepIfNeeded(repIndex: log.repIndex)
        guard let sessionId = CurrentSessionStore.shared.sessionId,
              let passTriggeredAt = log.passTriggeredAt else { return }
        if mode.requiresPhoneDisplayRelay, log.repIndex < 3 {
            let observed = max(0.01, log.exitLoggedAt.timeIntervalSince(passTriggeredAt))
            let updated = PartnerPassTempoCalibrationStore.updateRollingAverageTravelTime(
                observedSeconds: observed,
                trainingMode: .partner
            )
            TrainingPartnerConnectionCoordinator.shared.markSessionCalibrationResolved(
                averageTravelTimeSeconds: updated,
                trainingMode: .partner
            )
        }
        let sec = log.exitLoggedAt.timeIntervalSince(passTriggeredAt)
        let reactionTimeMs = Int(sec * 1000)
        guard reactionTimeMs <= SupabaseDecisionService.maxReactionTimeMs else { return }
        let decision = Decision(
            sessionId: sessionId,
            playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id,
            activityName: ActivityKind.twoMinuteTest.rawValue,
            stimulusType: "ball",
            decisionDirection: log.exitedGate.rawValue,
            reactionTimeMs: reactionTimeMs,
            correct: log.correct,
            createdAt: log.exitLoggedAt
        )
        SupabaseDecisionService.shared.saveDecision(decision)
    }

    private func recordSoloLifetimeRepIfNeeded(repIndex: Int) {
        guard mode == .solo else { return }
        guard soloLifetimeRecordedRepIndices.insert(repIndex).inserted else { return }
        if SoloTimeBasedSession.isActive {
            SoloTimeBasedSession.recordRepCompleted()
        }
        soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.recordRep(for: .twoMinuteTest)
    }

    private var soloFreeModeEndAction: (() -> Void)? {
        guard mode == .solo, SoloTimeBasedSession.config == .free else { return nil }
        return { userInitiatedEndSoloSession() }
    }

    private func onSoloCalibrationReadyIfNeeded() {
        SoloTimeBasedDisplaySessionSupport.onSoloCalibrationReady(
            mode: mode,
            hasCompletedCalibration: hasCompletedPassTempoCalibration,
            isCalibrating: soloWallCalibration.isCalibrating,
            timer: soloSessionTimer,
            tryAutoloop: { tryStartSoloAutoloop() }
        )
    }

    private func captureSoloSessionCompletionMetrics() {
        soloTimedCompleteElapsed = soloSessionTimer.elapsedSeconds()
        soloTimedCompleteReps = SoloTimeBasedDisplaySessionSupport.overlayRepCount(
            engineLoggedRepCount: engine.repLogs.count
        )
    }

    private func freezeSoloSessionForCompletion() {
        isSoloRunning = false
        stopSoloAutoloop()
        cancelStimulusAfterBeepWork()
        soloWallCalibration.cancelPendingBeeps()
        soloSessionTimer.stop()
        captureSoloSessionCompletionMetrics()
    }

    private func userInitiatedEndSoloSession() {
        guard mode == .solo, SoloTimeBasedSession.isActive, !showSoloTimedComplete, !isSoloSessionEnding else { return }
        SoloSessionEndTransition.beginUserEnd(
            setEnding: { isSoloSessionEnding = true },
            freeze: { freezeSoloSessionForCompletion() },
            presentOverlay: { showSoloTimedComplete = true },
            clearEnding: { isSoloSessionEnding = false }
        )
    }

    private func finishSoloTimeBasedSession() {
        guard mode == .solo, SoloTimeBasedSession.isActive, !showSoloTimedComplete else { return }
        freezeSoloSessionForCompletion()
        showSoloTimedComplete = true
    }

    /// Same layout as Dribble or Pass: center "X" marker, no players. Ball at one of four slots when visible.
    private var dribbleOrPassLayout: some View {
        GeometryReader { geo in
            let downshift = PartnerDisplayLayout.drillFocalCenterYOffset
            let ballSide = TwoMinuteSlotPositions.ballSideLength(in: geo.size, safeAreaInsets: geo.safeAreaInsets)
            let positions = TwoMinuteSlotPositions.positions(
                in: geo.size,
                safeAreaInsets: geo.safeAreaInsets,
                ballSideLength: ballSide,
                focalContentDownshift: downshift
            )
            let center = TwoMinuteSlotPositions.centerPosition(
                in: geo.size,
                safeAreaInsets: geo.safeAreaInsets,
                ballSideLength: ballSide,
                focalContentDownshift: downshift
            )

            ZStack {
                // Center marker + optional session-start cue stacked above (same focal center as ball slots).
                VStack(spacing: ActivitySessionStartCueView.spacingAboveCenterMarker) {
                    if let cueContent = sessionStartCueContent {
                        ActivitySessionStartCueView(
                            content: cueContent,
                            inlineVisualSideLength: ActivitySessionStartCueView.inlineVisualSideLength(relativeTo: ballSide)
                        ) {
                            onSessionStartCueFinished()
                        }
                        .frame(maxWidth: max(0, geo.size.width - 64))
                        .background(
                            GeometryReader { cueGeo in
                                Color.clear.preference(
                                    key: SessionStartCueHeightPreferenceKey.self,
                                    value: cueGeo.size.height
                                )
                            }
                        )
                    }
                    SoloActionCenterMarkerView(
                        focusPulseTrigger: soloActionIdleCue.focusPulseTrigger,
                        isSessionEnding: isSoloSessionEnding
                    )
                }
                .position(
                    x: center.x,
                    y: center.y - sessionStartCueStackYOffset
                )
                .zIndex(55)

                // Soccer ball: pre-mounted from scan/beep with opacity 0; PASS flips opacity (partner instant reveal).
                if let ctx = twoMinutePreparedBallContext,
                   let pt = positions[ctx.ballGate] {
                    Image("SoccerBall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: ballSide, height: ballSide)
                        .shadow(radius: 4)
                        .opacity(twoMinuteBallRevealOpacity)
                        .animation(nil, value: engine.phase)
                        .position(x: pt.x, y: pt.y)
                        .zIndex(1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: downshift)
            .onPreferenceChange(SessionStartCueHeightPreferenceKey.self) { sessionStartCueHeight = $0 }
        }
        .soloSessionEndingDim(isActive: isSoloSessionEnding)
        // Full-screen geometry + `safeAreaInsets` so slot math matches the physical display (esp. landscape iPad).
        .ignoresSafeArea()
    }

    /// Partner “waiting for coach” overlay: show until the coach is paired (Multipeer peer or relay `peer_joined`).
    private var shouldShowWaitingForCoachOverlay: Bool {
        guard mode.requiresPhoneDisplayRelay else { return false }
        if TrainingPartnerConnectionCoordinator.shared.isMidSessionPartnerDisconnect { return false }
        if sessionTransportMode == .relayWebSocket {
            return !partnerRelaySession.isCoachPaired
        }
        return !sessionManager.isConnected
    }

    /// Partner: 3–2–1–Go only after coach is connected (same signal as waiting overlay). Solo: always ready.
    private var partnerReadyForCountdown: Bool {
        mode.requiresPhoneDisplayRelay ? coachConnectedForCalibration : hasCompletedPassTempoCalibration
    }

    private var sessionStartCueDrillIsVisible: Bool {
        if mode == .solo, soloWallCalibration.isCalibrating { return false }
        if blockCoachDrillDuringSessionCountdown { return false }
        return true
    }

    /// Shift the cue+marker stack up so the X stays on the drill focal center when the cue is visible.
    private var sessionStartCueStackYOffset: CGFloat {
        guard sessionStartCueContent != nil else { return 0 }
        return (sessionStartCueHeight + ActivitySessionStartCueView.spacingAboveCenterMarker) / 2
    }

    private func tryPresentSessionStartCue() {
        guard !hasPresentedSessionStartCue else { return }
        guard let content = ActivityKind.twoMinuteTest.sessionStartCue else { return }
        guard sessionStartCueDrillIsVisible else { return }
        hasPresentedSessionStartCue = true
        sessionStartCueContent = content
    }

    /// Cue finished: clear UI and restart autoloop if a pre-cue start left the runner stuck without firing a rep.
    private func onSessionStartCueFinished() {
        sessionStartCueContent = nil
        if soloLoopRunner.isRunning {
            stopSoloAutoloop()
            if mode == .solo, effectiveUsesAutoLoop {
                isSoloRunning = true
            }
        }
        tryStartSoloAutoloop()
    }

    private var coachConnectedForCalibration: Bool {
        guard mode.requiresPhoneDisplayRelay else { return true }
        if sessionTransportMode == .relayWebSocket {
            return partnerRelaySession.isCoachPaired
        }
        return sessionManager.isConnected
    }

    private func completePartnerCalibration(averageTravelTime: Double?) {
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(averageTravelTime)
        hasCompletedPassTempoCalibration = true
        showPassTempoCalibration = false
    }

    private func configureCalibrationStartFlowForCurrentMode() {
        guard !mode.requiresPhoneDisplayRelay else { return }
        if mode == .solo, soloWallCalibration.isCalibrating { return }
        if !PBASessionFlowPolicy.shouldPromptCalibration(for: mode),
           let calibrated = SoloWallCalibrationController.effectiveSoloWallReturnTimeSeconds() {
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(calibrated)
            showCalibrationChoicePrompt = false
            showPassTempoCalibration = false
            if mode == .solo {
                onSoloCalibrationReadyIfNeeded()
            } else {
                tryStartSoloAutoloop()
            }
        } else {
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nil)
            showCalibrationChoicePrompt = true
            showPassTempoCalibration = false
        }
    }

    private func beginConnectedToCalibrationTransitionIfNeeded() {
        guard coachConnectedForCalibration,
              !hasCompletedPassTempoCalibration,
              !hasStartedConnectedToCalibrationTransition else { return }
        hasStartedConnectedToCalibrationTransition = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showConnectedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PartnerCalibrationTransition.connectedConfirmationDuration) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showConnectedConfirmation = false
            }
            guard coachConnectedForCalibration else {
                // Connection dropped during transition; do not enter calibration waiting.
                hasStartedConnectedToCalibrationTransition = false
                showPassTempoCalibration = false
                return
            }
            let coordinator = TrainingPartnerConnectionCoordinator.shared
            let shouldPrompt = PBASessionFlowPolicy.shouldPromptCalibration(for: .partner) && !coordinator.sessionCalibrationResolved
            if shouldPrompt {
                showPassTempoCalibration = true
            } else {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(
                    coordinator.sessionCalibrationAverageTravelTime ?? PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds()
                )
                hasCompletedPassTempoCalibration = true
                showPassTempoCalibration = false
            }
        }
    }

    private var waitingForCoachOverlay: some View {
        Group {
            if shouldShowWaitingForCoachOverlay {
                if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                    PartnerRelayDisplayWaitingWithSessionErrorOverlay(
                        joinCode: partnerRelaySession.joinCode,
                        activityTitle: ActivityKind.twoMinuteTest.displayName,
                        isDatabaseSessionCreating: sessionManager.isCreating,
                        databaseSessionError: sessionManager.creationError,
                        onRetryDatabaseSession: {
                            Task {
                                await sessionManager.startSession(
                                    activity: .twoMinuteTest,
                                    blockSize: blockTotalReps,
                                    playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
                                )
                            }
                        }
                    )
                } else if sessionManager.isCreating {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Creating session…")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 220)
                    .allowsHitTesting(false)
                    Spacer()
                } else if let error = sessionManager.creationError {
                    VStack(spacing: 16) {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await sessionManager.startSession(
                                    activity: .twoMinuteTest,
                                    blockSize: blockTotalReps,
                                    playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 220)
                    Spacer()
                } else {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text("Waiting for Coach Remote…")
                                .font(.title3.weight(.medium))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Tap Connect to Display on the coach device, then select this device.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .padding(.top, 200)
                    .allowsHitTesting(false)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(waitingCoachOverlayAllowsHitTesting)
    }

    /// Relay error overlay needs Retry taps; other waiting states pass touches through.
    private var waitingCoachOverlayAllowsHitTesting: Bool {
        return false
    }

    private var statusOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
    }

    /// Rep count and timer visible only after connection event (State 2). Hidden in State 1 (waiting for pairing).
    private var repCountOverlay: some View {
        let showLink = mode.requiresPhoneDisplayRelay
        let showRep = !mode.requiresPhoneDisplayRelay || sessionManager.isConnected
        return Group {
            PartnerDisplaySessionTopChrome(
                showCoachConnectionLine: showLink,
                showRepAndTempo: showRep,
                repLine: repCountText,
                tempoLine: "Tempo: \(config.difficulty.passTempo.displayName)"
            )
        }
    }

    private var repCountText: String {
        let rep: String
        if mode.requiresPhoneDisplayRelay, !sessionManager.isConnected {
            rep = "—"
        } else {
            switch engine.phase {
            case .waitingForNextRep: rep = "\(nextRepIndex + 1)"
            case .complete: rep = "\(blockTotalReps)"
            case .armedScanning(let r, _, _), .beepedAwaitingPass(let r, _), .ballVisible(let r, _, _), .awaitingExitLog(let r, _):
                rep = "\(r + 1)"
            }
        }
        return "Rep \(rep) of \(blockTotalReps)"
    }

    private func activateAudioSession() {
        PBABeepSoundManager.shared.activateSessionIfNeeded()
    }

    private func preloadBeepAssetsForInstantReveal() {
        PBABeepSoundManager.shared.preloadCurrent()
    }

    /// Same slot as visible ball, from first scan frame through exit log so Image asset decodes before PASS.
    private var twoMinutePreparedBallContext: (repIndex: Int, ballGate: Gate)? {
        switch engine.phase {
        case .armedScanning(let r, let g, _), .beepedAwaitingPass(let r, let g), .ballVisible(let r, let g, _), .awaitingExitLog(let r, let g):
            return (r, g)
        default:
            return nil
        }
    }

    private var twoMinuteBallRevealOpacity: Double {
        if case .ballVisible = engine.phase { return 1 }
        return 0
    }

    private func playBeep() {
        if mode == .solo {
            guard !soloWallCalibration.isCalibrating else { return }
            // Timing anchor: `soloRepBeepWallTime` and scheduler delays count from the beep (after unified scan→beep).
            cancelStimulusAfterBeepWork()
            let beepWall = Date()
            soloRepBeepWallTime = beepWall
            if case .beepedAwaitingPass(let r, _) = engine.phase {
                PBAFlowDebugLog.beep(repId: r, timestamp: beepWall)
            }
            sendBeepArmed(repIndex: engine.currentRepIndex)
            let timing = SoloRepTiming.fromCalibration(soloWallCalibration.calibratedReturnTime)
            let repAtBeep = engine.currentRepIndex
            soloRepTimingScheduler.scheduleRep(
                timing: timing,
                repIndex: repAtBeep,
                onDecisionOpen: { rep in
                    guard case .beepedAwaitingPass(let r, _) = self.engine.phase, r == rep else { return }
                    self.repController.openDecisionWindow()
                },
                onSyntheticPass: { rep in
                    guard case .beepedAwaitingPass(let r, _) = self.engine.phase, r == rep else { return }
                    guard self.twoMTAllowsPassTrigger(repIndex: rep) else { return }
                    guard !self.repController.hasLoggedTap else { return }
                    self.repController.registerTap()
                    self.twoMinuteEnginePassTrigger(repIndex: rep, passTimestamp: Date())
                }
            )
            DispatchQueue.main.async {
                self.activateAudioSession()
                self.preloadBeepAssetsForInstantReveal()
                PBABeepSoundManager.shared.play(soundEnabled: self.settingsViewModel.soundEnabled)
            }
            return
        } else {
            // Partner / relay: pre-change 2MT behavior (immediate decision window; no post-beep delay or `stimulusAfterBeepWorkItem`).
            // Arm coach PASS acceptance on the same run loop as the beep (and again with audio) so taps are not dropped vs. `DispatchQueue.main.async` sound scheduling.
            repController.openDecisionWindow()
            if case .beepedAwaitingPass(let r, _) = engine.phase {
                PBAFlowDebugLog.beep(repId: r, timestamp: Date())
            }
            // Tell the coach the iPad just beeped so its PASS button can arm.
            // See DribbleOrPassDisplaySessionView.playBeep for full rationale.
            sendBeepArmed(repIndex: engine.currentRepIndex)
            DispatchQueue.main.async {
                self.repController.openDecisionWindow()
                self.activateAudioSession()
                self.preloadBeepAssetsForInstantReveal()
                PBABeepSoundManager.shared.play(soundEnabled: self.settingsViewModel.soundEnabled)
            }
        }
    }

    private func sendBeepArmed(repIndex: Int) {
        let message = TwoMinuteMessage.beepArmed(repIndex: repIndex, timestamp: Date())
        if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
            #if DEBUG
            print("[2MT Display] send beepArmed repIndex=\(repIndex) (relay)")
            #endif
            partnerRelaySession.sendTwoMinuteMessage(message)
            return
        }
        connectionManager.sendTwoMinuteMessage(message)
    }

    /// Pops back to Progress (root of 2-min flow) after user dismisses results cover.
    private func popToRootFromSession() {
        let levels = 4 // Session -> GetReady -> Setup -> RoleSelection -> Progress
        for i in 0..<levels {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 * Double(i)) {
                dismiss()
            }
        }
    }

    private func sendSessionEndedIfNeeded() {
        guard !hasSentSessionEnded else { return }
        hasSentSessionEnded = true
        if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
            partnerRelaySession.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
            return
        }
        connectionManager.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
    }

    private func sendRepStartedAck(repIndex: Int) {
        let post: (TwoMinuteMessage) -> Void = { msg in
            if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                partnerRelaySession.sendTwoMinuteMessage(msg)
            } else {
                connectionManager.sendTwoMinuteMessage(msg)
            }
        }
        post(.repStarted(repIndex: repIndex, timestamp: Date()))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            post(.repStarted(repIndex: repIndex, timestamp: Date()))
        }
    }

}
