//
//  AwayFromPressureDisplaySessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Display: same layout as 2-min (center X, four slots). Danger zone at one edge on PASS trigger.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine

struct AwayFromPressureDisplaySessionView: View {
    let config: AwayFromPressureConfig
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @StateObject private var engine: AwayFromPressureEngine
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigateToBlockSummary = false
    @State private var showSoloSummary = false
    @State private var blockSummaryCalibratedTravelSeconds: Double?
    @State private var blockSummaryShowTimingAdaptationFeedback = false
    @State private var nextRepIndex = 0
    @State private var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    @State private var hasSentSessionEnded = false
    @State private var hasCompletedPassTempoCalibration = false
    @State private var showPassTempoCalibration = false
    @State private var partnerCalibration = PartnerPassTempoCalibrationTracker()
    @State private var showConnectedConfirmation = false
    @State private var hasStartedConnectedToCalibrationTransition = false
    /// True while ``SessionCountdownModifier`` shows 3–2–1–Go; coach drill messages must not advance the engine until the drill is visible.
    @State private var blockCoachDrillDuringSessionCountdown = false
    /// Latest coach `nextRep` deferred until countdown ends or engine reaches ``AwayFromPressurePhase/waitingForNextRep``.
    @State private var pendingNextRepIndex: Int?
    @State private var isTearingDownForNewSession: Bool = false
    @State private var partnerCoachRepGate = PartnerCoachRepSequenceGate()
    @StateObject private var repController = RepStateController()
    @StateObject private var soloWallCalibration = SoloWallCalibrationController()
    @ObservedObject private var partnerRelaySession: PartnerRelayDisplaySession
    @StateObject private var soloLoopRunner = SoloLoopRunner()
    @State private var soloRepTimingScheduler = SoloRepTimingScheduler()
    /// Solo: wall time when the current rep's beep fired; anchors pass tolerance window.
    @State private var soloRepBeepWallTime: Date?
    @State private var soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.totalReps(for: .awayFromPressure)
    @State private var soloLifetimeRecordedRepIndices = Set<String>()
    @StateObject private var soloSessionTimer = SoloSessionTimerController()
    @StateObject private var soloActionIdleCue = SoloActionIdleCueState()
    @State private var showSoloTimedComplete = false
    @State private var isSoloSessionEnding = false
    @State private var soloTimedCompleteElapsed: TimeInterval = 0
    @State private var soloTimedCompleteReps = 0
    @State private var soloWallBootResolved = false
    @State private var sessionStartCueContent: ActivitySessionStartCueContent?
    @State private var hasPresentedSessionStartCue = false
    @State private var sessionStartCueHeight: CGFloat = 0
    @State private var isSoloRunning = false

    private var showsDrillFocalLayout: Bool {
        SoloWallCalibrationDisplayPolicy.showsDrillFocalLayout(
            mode: mode,
            isCalibrating: soloWallCalibration.isCalibrating,
            bootResolved: soloWallBootResolved
        )
    }

    private var sessionTransportMode: SessionTransportMode {
        PartnerTransportPolicy.transportMode(for: .awayFromPressure, trainingMode: mode)
    }

    init(config: AwayFromPressureConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        let repCount = TimedSessionEnginePolicy.enginePlanBlockSize(
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId,
            soloFallback: TimedSessionEnginePolicy.timedSessionBlockSize,
            mode: mode
        )
        let plan = AwayFromPressureRepPlanner.generatePlan(forBlockSize: repCount)
        _engine = StateObject(wrappedValue: AwayFromPressureEngine(config: config, trainingMode: mode, plan: plan))
        _partnerRelaySession = ObservedObject(wrappedValue: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession)
    }

    private var enginePlanRepCount: Int {
        TimedSessionEnginePolicy.enginePlanBlockSize(
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId,
            soloFallback: TimedSessionEnginePolicy.timedSessionBlockSize,
            mode: mode
        )
    }

    private var blockTotalReps: Int { enginePlanRepCount }

    private var effectiveUsesAutoLoop: Bool {
        SoloTimeBasedDisplaySessionSupport.effectiveUsesAutoLoop(mode: mode)
    }

    private var isSoloDrillInputFrozen: Bool {
        SoloTimeBasedDisplaySessionSupport.shouldBlockSoloDrillInput(
            isEnding: isSoloSessionEnding,
            showComplete: showSoloTimedComplete
        )
    }

    private var showsBetweenRepPlayerText: Bool {
        DisplaySessionPlayerTextPolicy.showsBetweenRepPlayerText(for: engine.phase)
    }

    var body: some View {
        awayFromPressureRootView
    }

    private var awayFromPressureRootView: some View {
        awayFromPressureLifecycleModifiers
            .sessionCountdown(
                waitForPartnerReady: mode.requiresPhoneDisplayRelay,
                partnerReady: partnerReadyForCountdown,
                suppressCoachMessagesDuringCountdown: $blockCoachDrillDuringSessionCountdown,
                isEnabled: TimedSessionDisplayIntegration.showsPartnerSessionStartCountdown(
                    mode: mode,
                    effectiveUsesAutoLoop: effectiveUsesAutoLoop
                )
            )
            .onReceive(NotificationCenter.default.publisher(for: .relayForegroundReconnectCompleted)) { _ in
                handleRelayForegroundReconnectCompleted()
            }
            .onChange(of: blockCoachDrillDuringSessionCountdown) { old, new in
                handleBlockCoachDrillCountdownChange(old: old, new: new)
            }
    }

    private var passTempoCalibrationPresented: Binding<Bool> {
        Binding(
            get: { showPassTempoCalibration && !mode.requiresPhoneDisplayRelay },
            set: { showPassTempoCalibration = $0 }
        )
    }

    private var awayFromPressureSessionStack: some View {
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
                    .opacity(statusOverlayOpacity)
            }
            if TimedSessionDisplayIntegration.showsBlockRepProgressOverlay(mode: mode), showsBetweenRepPlayerText {
                repCountOverlay
            }
            SoloWallCalibrationGetReadyOverlay(mode: mode, calibration: soloWallCalibration)
            if mode == .partner, showExitLogButtons {
                exitLogOverlay
            }
            waitingForCoachRelayOverlay
            if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
            }
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(120)
            if mode == .solo, soloActionIdleCue.showTapHint, !soloWallCalibration.isCalibrating {
                SoloActionTapHintView()
                    .zIndex(50)
                    .transition(.opacity)
            }
        }
    }

    private var awayFromPressureSessionContentWithCover: some View {
        SessionScreenLayout {
            awayFromPressureSessionStack
        }
            .contentShape(Rectangle())
            .onTapGesture(perform: handleAwayFromPressureTap)
            .soloSessionTimerOverlay(
                isVisible: TimedSessionDisplayIntegration.showsSessionTimerOverlay(
                    mode: mode,
                    isCalibrating: soloWallCalibration.isCalibrating,
                    localTimer: soloSessionTimer
                ),
                text: TimedSessionDisplayIntegration.timerDisplayText(local: soloSessionTimer),
                onFreePlayEnd: soloFreeModeEndAction
            )
            .navigationDestination(isPresented: $navigateToBlockSummary) {
                awayFromPressureBlockSummaryDestination
            }
            .soloSessionCompleteOverlay(
                isPresented: showSoloTimedComplete && !TimedSessionDisplayIntegration.shouldDeferCompletionOverlay,
                elapsedSeconds: soloTimedCompleteElapsed,
                repCount: soloTimedCompleteReps,
                onDone: handleSoloSessionCompleteDismiss
            )
            .fullScreenCover(isPresented: passTempoCalibrationPresented) {
                awayFromPressurePassTempoCalibrationCover
            }
            .soloTapToStartGate(
                mode: mode,
                hasCompletedCalibration: hasCompletedPassTempoCalibration,
                isCalibrating: soloWallCalibration.isCalibrating,
                sessionStartCueActive: sessionStartCueContent != nil,
                localTimer: soloSessionTimer,
                onUserStart: {
                    isSoloRunning = true
                    startSoloLoop()
                }
            )
    }

    @ViewBuilder
    private var awayFromPressureBlockSummaryDestination: some View {
        AwayFromPressureBlockSummaryView(
            logs: engine.repLogs,
            config: config,
            trainingMode: mode,
            summaryCalibratedTravelSeconds: blockSummaryCalibratedTravelSeconds,
            showTimingAdaptationFeedback: blockSummaryShowTimingAdaptationFeedback,
            onRunItBack: runItBackFromSummary,
            settingsViewModel: settingsViewModel,
            profileManager: profileManager
        )
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
    }

    private var awayFromPressurePassTempoCalibrationCover: some View {
        PassTempoCalibrationScreen { calibrated in
            PartnerPassTempoCalibrationStore.save(averageTravelTimeSeconds: calibrated, trainingMode: mode)
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(calibrated)
            hasCompletedPassTempoCalibration = true
            showPassTempoCalibration = false
        }
        .interactiveDismissDisabled()
    }

    private var awayFromPressureEngineSyncModifiers: some View {
        awayFromPressureSessionContentWithCover
            .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main), perform: handleAwayFromPressureCoachRelayMessage)
            .onReceive(NotificationCenter.default.publisher(for: .partnerSoftReconnectRepRestart).receive(on: RunLoop.main)) { _ in
                guard !TrainingPartnerConnectionCoordinator.shared.isPartnerSoftReconnectRepRestartSuppressed else { return }
                applyPartnerSoftReconnectAfterTransportRestoreAwayFromPressure()
            }
            .onReceive(NotificationCenter.default.publisher(for: .partnerDisplayWillStartNewSessionFromDisconnect).receive(on: RunLoop.main)) { _ in
                applyPartnerStartNewSessionLocalTeardownAwayFromPressure()
            }
            .onChange(of: engine.currentRepIndex) { _, newValue in
                guard mode.requiresPhoneDisplayRelay else { return }
                TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                    newValue,
                    activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
                )
            }
            .onChange(of: engine.phase) { oldPhase, newPhase in
                handleAwayFromPressurePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
            }
            .onChange(of: hasCompletedPassTempoCalibration) { _, completed in
                guard completed else { return }
                tryPresentSessionStartCue()
                onSoloCalibrationReadyIfNeeded()
                if mode != .solo {
                    tryStartSoloAutoloop()
                }
                notifyPartnerTimedDrillSurfaceReadyIfNeeded()
            }
            .onChange(of: soloWallCalibration.isCalibrating) { _, isCalibrating in
                guard !isCalibrating else { return }
                tryPresentSessionStartCue()
                onSoloCalibrationReadyIfNeeded()
                tryStartSoloAutoloop()
            }
    }

    /// Split from `body` so the SwiftUI type checker can finish in reasonable time.
    private var awayFromPressureLifecycleModifiers: some View {
        awayFromPressureEngineSyncModifiers
            .onAppear(perform: handleAwayFromPressureOnAppear)
            .onDisappear(perform: handleAwayFromPressureOnDisappear)
            .onTimedSessionContainerEnd { userInitiatedEndSoloSession() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                      type == .ended else { return }
                activateAudioSession()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    pauseSessionForBackground()
                } else if newPhase == .active {
                    SessionStartCueRepGate.noteScenePhase(newPhase)
                    engine.synchronizeTimersAfterEnteringForeground()
                    if SessionStartCueRepGate.consumeDidEnterBackground() {
                        resumeSessionIfNeeded()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                schedulePartnerSuspendForBackgroundNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification)) { _ in
                schedulePartnerSuspendForBackgroundNotification()
            }
            .onChange(of: connectionManager.connectedPeerName) { _, name in
                guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .multipeer, name != nil else { return }
                let flag = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
                connectionManager.sendDisplaySessionInfo(hasCompletedInitialTest: flag)
            }
            .onChange(of: coachConnectedForCalibration) { _, connected in
                guard mode.requiresPhoneDisplayRelay else { return }
                if connected {
                    beginConnectedToCalibrationTransitionIfNeeded()
                    notifyPartnerTimedDrillSurfaceReadyIfNeeded()
                } else {
                    showConnectedConfirmation = false
                    hasStartedConnectedToCalibrationTransition = false
                    showPassTempoCalibration = false
                }
            }
            .preferredColorScheme(.dark)
            #if DEBUG
            .onChange(of: partnerRelaySession.joinCode) { _, newCode in
                guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket, let code = newCode else { return }
                afpRelayDisplayLog("relay session created (HTTP OK)")
                afpRelayDisplayLog("join code assigned code=\(code)")
            }
            #endif
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
    }

    private func handleAwayFromPressureTap() {
        if SoloWallCalibrationInput.handleIfSoloCalibrating(
            mode: mode,
            controller: soloWallCalibration,
            soundEnabled: settingsViewModel.soundEnabled,
            activateAudio: { activateAudioSession() },
            preloadBeep: { preloadBeepAssetsForInstantReveal() },
            onCompletedThreePass: onSoloWallCalibrationFinished
        ) { return }
        guard !isSoloDrillInputFrozen else { return }
        guard !SoloSessionUserStartGate.shouldBlockSoloRepFlow(
            mode: mode,
            hasCompletedCalibration: hasCompletedPassTempoCalibration,
            isCalibrating: soloWallCalibration.isCalibrating
        ) else { return }
        if mode == .solo, !effectiveUsesAutoLoop {
            handleWallSoloTrigger()
        }
    }

    private func handleSoloSessionCompleteDismiss() {
        FirstSessionOnboardingStore.completeSoloTimedFeedbackDismiss(
            clearSession: { SoloTimeBasedSession.clear() },
            dismissOverlay: { showSoloTimedComplete = false },
            popToRoot: { router.popToRoot() }
        )
    }

    private func handleRelayForegroundReconnectCompleted() {
        guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket else { return }
        alignEngineRepWithCoordinatorSnapshotAfterRelayForegroundAwayFromPressure()
        engine.synchronizeTimersAfterEnteringForeground()
        PartnerRelayCheckpointDisplaySend.sendIfReady(
            engine: engine,
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId,
            relay: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
        )
    }

    private func handleBlockCoachDrillCountdownChange(old: Bool, new: Bool) {
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
        if SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) {
            flushPendingCoachNextRepAfterCountdown()
        }
        notifyPartnerTimedDrillSurfaceReadyIfNeeded()
    }

    private func handleAwayFromPressurePhaseChange(oldPhase: AwayFromPressurePhase, newPhase: AwayFromPressurePhase) {
        recordTimedRepAtEngineBoundary(oldPhase: oldPhase, newPhase: newPhase)
        if case .blockComplete = newPhase {
            stopSoloAutoloop()
            PlayerFirstRunGuidanceStore.markCompletedFirstRun(activityId: ActivityKind.awayFromPressure.sessionActivityActivityId)
            pendingNextRepIndex = nil
            if mode.requiresPhoneDisplayRelay {
                TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                    blockTotalReps,
                    activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
                )
            }
            let calId = ActivityKind.awayFromPressure.sessionActivityActivityId
            let base = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
                ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
            blockSummaryCalibratedTravelSeconds = CurrentSessionStore.shared.calibratedBallTravelSeconds(
                baseNominal: base,
                activityId: calId
            )
            blockSummaryShowTimingAdaptationFeedback =
                abs(CurrentSessionStore.shared.calibrationFactor(for: calId) - 1.0) > 0.001
            DispatchQueue.main.async {
                if TimedSessionDisplayIntegration.continueAfterEnginePlanComplete(
                    restartEngineBlock: {
                        SoloTimeBasedDisplaySessionSupport.resetDisplayRepStateForEngineChunkRestart(
                            mode: self.mode,
                            setNextRepIndex: { self.nextRepIndex = $0 },
                            setPendingNextRepIndex: { self.pendingNextRepIndex = $0 },
                            resetRepController: { self.repController.reset() },
                            resetPartnerCoachRepGate: { self.partnerCoachRepGate.reset() }
                        )
                        self.engine.restartBlockFromBeginning()
                        self.syncRepController(with: self.engine.phase)
                        self.isSoloRunning = true
                    },
                    resumeReps: { self.tryStartSoloAutoloop() }
                ) {
                    return
                }
                guard TimedSessionDisplayIntegration.allowsBlockSummaryNavigation else { return }
                guard !TimedSessionDisplayIntegration.runEngineContinuously else { return }
                if mode == .solo {
                    if SoloTimeBasedSession.isActive {
                        finishSoloTimeBasedSession()
                    } else {
                        showSoloSummary = true
                        FirstSessionOnboardingStore.noteTrainingSessionCompleted(
                            deferLoginUntilFeedbackDismissed: false,
                            repCount: SoloTimeBasedDisplaySessionSupport.overlayRepCount(
                                engineLoggedRepCount: engine.repLogs.count
                            ),
                            elapsedSeconds: soloSessionTimer.elapsedSeconds()
                        )
                        navigateToBlockSummary = true
                    }
                } else {
                    FirstSessionOnboardingStore.noteTrainingSessionCompleted(
                        deferLoginUntilFeedbackDismissed: false,
                        repCount: SoloTimeBasedDisplaySessionSupport.overlayRepCount(
                            engineLoggedRepCount: engine.repLogs.count
                        ),
                        elapsedSeconds: soloSessionTimer.elapsedSeconds()
                    )
                    navigateToBlockSummary = true
                }
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
        let activeTimer = TimedSessionDisplayIntegration.sessionTimer(local: soloSessionTimer)
        if SoloTimeBasedSession.isActive, activeTimer.pendingEndAfterCurrentRep,
           case .waitingForNextRep = newPhase {
            finishSoloTimeBasedSession()
        } else if case .waitingForNextRep = newPhase {
            SoloTimeBasedDisplaySessionSupport.notifyQuickRepAdvanceIfNeeded(mode: mode, soloLoopRunner: soloLoopRunner)
        }
        syncRepController(with: newPhase)
        if case .armedScanning = newPhase {
            preloadBeepAssetsForInstantReveal()
        }
        if case .beepedAwaitingPass = newPhase,
           SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) {
            playBeep()
        }
        if mode == .solo, !mode.requiresPhoneDisplayRelay,
           case .waitingForNextRep = newPhase,
           case .markerVisible(let oldR, let oldP, _) = oldPhase {
            DispatchQueue.main.async {
                self.applySoloAwayFromPressureAutoExitIfNeeded(repIndex: oldR, pressureGate: oldP)
            }
        }
    }

    private func handleAwayFromPressureOnAppear() {
        SessionStartCueRepGate.onDrillSurfaceAppeared()
        if mode == .solo {
            soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.totalReps(for: .awayFromPressure)
        }
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        let timedPartnerActivitySwitch = mode.requiresPhoneDisplayRelay
            && TimedSessionDisplayIntegration.shouldSkipPartnerSessionStartCue(mode: mode)
        if timedPartnerActivitySwitch {
            showPassTempoCalibration = false
            let partnerNeedsCalibration = PBASessionFlowPolicy.shouldPromptCalibration(for: .partner)
                && !coordinator.sessionCalibrationResolved
            if partnerNeedsCalibration {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nil)
                hasCompletedPassTempoCalibration = false
                hasStartedConnectedToCalibrationTransition = false
            } else {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(
                    coordinator.sessionCalibrationAverageTravelTime ?? PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds()
                )
                hasCompletedPassTempoCalibration = true
                showConnectedConfirmation = false
                hasStartedConnectedToCalibrationTransition = true
            }
        } else if mode.requiresPhoneDisplayRelay {
            hasCompletedPassTempoCalibration = false
            showPassTempoCalibration = false
            let partnerNeedsCalibration = PBASessionFlowPolicy.shouldPromptCalibration(for: .partner) && !coordinator.sessionCalibrationResolved
            if partnerNeedsCalibration {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nil)
            } else {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(
                    coordinator.sessionCalibrationAverageTravelTime ?? PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds()
                )
                hasCompletedPassTempoCalibration = true
            }
        } else {
            showPassTempoCalibration = false
            let nominal = config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
            SoloSessionStart.applySoloWallCalibrationBoot(
                trainingMode: mode,
                controller: soloWallCalibration,
                nominalWallTravelSeconds: nominal,
                setHasCompletedPassTempoCalibration: { hasCompletedPassTempoCalibration = $0 },
                soundEnabled: settingsViewModel.soundEnabled,
                activateAudio: { activateAudioSession() },
                preloadBeep: { preloadBeepAssetsForInstantReveal() },
                onInlineCalibrationFinished: onSoloWallCalibrationFinished
            )
        }
        partnerCalibration.reset()
        showConnectedConfirmation = false
        if !timedPartnerActivitySwitch {
            hasStartedConnectedToCalibrationTransition = false
        }
        beginConnectedToCalibrationTransitionIfNeeded()
        #if DEBUG
        PartnerPersistDebug.log("AwayFromPressureDisplaySessionView onAppear")
        #endif
        onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        hasSentSessionEnded = false
        if mode.requiresPhoneDisplayRelay {
            TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
            if sessionTransportMode == .multipeer {
                TrainingPartnerConnectionCoordinator.shared.prepareMultipeerDisplayPartner(connectionManager: connectionManager)
            }
        }
        if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
            afpRelayDisplayLog("relay pipeline starting (POST /v1/sessions + WebSocket display)")
            partnerRelaySession.onCoachPairingChanged = { [partnerRelaySession] connected in
                if connected {
                    afpRelayDisplayLog("coach peer_joined")
                } else {
                    let socket = partnerRelaySession.socketConnectionState
                    if socket == .disconnected {
                        afpRelayDisplayLog("coach unpaired (relay socket disconnected)")
                    } else {
                        afpRelayDisplayLog("coach peer_left")
                    }
                }
            }
            Task { await TrainingPartnerConnectionCoordinator.shared.prepareRelayDisplayForActivity() }
        }
        let pid = playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
        wedgeStyle = WedgeDifficultyEngine.currentStyle(playerId: pid)
        activateAudioSession()
        preloadBeepAssetsForInstantReveal()
        AnalyticsManager.shared.track(.trainingSessionStarted, playerId: playerStore.selectedPlayerId)
        registerSupabaseAwayFromPressureBlockSession()
        if mode == .solo, effectiveUsesAutoLoop {
            if SoloSessionUserStartGate.hasConfirmedUserStart,
               hasCompletedPassTempoCalibration,
               !soloWallCalibration.isCalibrating {
                isSoloRunning = true
            } else {
                isSoloRunning = false
            }
        }
        if effectiveUsesAutoLoop {
            tryPresentSessionStartCue()
        }
        if mode == .solo {
            if effectiveUsesAutoLoop {
                syncRepController(with: engine.phase)
                if isSoloRunning {
                    startSoloLoop()
                }
            }
            onSoloCalibrationReadyIfNeeded()
        } else {
            tryStartSoloAutoloop()
        }
        soloWallBootResolved = true
        notifyPartnerTimedDrillSurfaceReadyIfNeeded()
    }

    private func notifyPartnerTimedDrillSurfaceReadyIfNeeded() {
        TimedSessionDisplayIntegration.fastPathPartnerTimedDrillSurfaceIfNeeded(
            mode: mode,
            partnerDrillReady: TimedSessionDisplayIntegration.partnerTimedDrillSurfaceReady(
                mode: mode,
                coachConnectedForCalibration: coachConnectedForCalibration,
                hasCompletedPassTempoCalibration: hasCompletedPassTempoCalibration,
                showPassTempoCalibration: showPassTempoCalibration,
                showConnectedConfirmation: showConnectedConfirmation
            )
        )
    }

    private func handleAwayFromPressureOnDisappear() {
        cancelSoloAfpStimulusAfterBeepWork()
        soloWallCalibration.cancelPendingBeeps()
        stopSoloAutoloop()
        pendingNextRepIndex = nil
        SessionStartCueRepGate.onDrillSurfaceDisappeared()
        #if DEBUG
        PartnerPersistDebug.log("AwayFromPressureDisplaySessionView onDisappear")
        #endif
        // Timed container activity switch reuses the same live session; do not send end/disconnect teardown here.
        if TimedSessionDisplayIntegration.usesSharedSession {
            return
        }
        if mode.requiresPhoneDisplayRelay {
            teardownPartnerTransportWhenSessionSuspends()
        }
    }

    private func handleAwayFromPressureCoachRelayMessage(_ notification: Notification) {
        guard mode.requiresRelay else { return }
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
            print("[DISPLAY] Received startNextBlock activity=awayFromPressure")
            runItBackFromSummary()
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
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                if !partnerRelaySession.isCoachPaired {
                    afpRelayDisplayLog("incoming nextRep repIndex=\(repIndex) while isCoachPaired=false (still applying — relay UI can lag peer_joined)")
                }
                afpRelayDisplayLog("incoming nextRep repIndex=\(repIndex)")
            }
            #endif
            applyPartnerCoachNextRep(repIndex: repIndex)
        case .passTriggered(let repIndex, let timestamp):
            guard afpAllowsPassTrigger(repIndex: repIndex) else { return }
            guard repController.state == .preBeep || repController.state == .decisionWindow else { return }
            guard !repController.hasLoggedTap else { return }
            repController.registerTap()
            TimedSessionDisplayIntegration.recordSessionRepIfNeeded(
                activityId: ActivityKind.awayFromPressure.sessionActivityActivityId,
                repIndex: repIndex,
                recordedRepTokens: &soloLifetimeRecordedRepIndices
            )
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("incoming passTriggered repIndex=\(repIndex)")
            }
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .awayFromPressure, kind: "passTriggered", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            #endif
            afpApplyPassTrigger(repIndex: repIndex, passTimestamp: timestamp)
        case .exitLogged(let repIndex, let gate, let timestamp):
            guard afpAllowsExitLogged(repIndex: repIndex) else { return }
            guard repController.canAcceptSwipe() else { return }
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("incoming exitLogged repIndex=\(repIndex) gate=\(gate)")
            }
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .awayFromPressure, kind: "exitLogged", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .awayFromPressure, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "exitLogged")
            #endif
            if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                repController.registerSwipe()
                syncRepController(with: engine.phase)
                saveDecisionForRep(log: log)
            }
        case .firstTouchLogged(let repIndex, let gate, let timestamp):
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("incoming firstTouchLogged repIndex=\(repIndex) gate=\(gate)")
            }
            #endif
            engine.onFirstTouchLogged(repIndex: repIndex, gate: gate, timestamp: timestamp)
        case .incorrectDecision(let repIndex, let timestamp):
            guard afpAllowsIncorrectDecision(repIndex: repIndex) else { return }
            guard repController.canAcceptSwipe() else { return }
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("incoming incorrectDecision repIndex=\(repIndex)")
            }
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .awayFromPressure, kind: "incorrectDecision", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .awayFromPressure, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "incorrectDecision")
            #endif
            if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                repController.registerSwipe()
                syncRepController(with: engine.phase)
                saveDecisionForRep(log: log)
            }
        case .coachPaired:
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("incoming coachPaired (envelope)")
            }
            #endif
            break
        case .sessionEnded(_, _):
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("sessionEnded received")
            }
            #endif
            break
        case .partnerTrainingEnded:
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("partnerTrainingEnded received (coordinator also tears down relay)")
            }
            #endif
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
        case .timedSessionActive, .timedSessionInactive, .displayRepEngineReady, .activityChanged:
            break
        }
    }

    private func startRepSolo() {
        guard isSoloRunning, !isSoloDrillInputFrozen else { return }
        guard SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) else { return }
        handleWallSoloTrigger()
    }

    private func onSoloWallCalibrationFinished(_: Double) {
        hasCompletedPassTempoCalibration = true
        tryPresentSessionStartCue()
        startSoloLoop()
    }

    private func startSoloLoop() {
        onSoloCalibrationReadyIfNeeded()
        tryStartSoloAutoloop()
    }

    private func tryStartSoloAutoloop() {
        guard effectiveUsesAutoLoop else { return }
        guard !isSoloDrillInputFrozen else { return }
        guard !soloWallCalibration.isCalibrating else { return }
        guard hasCompletedPassTempoCalibration else { return }
        guard !SoloSessionUserStartGate.shouldBlockSoloRepFlow(
            mode: mode,
            hasCompletedCalibration: hasCompletedPassTempoCalibration,
            isCalibrating: soloWallCalibration.isCalibrating
        ) else { return }
        guard !blockCoachDrillDuringSessionCountdown else { return }
        guard SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) else { return }
        guard !soloLoopRunner.isRunning else { return }
        if case .blockComplete = engine.phase { return }
        isSoloRunning = true
        soloLoopRunner.start(settings: SoloTimingSettings.soloAutoloopSettings(wallController: soloWallCalibration)) { startRepSolo() }
    }

    private func stopSoloAutoloop() {
        isSoloRunning = false
        soloLoopRunner.stop()
    }

    private var showExitLogButtons: Bool {
        guard !mode.requiresPhoneDisplayRelay else { return false }
        if case .awaitingExitLog = engine.phase { return true }
        if case .markerVisible = engine.phase { return true }
        return false
    }

    private func handleWallSoloTrigger() {
        if SoloWallCalibrationInput.handleIfSoloCalibrating(
            mode: mode,
            controller: soloWallCalibration,
            soundEnabled: settingsViewModel.soundEnabled,
            activateAudio: { activateAudioSession() },
            preloadBeep: { preloadBeepAssetsForInstantReveal() },
            onCompletedThreePass: onSoloWallCalibrationFinished
        ) { return }
        guard !isSoloDrillInputFrozen else { return }
        guard SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) else { return }
        switch engine.phase {
        case .waitingForNextRep:
            soloActionIdleCue.onUserTapToStart()
            repController.completeRepCycleEnd()
            guard repController.acceptIncomingNextRep() else { return }
            engine.onNextRep(repIndex: nextRepIndex)
        case .beepedAwaitingPass(repIndex: let ri, _):
            guard afpAllowsPassTrigger(repIndex: ri) else { return }
            guard !repController.hasLoggedTap else { return }
            repController.registerTap()
            #if DEBUG
            let soloPass = Date()
            DecisionSpeedDebugLog.logSoloDisplayPassTrigger(activity: .awayFromPressure, repIndex: ri, displayWallPassTS: soloPass)
            afpApplyPassTrigger(repIndex: ri, passTimestamp: soloPass)
            #else
            afpApplyPassTrigger(repIndex: ri, passTimestamp: Date())
            #endif
        default:
            break
        }
    }

    private var repIndexForExit: Int? {
        switch engine.phase {
        case .awaitingExitLog(let ri, _), .markerVisible(let ri, _, _): return ri
        default: return nil
        }
    }

    /// DEBUG relay: full opacity while waiting; otherwise match marker dimming.
    private var statusOverlayOpacity: CGFloat {
        if shouldShowRelayWaiting { return 1 }
        return isMarkerVisible ? 0.25 : 1
    }

    private var shouldShowRelayWaiting: Bool {
        mode.requiresRelay
            && mode.requiresPhoneDisplayRelay
            && sessionTransportMode == .relayWebSocket
            && !partnerRelaySession.isCoachPaired
            && !TrainingPartnerConnectionCoordinator.shared.isMidSessionPartnerDisconnect
    }

    /// Partner: countdown only after coach is connected (Multipeer) or paired on relay. Solo: always ready.
    private var partnerReadyForCountdown: Bool {
        mode.requiresPhoneDisplayRelay ? coachConnectedForCalibration : hasCompletedPassTempoCalibration
    }

    private var coachConnectedForCalibration: Bool {
        guard mode.requiresPhoneDisplayRelay else { return true }
        switch sessionTransportMode {
        case .multipeer:
            return connectionManager.connectedPeerName != nil
        case .relayWebSocket:
            return partnerRelaySession.isCoachPaired
        }
    }

    private func completePartnerCalibration(averageTravelTime: Double?) {
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(averageTravelTime)
        hasCompletedPassTempoCalibration = true
        showPassTempoCalibration = false
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

    private var repCountOverlay: some View {
        let showLink = mode.requiresPhoneDisplayRelay
        let showRep = !mode.requiresPhoneDisplayRelay || sessionTransportMode != .relayWebSocket || partnerRelaySession.isCoachPaired
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
        switch engine.phase {
        case .waitingForNextRep: rep = "—"
        case .blockComplete: rep = "\(blockTotalReps)"
        case .armedScanning(let r, _, _), .beepedAwaitingPass(let r, _), .markerVisible(let r, _, _), .awaitingExitLog(let r, _):
            rep = "\(r + 1)"
        }
        return "Rep \(rep) of \(blockTotalReps)"
    }

    private var exitLogOverlay: some View {
        Group {
            if let repIndex = repIndexForExit {
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
        }
        .zIndex(2)
    }

    /// Solo: partner-only exit arrows — auto-log the correct “away” direction (opposite of pressure).
    private func applySoloAwayFromPressureAutoExitIfNeeded(repIndex: Int, pressureGate: Gate) {
        guard mode == .solo, !mode.requiresPhoneDisplayRelay else { return }
        guard case .waitingForNextRep = engine.phase else { return }
        guard engine.currentRepIndex == repIndex else { return }
        logExit(repIndex: repIndex, gate: pressureGate.opposite)
    }

    private func logExit(repIndex: Int, gate: Gate) {
        guard afpAllowsExitLogged(repIndex: repIndex) else { return }
        guard !repController.hasLoggedSwipe else { return }
        #if DEBUG
        let soloExit = Date()
        DecisionSpeedDebugLog.logSoloDisplayExitTrigger(activity: .awayFromPressure, repIndex: repIndex, gate: gate, displayWallExitTS: soloExit)
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

    private func saveDecisionForRep(log: AwayFromPressureRepLog) {
        recordSoloLifetimeRepIfNeeded(repIndex: log.repIndex)
        guard let sessionId = CurrentSessionStore.shared.sessionId,
              let sec = log.decisionTimeSeconds else { return }
        if mode.requiresPhoneDisplayRelay, log.repIndex < 3, let pass = log.passTriggeredAt {
            let observed = max(0.01, log.exitLoggedAt.timeIntervalSince(pass))
            let updated = PartnerPassTempoCalibrationStore.updateRollingAverageTravelTime(
                observedSeconds: observed,
                trainingMode: mode
            )
            TrainingPartnerConnectionCoordinator.shared.markSessionCalibrationResolved(
                averageTravelTimeSeconds: updated,
                trainingMode: mode
            )
        }
        let reactionTimeMs = Int(sec * 1000)
        guard reactionTimeMs <= SupabaseDecisionService.maxReactionTimeMs else { return }
        let decision = Decision(
            sessionId: sessionId,
            playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id,
            activityName: ActivityKind.awayFromPressure.rawValue,
            stimulusType: "defender",
            decisionDirection: log.exitedGate?.rawValue ?? "incorrect",
            reactionTimeMs: reactionTimeMs,
            correct: log.correct,
            createdAt: log.exitLoggedAt
        )
        SupabaseDecisionService.shared.saveDecision(decision)
    }

    private func recordSoloLifetimeRepIfNeeded(repIndex: Int) {
        TimedSessionDisplayIntegration.recordSessionRepIfNeeded(
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId,
            repIndex: repIndex,
            recordedRepTokens: &soloLifetimeRecordedRepIndices
        )
        guard mode == .solo else { return }
        soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.recordRep(for: .awayFromPressure)
    }

    private func recordTimedRepAtEngineBoundary(oldPhase: AwayFromPressurePhase, newPhase: AwayFromPressurePhase) {
        guard case .waitingForNextRep = newPhase else { return }
        let completedRepIndex: Int?
        switch oldPhase {
        case .markerVisible(let r, _, _), .awaitingExitLog(let r, _):
            completedRepIndex = r
        default:
            completedRepIndex = nil
        }
        guard let repIndex = completedRepIndex else { return }
        guard engine.repLogs.last?.repIndex == repIndex else { return }
        TimedSessionDisplayIntegration.recordSessionRepIfNeeded(
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId,
            repIndex: repIndex,
            recordedRepTokens: &soloLifetimeRecordedRepIndices
        )
    }

    private var soloFreeModeEndAction: (() -> Void)? {
        guard mode == .solo, SoloTimeBasedSession.isActive else { return nil }
        return { userInitiatedEndSoloSession() }
    }

    private func captureSoloSessionCompletionMetrics() {
        soloTimedCompleteElapsed = soloSessionTimer.elapsedSeconds()
        soloTimedCompleteReps = SoloTimeBasedDisplaySessionSupport.overlayRepCount(
            engineLoggedRepCount: engine.repLogs.count
        )
    }

    private func freezeSoloSessionForCompletion() {
        stopSoloAutoloop()
        cancelSoloAfpStimulusAfterBeepWork()
        soloWallCalibration.cancelPendingBeeps()
        soloSessionTimer.stop()
        captureSoloSessionCompletionMetrics()
    }

    private func userInitiatedEndSoloSession() {
        TimedSessionDisplayIntegration.requestUserEnd(
            mode: mode,
            showComplete: showSoloTimedComplete,
            isEnding: isSoloSessionEnding,
            completionType: .earlyExit,
            freeze: {},
            localEnd: {
                SoloSessionEndTransition.beginUserEnd(
                    setEnding: { isSoloSessionEnding = true },
                    freeze: {},
                    presentOverlay: {
                        finishSoloTimeBasedSession(completionType: .earlyExit)
                    },
                    clearEnding: { isSoloSessionEnding = false }
                )
            }
        )
    }

    private func finishSoloTimeBasedSession(completionType: SessionCompletionType = .completed) {
        TimedSessionDisplayIntegration.finishTimeBasedSession(
            mode: mode,
            showComplete: showSoloTimedComplete,
            completionType: completionType,
            freeze: { freezeSoloSessionForCompletion() },
            localFinish: {
                guard mode == .solo, SoloTimeBasedSession.isActive, !showSoloTimedComplete else { return }
                freezeSoloSessionForCompletion()
                CurrentSessionStore.shared.markSessionCompletionType(completionType)
                FirstSessionOnboardingStore.prepareLoginPromptAfterSoloTimedSessionIfNeeded(
                    repCount: soloTimedCompleteReps,
                    elapsedSeconds: soloTimedCompleteElapsed
                )
                showSoloTimedComplete = true
            }
        )
    }

    private func onSoloCalibrationReadyIfNeeded() {
        TimedSessionDisplayIntegration.onCalibrationReady(
            mode: mode,
            hasCompletedCalibration: hasCompletedPassTempoCalibration,
            isCalibrating: soloWallCalibration.isCalibrating,
            localTimer: soloSessionTimer,
            tryAutoloop: { tryStartSoloAutoloop() }
        )
    }

    private var isMarkerVisible: Bool {
        if case .markerVisible = engine.phase { return true }
        return false
    }

    private var sessionStartCueDrillIsVisible: Bool {
        if mode == .solo, soloWallCalibration.isCalibrating { return false }
        if blockCoachDrillDuringSessionCountdown { return false }
        return true
    }

    private var sessionStartCueStackYOffset: CGFloat {
        guard sessionStartCueContent != nil else { return 0 }
        return (sessionStartCueHeight + ActivitySessionStartCueView.spacingAboveCenterMarker) / 2
    }

    private func tryPresentSessionStartCue() {
        guard !hasPresentedSessionStartCue else { return }
        guard !TimedSessionDisplayIntegration.shouldSkipPartnerSessionStartCue(mode: mode) else { return }
        guard let content = ActivityKind.awayFromPressure.sessionStartCue else {
            hasPresentedSessionStartCue = true
            TimedSessionDisplayIntegration.markPartnerSessionStartChromeCompletedIfNeeded(mode: mode)
            SessionStartCueRepGate.enableRepEngine()
            return
        }
        guard sessionStartCueDrillIsVisible else { return }
        hasPresentedSessionStartCue = true
        sessionStartCueContent = content
    }

    /// Cue finished: clear UI and restart autoloop if a pre-cue start left the runner stuck without firing a rep.
    private func onSessionStartCueFinished() {
        sessionStartCueContent = nil
        TimedSessionDisplayIntegration.markPartnerSessionStartChromeCompletedIfNeeded(mode: mode)
        if soloLoopRunner.isRunning {
            stopSoloAutoloop()
            if mode == .solo, effectiveUsesAutoLoop {
                isSoloRunning = true
            }
        }
        SessionStartCueRepGate.scheduleRepEngineResume {
            resumeRepEngineAfterInstructionDismissed()
        }
    }

    private func pauseSessionForBackground() {
        engine.applicationDidEnterBackground()
    }

    private func resumeSessionIfNeeded() {
        handleRepGateForegroundReturn()
    }

    /// Idempotent: safe when `scenePhase` flips rapidly; gate consumes the pending flag once.
    private func handleRepGateForegroundReturn() {
        guard SessionStartCueRepGate.consumeForegroundReconciliation(instructionVisible: sessionStartCueContent != nil) else { return }
        hasPresentedSessionStartCue = false
        tryPresentSessionStartCue()
        guard sessionStartCueContent == nil else { return }
        resumeRepEngineAfterInstructionDismissed()
    }

    private func resumeRepEngineAfterInstructionDismissed() {
        guard TimedSessionDisplayIntegration.canResumeRepEngine else { return }
        guard SessionStartCueRepGate.claimFirstRepStart() else { return }
        tryStartSoloAutoloop()
        flushPendingCoachNextRepAfterCountdown()
    }

    private var dribbleOrPassLayout: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let focalDownshift = PartnerDisplayLayout.drillFocalCenterYOffset
            let gameplayReference = min(geo.size.width, geo.size.height)

            ZStack {
                if let ctx = afpPreparedPressureContext {
                    AwayFromPressureGateOverlay(
                        gate: ctx.pressureGate,
                        wedgeStyle: wedgeStyle,
                        isDecisionRevealActive: isMarkerVisible
                    )
                    .id("\(ctx.repIndex)-\(ctx.pressureGate)")
                    .zIndex(1)
                }

                awayFromPressureSessionStartCueMarkerStack(
                    geo: geo,
                    center: center,
                    focalDownshift: focalDownshift,
                    gameplayReference: gameplayReference
                )
                .zIndex(55)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onPreferenceChange(SessionStartCueHeightPreferenceKey.self) { sessionStartCueHeight = $0 }
        }
        .soloSessionEndingDim(isActive: isSoloSessionEnding)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func awayFromPressureSessionStartCueMarkerStack(
        geo: GeometryProxy,
        center: CGPoint,
        focalDownshift: CGFloat,
        gameplayReference: CGFloat
    ) -> some View {
        VStack(spacing: ActivitySessionStartCueView.spacingAboveCenterMarker) {
            if let cueContent = sessionStartCueContent {
                ActivitySessionStartCueView(
                    content: cueContent,
                    inlineVisualSideLength: ActivitySessionStartCueView.inlineVisualSideLength(relativeTo: gameplayReference)
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
            y: center.y + focalDownshift - sessionStartCueStackYOffset
        )
    }

    /// Pending cue: same gate as the upcoming marker, mounted from scan/beep through exit; `isDecisionRevealActive` controls preload visibility and reveal-synced inward motion.
    private var afpPreparedPressureContext: (repIndex: Int, pressureGate: Gate)? {
        switch engine.phase {
        case .armedScanning(let r, let g, _), .beepedAwaitingPass(let r, let g), .markerVisible(let r, let g, _), .awaitingExitLog(let r, let g):
            return (r, g)
        default:
            return nil
        }
    }

    private func afpApplyPassTrigger(repIndex: Int, passTimestamp: Date) {
        PBAFlowDebugLog.passReceived(repId: repIndex, timestamp: passTimestamp)
        #if DEBUG
        let wallBeforeEngine = Date()
        DecisionSpeedDebugLog.logDisplayBeforeEnginePass(activity: .awayFromPressure, repIndex: repIndex, embeddedPass: passTimestamp, displayWallBeforeEngine: wallBeforeEngine)
        #endif
        engine.onPassTrigger(repIndex: repIndex, timestamp: passTimestamp)
        PBAFlowDebugLog.reveal(repId: repIndex, timestamp: Date())
    }

    private func registerSupabaseAwayFromPressureBlockSession() {
        TimedSessionDisplayIntegration.registerActivitySegment(
            activity: .awayFromPressure,
            skipSessionCreation: {},
            createSession: {
                CurrentSessionStore.shared.resetDecisionTimingCalibrationForNewDrillBlock(
                    activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
                )
                Task {
                    guard let sessionId = await SupabaseSessionService.shared.createSessionForDrill(
                        activity: .awayFromPressure,
                        blockSize: blockTotalReps,
                        playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id,
                        mode: SessionAnalyticsMode.from(trainingMode: mode)
                    ) else { return }
                    let block = await SupabaseSessionService.shared.openSessionActivityBlock(sessionId: sessionId, activityId: ActivityKind.awayFromPressure.sessionActivityActivityId, blockNumber: 1)
                    await MainActor.run {
                        CurrentSessionStore.shared.setSessionIdOnly(
                            sessionId,
                            mode: SessionAnalyticsMode.from(trainingMode: mode),
                            startAnalyticsClock: mode.requiresPhoneDisplayRelay
                        )
                        if let activityId = block.sessionActivityId { CurrentSessionStore.shared.setCurrentSessionActivityId(activityId) }
                        if let segmentId = block.segmentId {
                            CurrentSessionStore.shared.setCurrentSessionActivitySegmentId(
                                segmentId,
                                activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
                            )
                        }
                    }
                }
            }
        )
    }

    /// Dismiss block summary and restart this drill from rep 0 (same display session; no role/setup routing).
    private func runItBackFromSummary() {
        soloWallCalibration.cancelPendingBeeps()
        stopSoloAutoloop()
        showSoloSummary = false
        navigateToBlockSummary = false
        blockSummaryCalibratedTravelSeconds = nil
        blockSummaryShowTimingAdaptationFeedback = false
        nextRepIndex = 0
        hasSentSessionEnded = false
        repController.reset()
        pendingNextRepIndex = nil
        if mode.requiresPhoneDisplayRelay {
            partnerCoachRepGate.reset()
        }
        engine.restartBlockFromBeginning()
        syncRepController(with: engine.phase)
        registerSupabaseAwayFromPressureBlockSession()
        if mode == .solo {
            let nominal = config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
            SoloSessionStart.applySoloWallCalibrationBoot(
                trainingMode: mode,
                controller: soloWallCalibration,
                nominalWallTravelSeconds: nominal,
                setHasCompletedPassTempoCalibration: { hasCompletedPassTempoCalibration = $0 },
                soundEnabled: settingsViewModel.soundEnabled,
                activateAudio: { activateAudioSession() },
                preloadBeep: { preloadBeepAssetsForInstantReveal() },
                onInlineCalibrationFinished: onSoloWallCalibrationFinished
            )
            onSoloCalibrationReadyIfNeeded()
        } else {
            tryStartSoloAutoloop()
        }
    }

    private func syncRepController(with phase: AwayFromPressurePhase) {
        switch phase {
        case .waitingForNextRep:
            repController.completeRepCycleEnd()
        case .armedScanning:
            repController.startRep()
        case .beepedAwaitingPass:
            if mode == .solo { break }
            repController.openDecisionWindow()
        case .markerVisible:
            repController.openDecisionWindow()
        case .awaitingExitLog:
            // Coach still sends `exitLogged` while in this phase — keep swipe gate open; end cycle only at `waitingForNextRep`.
            repController.openDecisionWindow()
        case .blockComplete:
            repController.completeRepCycleEnd()
        }
        if mode.requiresPhoneDisplayRelay, case .waitingForNextRep = phase {
            flushPendingPartnerCoachNextRepIfNeeded()
        }
    }

    private var statusOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var waitingForCoachRelayOverlay: some View {
        if shouldShowRelayWaiting {
            PartnerRelayDisplayWaitingOverlay(
                joinCode: partnerRelaySession.joinCode,
                activityTitle: "Playing Away From Pressure",
                onExitSession: {
                    cancelWaitingForCoachAndExit()
                }
            )
        }
    }

    private func cancelWaitingForCoachAndExit() {
        pendingNextRepIndex = nil
        blockCoachDrillDuringSessionCountdown = false
        engine.invalidateAllTimers()
        repController.resetForNewSession()
        soloWallCalibration.cancelPendingBeeps()
        stopSoloAutoloop()
        TimedSessionController.shared.clear()
        CurrentSessionStore.shared.clear()
        TrainingPartnerConnectionCoordinator.shared.endPartnerTrainingSession(
            reason: "display.waitingForCoach.backCancel.awayFromPressure"
        )
        dismiss()
    }

    private func afpRelayDisplayLog(_ message: String) {
        #if DEBUG
        print("[RelayWS-DEBUG][AFP Display] \(message)")
        #endif
    }

    private func flushPendingCoachNextRepAfterCountdown() {
        guard SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) else { return }
        guard let idx = pendingNextRepIndex else { return }
        pendingNextRepIndex = nil
        applyPartnerCoachNextRep(repIndex: idx)
    }

    private func alignEngineRepWithCoordinatorSnapshotAfterRelayForegroundAwayFromPressure() {
        guard mode.requiresPhoneDisplayRelay else { return }
        let activityId = ActivityKind.awayFromPressure.sessionActivityActivityId
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

    private func applyPartnerSoftReconnectAfterTransportRestoreAwayFromPressure() {
        guard mode.requiresPhoneDisplayRelay else { return }
        pendingNextRepIndex = nil
        engine.partnerSoftAbandonCurrentRepAwaitCoachRedo(blockRepCount: blockTotalReps)
        let safeRepIndex = max(0, min(engine.currentRepIndex, blockTotalReps - 1))
        var gate = partnerCoachRepGate
        gate.alignExpectedNextForCoachSoftReconnectReplay(repIndex: safeRepIndex)
        partnerCoachRepGate = gate
        TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
            safeRepIndex,
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
        )
        repController.completeRepCycleEnd()
        syncRepController(with: engine.phase)
    }

    private func applyPartnerStartNewSessionLocalTeardownAwayFromPressure() {
        guard !isTearingDownForNewSession else { return }
        isTearingDownForNewSession = true
        defer { isTearingDownForNewSession = false }
        pendingNextRepIndex = nil
        blockCoachDrillDuringSessionCountdown = false
        cancelSoloAfpStimulusAfterBeepWork()
        soloWallCalibration.cancelPendingBeeps()
        engine.invalidateAllTimers()
        repController.resetForNewSession()
    }

    private func applyPartnerCoachNextRep(repIndex: Int) {
        if SessionStartCueRepGate.deferCoachNextRepIfNeeded(
            repIndex: repIndex,
            instructionVisible: sessionStartCueContent != nil,
            pending: &pendingNextRepIndex
        ) { return }
        #if DEBUG
        if repIndex > partnerCoachRepGate.expectedNextCoachRepIndex {
            print("[PartnerCoach][AFP] nextRep coach ahead of displayTrackedNext: coach=\(repIndex) displayNext=\(partnerCoachRepGate.expectedNextCoachRepIndex)")
        }
        #endif
        if case .blockComplete = engine.phase { return }
        if case .waitingForNextRep = engine.phase, repIndex < partnerCoachRepGate.expectedNextCoachRepIndex {
            if repIndex + 1 == partnerCoachRepGate.expectedNextCoachRepIndex {
                sendRepStartedAck(repIndex: repIndex)
                #if DEBUG
                print("[PartnerCoach][AFP] duplicate nextRep \(repIndex) (already applied) — re-sent repStarted")
                #endif
            } else {
                #if DEBUG
                print("[PartnerCoach][AFP] ignoring stale nextRep \(repIndex) (displayTrackedNext=\(partnerCoachRepGate.expectedNextCoachRepIndex))")
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

    private func afpDisplayEngineIsMidRep(repIndex: Int) -> Bool {
        switch engine.phase {
        case .armedScanning(let r, _, _), .beepedAwaitingPass(let r, _), .markerVisible(let r, _, _), .awaitingExitLog(let r, _):
            return r == repIndex
        case .waitingForNextRep, .blockComplete:
            return false
        }
    }

    @discardableResult
    private func tryCommitPartnerCoachNextRep(repIndex: Int) -> Bool {
        if SessionStartCueRepGate.deferCoachNextRepIfNeeded(
            repIndex: repIndex,
            instructionVisible: sessionStartCueContent != nil,
            pending: &pendingNextRepIndex
        ) { return false }
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
            if afpDisplayEngineIsMidRep(repIndex: repIndex) {
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
            print("[PartnerCoach][AFP] onNextRep did not arm (phase still waiting) — reverting repController; no ack")
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
        guard SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) else { return }
        guard let idx = pendingNextRepIndex else { return }
        guard case .waitingForNextRep = engine.phase else { return }
        _ = tryCommitPartnerCoachNextRep(repIndex: idx)
    }

    private func afpAllowsPassTrigger(repIndex: Int, at passTime: Date = Date()) -> Bool {
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
            return SoloRepTiming.fromCalibration(soloWallCalibration.calibratedReturnTime)
                .acceptsPass(at: passTime, beepTime: beepTime)
        }
        return true
    }

    private func afpAllowsExitLogged(repIndex: Int) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .markerVisible(let r, _, _), .awaitingExitLog(let r, _):
            return r == repIndex
        case .waitingForNextRep:
            // Solo auto-exit runs after marker hide → `waitingForNextRep` (see `applySoloAwayFromPressureAutoExitIfNeeded`).
            return mode == .solo && !mode.requiresPhoneDisplayRelay
        default:
            return false
        }
    }

    private func afpAllowsIncorrectDecision(repIndex: Int) -> Bool {
        afpAllowsExitLogged(repIndex: repIndex)
    }

    private func activateAudioSession() {
        PBABeepSoundManager.shared.activateSessionIfNeeded()
    }

    private func preloadBeepAssetsForInstantReveal() {
        PBABeepSoundManager.shared.preloadCurrent()
    }

    private func cancelSoloAfpStimulusAfterBeepWork() {
        soloRepTimingScheduler.cancelAll()
        soloRepBeepWallTime = nil
    }

    private func playBeep() {
        if mode == .solo {
            cancelSoloAfpStimulusAfterBeepWork()
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
                    if case .beepedAwaitingPass(let r, _) = self.engine.phase, r == rep {
                        self.repController.openDecisionWindow()
                    }
                },
                onSyntheticPass: { rep in
                    guard case .beepedAwaitingPass(let r, _) = self.engine.phase, r == rep else { return }
                    guard self.afpAllowsPassTrigger(repIndex: rep) else { return }
                    guard !self.repController.hasLoggedTap else { return }
                    self.repController.registerTap()
                    #if DEBUG
                    let soloPass = Date()
                    DecisionSpeedDebugLog.logSoloDisplayPassTrigger(activity: .awayFromPressure, repIndex: rep, displayWallPassTS: soloPass)
                    self.afpApplyPassTrigger(repIndex: rep, passTimestamp: soloPass)
                    #else
                    self.afpApplyPassTrigger(repIndex: rep, passTimestamp: Date())
                    #endif
                }
            )
            DispatchQueue.main.async {
                self.activateAudioSession()
                self.preloadBeepAssetsForInstantReveal()
                PBABeepSoundManager.shared.play(soundEnabled: self.settingsViewModel.soundEnabled)
            }
        } else {
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
            afpRelayDisplayLog("send beepArmed repIndex=\(repIndex) (relay)")
            #endif
            partnerRelaySession.sendTwoMinuteMessage(message)
            return
        }
        connectionManager.sendTwoMinuteMessage(message)
    }

    private func sendSessionEndedIfNeeded() {
        guard !hasSentSessionEnded else { return }
        hasSentSessionEnded = true
        if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
            afpRelayDisplayLog("send sessionEnded (relay)")
            partnerRelaySession.sendTwoMinuteMessage(.sessionEnded(source: .display, timestamp: Date()))
            return
        }
        connectionManager.sendTwoMinuteMessage(.sessionEnded(source: .display, timestamp: Date()))
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

    /// Ends partner transport when leaving the drill **or** when the app backgrounds (Home / app switcher).
    /// **Do not** send ``sessionEnded`` while persisting — that message tells the coach app to clear the join session and return to the hub.
    private func teardownPartnerTransportWhenSessionSuspends() {
        guard mode.requiresPhoneDisplayRelay else { return }
        if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                afpRelayDisplayLog("persist partner pairing — skip sessionEnded + relay tearDown (Home / next activity)")
            }
            if sessionTransportMode == .multipeer {
                print("[Multipeer] TrainingPartnerSession: display onDisappear — skip sessionEnded + stopHosting (training session active)")
            }
            #endif
            return
        }
        sendSessionEndedIfNeeded()
        if sessionTransportMode == .relayWebSocket {
            afpRelayDisplayLog("teardown partner transport (leave or app background)")
            partnerRelaySession.tearDown()
        }
        if sessionTransportMode == .multipeer {
            connectionManager.stopHosting()
        }
    }

    /// iOS Home / app switcher backgrounds the process — **do not** end training pairing (that forced a new join code).
    private func schedulePartnerSuspendForBackgroundNotification() {
        guard mode.requiresPhoneDisplayRelay else { return }
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "AFPDisplayPartnerSuspend") {
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
}
