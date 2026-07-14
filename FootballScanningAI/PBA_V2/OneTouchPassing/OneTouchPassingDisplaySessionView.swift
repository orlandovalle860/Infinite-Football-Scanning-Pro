//
//  OneTouchPassingDisplaySessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Layout like others; beep then green/red teammates after PASS.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine

private enum OTPersistDebug {
    static func log(_ message: String) {
        #if DEBUG
        print("[OTP-Persist-Debug] \(message)")
        #endif
    }
}

struct OneTouchPassingDisplaySessionView: View {
    let config: OneTouchPassingConfig
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @StateObject private var engine: OneTouchPassingEngine
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigateToBlockSummary = false
    /// True when the pushed summary is the Solo session complete screen (text-only).
    @State private var showSoloSummary = false
    @State private var blockSummaryCalibratedTravelSeconds: Double?
    @State private var blockSummaryShowTimingAdaptationFeedback = false
    @State private var nextRepIndex = 0
    @State private var hasSentSessionEnded = false
    @State private var hasCompletedPassTempoCalibration = false
    @State private var showPassTempoCalibration = false
    @State private var partnerCalibration = PartnerPassTempoCalibrationTracker()
    @State private var showConnectedConfirmation = false
    @State private var hasStartedConnectedToCalibrationTransition = false
    /// True while ``SessionCountdownModifier`` shows 3–2–1–Go; coach drill messages must not advance the engine until the drill is visible.
    @State private var blockCoachDrillDuringSessionCountdown = false
    /// Latest coach `nextRep` deferred until countdown ends or engine reaches ``OneTouchPassingPhase/waitingForNextRep``.
    @State private var pendingNextRepIndex: Int?
    @State private var isTearingDownForNewSession: Bool = false
    @State private var partnerCoachRepGate = PartnerCoachRepSequenceGate()
    /// Red covered gate wedge: same adaptive style as Playing Away From Pressure (`WedgeDifficultyEngine`).
    @State private var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    @StateObject private var repController = RepStateController()
    @StateObject private var soloWallCalibration = SoloWallCalibrationController()
    @ObservedObject private var partnerRelaySession: PartnerRelayDisplaySession
    @StateObject private var soloLoopRunner = SoloLoopRunner()
    /// Solo: delays ``RepStateController/openDecisionWindow()`` until after unified post-beep delay.
    @State private var soloRepTimingScheduler = SoloRepTimingScheduler()
    /// Solo: wall time when the current rep's beep fired; anchors pass tolerance window.
    @State private var soloRepBeepWallTime: Date?
    @State private var soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.totalReps(for: .oneTouchPassing)
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

    private var showsDrillFocalLayout: Bool {
        SoloWallCalibrationDisplayPolicy.showsDrillFocalLayout(
            mode: mode,
            isCalibrating: soloWallCalibration.isCalibrating,
            bootResolved: soloWallBootResolved
        )
    }

    private var sessionTransportMode: SessionTransportMode {
        PartnerTransportPolicy.transportMode(for: .oneTouchPassing, trainingMode: mode)
    }

    init(config: OneTouchPassingConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        let repCount = TimedSessionEnginePolicy.enginePlanBlockSize(
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
            soloFallback: TimedSessionEnginePolicy.timedSessionBlockSize,
            mode: mode
        )
        let plan = OneTouchPassingScenarioGenerator.generatePlan(forBlockSize: repCount)
        _engine = StateObject(wrappedValue: OneTouchPassingEngine(config: config, trainingMode: mode, plan: plan))
        _partnerRelaySession = ObservedObject(wrappedValue: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession)
    }

    private var enginePlanRepCount: Int {
        TimedSessionEnginePolicy.enginePlanBlockSize(
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
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

    private var oneTouchMainStack: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showsDrillFocalLayout {
                layoutWithGates
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
            if mode == .partner, showExitLogButtons, let repIndex = repIndexForExit {
                exitLogOverlay(repIndex: repIndex)
                    .zIndex(2)
            }
            waitingForCoachRelayOverlay
            if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
            }
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(120)
            SoloWallCalibrationGetReadyOverlay(mode: mode, calibration: soloWallCalibration)
            if mode == .solo, soloActionIdleCue.showTapHint, !soloWallCalibration.isCalibrating {
                SoloActionTapHintView()
                    .zIndex(50)
                    .transition(.opacity)
            }
        }
    }

    private var oneTouchSessionPhaseModifiers: some View {
        SessionScreenLayout {
            oneTouchMainStack
        }
            .contentShape(Rectangle())
            .onTapGesture {
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
                OneTouchPassingBlockSummaryView(
                    results: engine.repResults,
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
            .soloSessionCompleteOverlay(
                isPresented: showSoloTimedComplete && !TimedSessionDisplayIntegration.shouldDeferCompletionOverlay,
                elapsedSeconds: soloTimedCompleteElapsed,
                repCount: soloTimedCompleteReps,
                onDone: {
                    FirstSessionOnboardingStore.completeSoloTimedFeedbackDismiss(
                        clearSession: { SoloTimeBasedSession.clear() },
                        dismissOverlay: { showSoloTimedComplete = false },
                        popToRoot: { router.popToRoot() }
                    )
                }
            )
            .soloTapToStartGate(
                mode: mode,
                hasCompletedCalibration: hasCompletedPassTempoCalibration,
                isCalibrating: soloWallCalibration.isCalibrating,
                sessionStartCueActive: sessionStartCueContent != nil,
                localTimer: soloSessionTimer,
                onUserStart: { tryStartSoloAutoloop() }
            )
            .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main), perform: handleOneTouchCoachRelayMessage)
            .onReceive(NotificationCenter.default.publisher(for: .partnerSoftReconnectRepRestart).receive(on: RunLoop.main)) { _ in
                guard !TrainingPartnerConnectionCoordinator.shared.isPartnerSoftReconnectRepRestartSuppressed else { return }
                applyPartnerSoftReconnectAfterTransportRestoreOneTouchPassing()
            }
            .onReceive(NotificationCenter.default.publisher(for: .partnerDisplayWillStartNewSessionFromDisconnect).receive(on: RunLoop.main)) { _ in
                applyPartnerStartNewSessionLocalTeardownOneTouchPassing()
            }
            .onChange(of: engine.currentRepIndex) { _, newValue in
                guard mode.requiresPhoneDisplayRelay else { return }
                TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                    newValue,
                    activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
                )
            }
            .onChange(of: engine.phase) { oldPhase, newPhase in
                handleOneTouchPassingPhaseChange(oldPhase: oldPhase, newPhase: newPhase)
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
                tryStartSoloAutoloop()
            }
    }

    private var oneTouchSessionViewNavChrome: some View {
        oneTouchSessionPhaseModifiers
        .onAppear(perform: oneTouchPassingDisplaySessionOnAppear)
        .onTimedSessionContainerEnd { userInitiatedEndSoloSession() }
        .onDisappear {
            cancelSoloOtpStimulusAfterBeepWork()
            soloWallCalibration.cancelPendingBeeps()
            stopSoloAutoloop()
            pendingNextRepIndex = nil
            SessionStartCueRepGate.onDrillSurfaceDisappeared()
            #if DEBUG
            PartnerPersistDebug.log("OneTouchPassingDisplaySessionView onDisappear")
            otpPersistDebugSnapshot("onDisappear")
            #endif
            // Timed container activity switch reuses the same live session; do not send end/disconnect teardown here.
            if TimedSessionDisplayIntegration.usesSharedSession {
                return
            }
            if mode.requiresPhoneDisplayRelay {
                teardownPartnerTransportWhenSessionSuspends()
            }
        }
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
        .onChange(of: playerStore.selectedPlayerId) { _, _ in
            wedgeStyle = WedgeDifficultyEngine.currentStyle(playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id)
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .onChange(of: partnerRelaySession.joinCode) { _, newCode in
            guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket, let code = newCode else { return }
            otpRelayDisplayLog("relay session created (HTTP OK)")
            otpRelayDisplayLog("join code assigned code=\(code)")
        }
        #endif
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
            guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket else { return }
            alignEngineRepWithCoordinatorSnapshotAfterRelayForegroundOneTouchPassing()
            engine.synchronizeTimersAfterEnteringForeground()
            PartnerRelayCheckpointDisplaySend.sendIfReady(
                engine: engine,
                activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
                relay: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
            )
        }
        .onChange(of: blockCoachDrillDuringSessionCountdown) { old, new in
            #if DEBUG
            OTPersistDebug.log("blockCoachDrillDuringSessionCountdown=\(new) (session 3–2–1–Go overlay \(new ? "visible — drill messages suppressed" : "cleared after Go"))")
            #endif
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
        #if DEBUG
        .onChange(of: partnerRelaySession.isCoachPaired) { _, paired in
            otpPersistDebugSnapshot("relay isCoachPaired=\(paired)")
        }
        .onChange(of: connectionManager.connectedPeerName) { _, name in
            guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .multipeer else { return }
            let peerLabel: String = name ?? "nil"
            otpPersistDebugSnapshot("multipeer connectedPeerName=\(peerLabel)")
        }
        #endif
        .fullScreenCover(
            isPresented: Binding(
                get: { showPassTempoCalibration && !mode.requiresPhoneDisplayRelay },
                set: { showPassTempoCalibration = $0 }
            )
        ) {
            PassTempoCalibrationScreen { calibrated in
                PartnerPassTempoCalibrationStore.save(averageTravelTimeSeconds: calibrated, trainingMode: mode)
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(calibrated)
                hasCompletedPassTempoCalibration = true
                showPassTempoCalibration = false
            }
            .interactiveDismissDisabled()
        }
    }

    /// Session shell after role/training-mode entry: nav chrome, countdown, relay observers, calibration cover.
    private var oneTouchSessionViewWithBaseModifiers: some View {
        oneTouchSessionViewNavChrome
    }

    var body: some View {
        oneTouchSessionViewWithBaseModifiers
    }

    private func handleOneTouchCoachRelayMessage(_ notification: Notification) {
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
            print("[DISPLAY] Received startNextBlock activity=oneTouchPassing")
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
            #if DEBUG
            OTPersistDebug.log("deferred drill message during session countdown (nextRep queued if applicable): \(otpMessageKind(msg))")
            #endif
            return
        }
        #if DEBUG
        OTPersistDebug.log("coach message received: \(otpMessageKind(msg))")
        #endif
        switch msg {
        case .repStarted:
            return
        case .nextRep(let repIndex):
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                if !partnerRelaySession.isCoachPaired {
                    otpRelayDisplayLog("incoming nextRep repIndex=\(repIndex) while isCoachPaired=false (still applying — relay UI can lag peer_joined)")
                }
                otpRelayDisplayLog("incoming nextRep repIndex=\(repIndex)")
            }
            #endif
            applyPartnerCoachNextRep(repIndex: repIndex)
        case .passTriggered(let repIndex, let timestamp):
            guard otpAllowsPassTrigger(repIndex: repIndex) else { return }
            guard repController.state == .preBeep || repController.state == .decisionWindow else { return }
            guard !repController.hasLoggedTap else { return }
            repController.registerTap()
            TimedSessionDisplayIntegration.recordSessionRepIfNeeded(
                activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
                repIndex: repIndex,
                recordedRepTokens: &soloLifetimeRecordedRepIndices
            )
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("incoming passTriggered repIndex=\(repIndex)")
            }
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .oneTouchPassing, kind: "passTriggered", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            #endif
            otpApplyPassTrigger(repIndex: repIndex, passTimestamp: timestamp)
        case .exitLogged(let repIndex, let gate, let timestamp):
            guard otpAllowsExitLogged(repIndex: repIndex) else { return }
            guard repController.canAcceptSwipe() else { return }
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("incoming exitLogged repIndex=\(repIndex) gate=\(gate)")
            }
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .oneTouchPassing, kind: "exitLogged", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .oneTouchPassing, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "exitLogged")
            #endif
            if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let result = engine.repResults.last {
                repController.registerSwipe()
                syncRepController(with: engine.phase)
                saveDecisionForRep(result: result)
            }
        case .firstTouchLogged: break
        case .incorrectDecision(let repIndex, let timestamp):
            guard otpAllowsIncorrectDecision(repIndex: repIndex) else { return }
            guard repController.canAcceptSwipe() else { return }
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("incoming incorrectDecision repIndex=\(repIndex)")
            }
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .oneTouchPassing, kind: "incorrectDecision", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .oneTouchPassing, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "incorrectDecision")
            #endif
            if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let result = engine.repResults.last {
                repController.registerSwipe()
                syncRepController(with: engine.phase)
                saveDecisionForRep(result: result)
            }
        case .coachPaired:
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("incoming coachPaired (envelope)")
            }
            #endif
            break
        case .sessionEnded(_, _):
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("sessionEnded received")
            }
            #endif
            break
        case .partnerTrainingEnded:
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("partnerTrainingEnded received (coordinator also tears down relay)")
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
        case .beepedAwaitingPass(repIndex: let ri):
            guard otpAllowsPassTrigger(repIndex: ri) else { return }
            guard !repController.hasLoggedTap else { return }
            repController.registerTap()
            #if DEBUG
            let soloPass = Date()
            DecisionSpeedDebugLog.logSoloDisplayPassTrigger(activity: .oneTouchPassing, repIndex: ri, displayWallPassTS: soloPass)
            otpApplyPassTrigger(repIndex: ri, passTimestamp: soloPass)
            #else
            otpApplyPassTrigger(repIndex: ri, passTimestamp: Date())
            #endif
        default:
            break
        }
    }

    private func startRepSolo() {
        guard !isSoloDrillInputFrozen else { return }
        guard SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) else { return }
        handleWallSoloTrigger()
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
        soloLoopRunner.start(settings: SoloTimingSettings.soloAutoloopSettings(wallController: soloWallCalibration)) { startRepSolo() }
    }

    private func startSoloLoop() {
        onSoloCalibrationReadyIfNeeded()
    }

    private func onSoloWallCalibrationFinished(_: Double) {
        hasCompletedPassTempoCalibration = true
        tryPresentSessionStartCue()
        startSoloLoop()
    }

    private func stopSoloAutoloop() {
        soloLoopRunner.stop()
    }

    private var showExitLogButtons: Bool {
        guard !mode.requiresPhoneDisplayRelay else { return false }
        if case .awaitingExitLog = engine.phase { return true }
        if case .cueVisible = engine.phase { return true }
        return false
    }

    private var repIndexForExit: Int? {
        switch engine.phase {
        case .awaitingExitLog(let ri), .cueVisible(let ri, _): return ri
        default: return nil
        }
    }

    private var statusOverlayOpacity: CGFloat {
        if shouldShowRelayWaiting { return 1 }
        return hasGatesVisible ? 0.25 : 1
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
        case .armedScanning(let r, _), .beepedAwaitingPass(let r), .cueRevealing(let r, _), .cueVisible(let r, _), .awaitingExitLog(let r):
            rep = "\(r + 1)"
        }
        return "Rep \(rep) of \(blockTotalReps)"
    }

    private func exitLogOverlay(repIndex: Int) -> some View {
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

    /// Solo: exit overlay is intentionally not shown (partner-only arrows). The engine still needs `onExitLogged` to reach ``waitingForNextRep`` so the solo autoloop can schedule the next rep — log the first valid green for this rep.
    private func applySoloOneTouchAutoExitIfNeeded(repIndex: Int) {
        guard mode == .solo, !mode.requiresPhoneDisplayRelay else { return }
        guard case .waitingForNextRep = engine.phase else { return }
        guard engine.currentRepIndex == repIndex else { return }
        guard let plan = engine.currentPlan,
              let gate = Gate.allCases.first(where: { plan.isGreen($0) }) else { return }
        logExit(repIndex: repIndex, gate: gate)
    }

    private func logExit(repIndex: Int, gate: Gate) {
        guard otpAllowsExitLogged(repIndex: repIndex) else { return }
        guard !repController.hasLoggedSwipe else { return }
        #if DEBUG
        let soloExit = Date()
        DecisionSpeedDebugLog.logSoloDisplayExitTrigger(activity: .oneTouchPassing, repIndex: repIndex, gate: gate, displayWallExitTS: soloExit)
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: soloExit) != nil, let result = engine.repResults.last {
            repController.registerSwipe()
            syncRepController(with: engine.phase)
            saveDecisionForRep(result: result)
        }
        #else
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let result = engine.repResults.last {
            repController.registerSwipe()
            syncRepController(with: engine.phase)
            saveDecisionForRep(result: result)
        }
        #endif
        nextRepIndex = repIndex + 1
    }

    private func oneTouchPassingDisplaySessionOnAppear() {
        SessionStartCueRepGate.onDrillSurfaceAppeared()
        if mode == .solo {
            soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.totalReps(for: .oneTouchPassing)
        }
        if mode != .solo {
            soloWallCalibration.resetForNonSoloSession()
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
        PartnerPersistDebug.log("OneTouchPassingDisplaySessionView onAppear")
        otpPersistDebugSnapshot("onAppear")
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
            otpRelayDisplayLog("relay pipeline starting (POST /v1/sessions + WebSocket display)")
            partnerRelaySession.onCoachPairingChanged = { [partnerRelaySession] connected in
                if connected {
                    otpRelayDisplayLog("coach peer_joined")
                } else {
                    let socket = partnerRelaySession.socketConnectionState
                    if socket == .disconnected {
                        otpRelayDisplayLog("coach unpaired (relay socket disconnected)")
                    } else {
                        otpRelayDisplayLog("coach peer_left")
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
        registerSupabaseOneTouchPassingBlockSession()
        if effectiveUsesAutoLoop {
            tryPresentSessionStartCue()
            syncRepController(with: engine.phase)
        }
        if mode == .solo {
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

    private func onSoloCalibrationReadyIfNeeded() {
        TimedSessionDisplayIntegration.onCalibrationReady(
            mode: mode,
            hasCompletedCalibration: hasCompletedPassTempoCalibration,
            isCalibrating: soloWallCalibration.isCalibrating,
            localTimer: soloSessionTimer,
            tryAutoloop: { tryStartSoloAutoloop() }
        )
    }

    private func registerSupabaseOneTouchPassingBlockSession() {
        TimedSessionDisplayIntegration.registerActivitySegment(
            activity: .oneTouchPassing,
            skipSessionCreation: {},
            createSession: {
                CurrentSessionStore.shared.resetDecisionTimingCalibrationForNewDrillBlock(
                    activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
                )
                Task {
                    guard let sessionId = await SupabaseSessionService.shared.createSessionForDrill(
                        activity: .oneTouchPassing,
                        blockSize: blockTotalReps,
                        playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id,
                        mode: SessionAnalyticsMode.from(trainingMode: mode)
                    ) else { return }
                    let block = await SupabaseSessionService.shared.openSessionActivityBlock(sessionId: sessionId, activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId, blockNumber: 1)
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
                                activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
                            )
                        }
                    }
                }
            }
        )
    }

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
            partnerCoachRepGate = PartnerCoachRepSequenceGate()
        }
        engine.restartBlockFromBeginning()
        syncRepController(with: engine.phase)
        registerSupabaseOneTouchPassingBlockSession()
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

    private func handleOneTouchPassingPhaseChange(oldPhase: OneTouchPassingPhase, newPhase: OneTouchPassingPhase) {
        recordTimedRepAtEngineBoundary(oldPhase: oldPhase, newPhase: newPhase)
        #if DEBUG
        OTPersistDebug.log("engine.phase -> \(String(describing: newPhase)) | blockCoachDrillDuringSessionCountdown=\(blockCoachDrillDuringSessionCountdown) waitingOverlay=\(shouldShowRelayWaiting) relayCoachPaired=\(partnerRelaySession.isCoachPaired)")
        #endif
        if mode == .solo, case .beepedAwaitingPass = oldPhase {
            if case .beepedAwaitingPass = newPhase { }
            else {
                cancelSoloOtpStimulusAfterBeepWork()
            }
        }
        syncRepController(with: newPhase)
        if case .blockComplete = newPhase {
            stopSoloAutoloop()
            PlayerFirstRunGuidanceStore.markCompletedFirstRun(activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId)
            pendingNextRepIndex = nil
            if mode.requiresPhoneDisplayRelay, !TimedSessionDisplayIntegration.shouldLoopEngineChunks {
                TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                    blockTotalReps,
                    activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
                )
            }
            let calId = ActivityKind.oneTouchPassing.sessionActivityActivityId
            let base = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
                ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
            blockSummaryCalibratedTravelSeconds = CurrentSessionStore.shared.calibratedBallTravelSeconds(
                baseNominal: base,
                activityId: calId
            )
            blockSummaryShowTimingAdaptationFeedback =
                abs(CurrentSessionStore.shared.calibrationFactor(for: calId) - 1.0) > 0.001
            DispatchQueue.main.async {
                // Coach may already have wrapped to nextRep(0) and restarted this chunk on this turn.
                guard case .blockComplete = self.engine.phase else { return }
                if TimedSessionDisplayIntegration.continueAfterEnginePlanComplete(
                    restartEngineBlock: {
                        let preservedPending = self.pendingNextRepIndex
                        SoloTimeBasedDisplaySessionSupport.resetDisplayRepStateForEngineChunkRestart(
                            mode: self.mode,
                            setNextRepIndex: { self.nextRepIndex = $0 },
                            setPendingNextRepIndex: { self.pendingNextRepIndex = $0 },
                            resetRepController: { self.repController.reset() },
                            resetPartnerCoachRepGate: {
                                self.partnerCoachRepGate = PartnerCoachRepSequenceGate()
                            },
                            clearPendingNextRep: preservedPending == nil
                        )
                        self.engine.restartBlockFromBeginning()
                        self.syncRepController(with: self.engine.phase)
                        if self.mode.requiresPhoneDisplayRelay {
                            TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                                0,
                                activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
                            )
                        }
                        if let preservedPending {
                            self.pendingNextRepIndex = preservedPending
                            self.flushPendingPartnerCoachNextRepIfNeeded()
                        }
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
                                engineLoggedRepCount: engine.repResults.count
                            ),
                            elapsedSeconds: soloSessionTimer.elapsedSeconds()
                        )
                        navigateToBlockSummary = true
                    }
                } else {
                    FirstSessionOnboardingStore.noteTrainingSessionCompleted(
                        deferLoginUntilFeedbackDismissed: false,
                        repCount: SoloTimeBasedDisplaySessionSupport.overlayRepCount(
                            engineLoggedRepCount: engine.repResults.count
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
        if case .armedScanning = newPhase {
            preloadBeepAssetsForInstantReveal()
        }
        if case .beepedAwaitingPass = newPhase,
           SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) {
            playBeep()
        }
        if mode == .solo, !mode.requiresPhoneDisplayRelay,
           case .waitingForNextRep = newPhase,
           case .cueVisible(let oldR, _) = oldPhase {
            DispatchQueue.main.async {
                self.applySoloOneTouchAutoExitIfNeeded(repIndex: oldR)
            }
        }
    }

    private func syncRepController(with phase: OneTouchPassingPhase) {
        switch phase {
        case .waitingForNextRep:
            repController.completeRepCycleEnd()
        case .armedScanning:
            repController.startRep()
        case .beepedAwaitingPass:
            if mode == .solo { break }
            repController.openDecisionWindow()
        case .cueRevealing, .cueVisible:
            repController.openDecisionWindow()
        case .awaitingExitLog:
            repController.openDecisionWindow()
        case .blockComplete:
            repController.completeRepCycleEnd()
        }
        if mode.requiresPhoneDisplayRelay, case .waitingForNextRep = phase {
            flushPendingPartnerCoachNextRepIfNeeded()
        }
    }

    private func saveDecisionForRep(result: OneTouchRepResult) {
        recordSoloLifetimeRepIfNeeded(repIndex: result.repIndex)
        guard let sessionId = CurrentSessionStore.shared.sessionId else { return }
        if mode.requiresPhoneDisplayRelay, result.repIndex < 3 {
            let updated = PartnerPassTempoCalibrationStore.updateRollingAverageTravelTime(
                observedSeconds: max(0.01, result.decisionTime),
                trainingMode: mode
            )
            TrainingPartnerConnectionCoordinator.shared.markSessionCalibrationResolved(
                averageTravelTimeSeconds: updated,
                trainingMode: mode
            )
        }
        let baseTravel = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
        let travelTimeSeconds = CurrentSessionStore.shared.calibratedBallTravelSeconds(
            baseNominal: baseTravel,
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
        )
        let reactionTimeMs = Int((travelTimeSeconds - result.decisionTime) * 1000)
        guard reactionTimeMs <= SupabaseDecisionService.maxReactionTimeMs else { return }
        let decision = Decision(
            sessionId: sessionId,
            playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id,
            activityName: ActivityKind.oneTouchPassing.rawValue,
            stimulusType: "pass",
            decisionDirection: result.chosenGate.rawValue,
            reactionTimeMs: reactionTimeMs,
            correct: result.correct,
            createdAt: Date()
        )
        SupabaseDecisionService.shared.saveDecision(decision)
    }

    private func recordSoloLifetimeRepIfNeeded(repIndex: Int) {
        TimedSessionDisplayIntegration.recordSessionRepIfNeeded(
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
            repIndex: repIndex,
            recordedRepTokens: &soloLifetimeRecordedRepIndices
        )
        guard mode == .solo else { return }
        soloLifetimeRepDisplayCount = SoloLifetimeRepCounter.recordRep(for: .oneTouchPassing)
    }

    private func recordTimedRepAtEngineBoundary(oldPhase: OneTouchPassingPhase, newPhase: OneTouchPassingPhase) {
        guard case .waitingForNextRep = newPhase else { return }
        let completedRepIndex: Int?
        switch oldPhase {
        case .cueVisible(let r, _), .awaitingExitLog(let r):
            completedRepIndex = r
        default:
            completedRepIndex = nil
        }
        guard let repIndex = completedRepIndex else { return }
        guard engine.repResults.last?.repIndex == repIndex else { return }
        TimedSessionDisplayIntegration.recordSessionRepIfNeeded(
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
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
            engineLoggedRepCount: engine.repResults.count
        )
    }

    private func freezeSoloSessionForCompletion() {
        stopSoloAutoloop()
        cancelSoloOtpStimulusAfterBeepWork()
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

    private var hasGatesVisible: Bool {
        !engine.revealedGates.isEmpty
    }

    private var otpShouldPreloadGateCueLayers: Bool {
        switch engine.phase {
        case .armedScanning, .beepedAwaitingPass, .cueRevealing, .cueVisible, .awaitingExitLog:
            return true
        case .waitingForNextRep, .blockComplete:
            return false
        }
    }

    private func otpGateCueOpacity(for gate: Gate) -> Double {
        engine.revealedGates.contains(gate) ? 1 : 0
    }

    private func otpApplyPassTrigger(repIndex: Int, passTimestamp: Date) {
        PBAFlowDebugLog.passReceived(repId: repIndex, timestamp: passTimestamp)
        #if DEBUG
        let wallBeforeEngine = Date()
        DecisionSpeedDebugLog.logDisplayBeforeEnginePass(activity: .oneTouchPassing, repIndex: repIndex, embeddedPass: passTimestamp, displayWallBeforeEngine: wallBeforeEngine)
        #endif
        engine.onPassTrigger(repIndex: repIndex, timestamp: passTimestamp)
        PBAFlowDebugLog.reveal(repId: repIndex, timestamp: Date())
    }

    /// Drives `.id` so gate lane reveal animation replays each rep (same pattern as DOP / Away From Pressure).
    private var oneTouchActiveCueRepIndex: Int {
        switch engine.phase {
        case .armedScanning(let r, _): return r
        case .beepedAwaitingPass(let r): return r
        case .cueRevealing(let r, _): return r
        case .cueVisible(let r, _): return r
        case .awaitingExitLog(let r): return r
        case .waitingForNextRep, .blockComplete: return -1
        }
    }

    private var layoutWithGates: some View {
        GeometryReader { geo in
            layoutWithGatesContent(geo: geo)
        }
        .soloSessionEndingDim(isActive: isSoloSessionEnding)
        .ignoresSafeArea()
    }

    private func layoutWithGatesContent(geo: GeometryProxy) -> some View {
        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        let focalDownshift = PartnerDisplayLayout.drillFocalCenterYOffset
        let gameplayReference = min(geo.size.width, geo.size.height)

        return ZStack {
            otpGateOverlayLayer
            otpSessionStartCueMarkerStack(
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

    @ViewBuilder
    private var otpGateOverlayLayer: some View {
        if let plan = engine.currentPlan, otpShouldPreloadGateCueLayers {
            ForEach(Gate.allCases, id: \.self) { gate in
                OneTouchGateOverlay(
                    gate: gate,
                    isGreen: plan.isGreen(gate),
                    wedgeStyle: wedgeStyle,
                    isDecisionRevealActive: engine.revealedGates.contains(gate)
                )
                .id("\(oneTouchActiveCueRepIndex)-\(gate.rawValue)")
                .opacity(otpGateCueOpacity(for: gate))
                .animation(nil, value: engine.revealedGates)
                .zIndex(1)
            }
        }
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
        guard let content = ActivityKind.oneTouchPassing.sessionStartCue else {
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
        }
        SessionStartCueRepGate.scheduleRepEngineResume {
            resumeRepEngineAfterInstructionDismissed()
        }
    }

    private func pauseSessionForBackground() {
        if mode == .solo {
            cancelSoloOtpStimulusAfterBeepWork()
            if soloWallCalibration.isCalibrating {
                soloWallCalibration.cancelPendingBeeps()
            }
        }
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

    @ViewBuilder
    private func otpSessionStartCueMarkerStack(
        geo: GeometryProxy,
        center: CGPoint,
        focalDownshift: CGFloat,
        gameplayReference: CGFloat
    ) -> some View {
        let markerStackSpacing: CGFloat = sessionStartCueContent == nil
            ? 10
            : ActivitySessionStartCueView.spacingAboveCenterMarker
        VStack(spacing: markerStackSpacing) {
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

    private var statusOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var waitingForCoachRelayOverlay: some View {
        if shouldShowRelayWaiting {
            PartnerRelayDisplayWaitingOverlay(
                joinCode: partnerRelaySession.joinCode,
                activityTitle: "One-Touch Passing",
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
            reason: "display.waitingForCoach.backCancel.oneTouchPassing"
        )
        dismiss()
    }

    private func otpRelayDisplayLog(_ message: String) {
        #if DEBUG
        print("[RelayWS-DEBUG][OTP Display] \(message)")
        #endif
    }

    #if DEBUG
    private func otpPersistDebugSnapshot(_ tag: String) {
        let sessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
        let paired = partnerRelaySession.isCoachPaired
        let waiting = shouldShowRelayWaiting
        let ready = partnerReadyForCountdown
        let block = blockCoachDrillDuringSessionCountdown
        let phase = String(describing: engine.phase)
        OTPersistDebug.log("\(tag) | partnerTrainingSessionActive=\(sessionActive) relayCoachPaired=\(paired) otpThinksCoachPaired(relay)=\(paired) partnerReadyForCountdown=\(ready) waitingForCoachOverlay=\(waiting) reason=\(waiting ? "!isCoachPaired (relay)" : "paired or not relay") blockCoachDrillDuringSessionCountdown=\(block) phase=\(phase)")
    }

    private func otpMessageKind(_ msg: TwoMinuteMessage) -> String {
        switch msg {
        case .nextRep(let i): return "nextRep(\(i))"
        case .repStarted(let i, _): return "repStarted(\(i))"
        case .beepArmed(let i, _): return "beepArmed(\(i))"
        case .passTriggered(let i, _): return "passTriggered(\(i))"
        case .exitLogged(let i, let g, _): return "exitLogged(\(i),\(g))"
        case .firstTouchLogged(let i, let g, _): return "firstTouchLogged(\(i),\(g))"
        case .incorrectDecision(let i, _): return "incorrectDecision(\(i))"
        case .coachPaired(let sid): return "coachPaired(\(sid))"
        case .sessionEnded(_, _): return "sessionEnded"
        case .partnerTrainingEnded(_): return "partnerTrainingEnded"
        case .partnerSessionCheckpoint(_, _, _, _, _, _): return "partnerSessionCheckpoint"
        case .sessionStarted(let id, let n, _): return "sessionStarted(\(id),\(n))"
        case .calibrationPassTapped: return "calibrationPassTapped"
        case .calibrationArrivalTapped: return "calibrationArrivalTapped"
        case .calibrationFinished(let s): return "calibrationFinished(\(String(describing: s)))"
        case .startNextBlock: return "startNextBlock"
        case .activityChanged: return "activityChanged"
        case .timedSessionActive(let id, _): return "timedSessionActive(\(id))"
        case .timedSessionInactive: return "timedSessionInactive"
        case .displayRepEngineReady(let id, _): return "displayRepEngineReady(\(id))"
        }
    }
    #endif

    private func activateAudioSession() {
        PBABeepSoundManager.shared.activateSessionIfNeeded()
    }

    private func flushPendingCoachNextRepAfterCountdown() {
        guard SessionStartCueRepGate.canStartRepEngine(instructionVisible: sessionStartCueContent != nil) else { return }
        guard let idx = pendingNextRepIndex else { return }
        pendingNextRepIndex = nil
        applyPartnerCoachNextRep(repIndex: idx)
    }

    /// After relay foreground reconnect: keep display rep index in sync with coordinator (survives `StateObject` engine recreation).
    private func alignEngineRepWithCoordinatorSnapshotAfterRelayForegroundOneTouchPassing() {
        guard mode.requiresPhoneDisplayRelay else { return }
        let activityId = ActivityKind.oneTouchPassing.sessionActivityActivityId
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

    private func applyPartnerSoftReconnectAfterTransportRestoreOneTouchPassing() {
        guard mode.requiresPhoneDisplayRelay else { return }
        pendingNextRepIndex = nil
        engine.partnerSoftAbandonCurrentRepAwaitCoachRedo(blockRepCount: blockTotalReps)
        let safeRepIndex = max(0, min(engine.currentRepIndex, blockTotalReps - 1))
        var gate = partnerCoachRepGate
        gate.alignExpectedNextForCoachSoftReconnectReplay(repIndex: safeRepIndex)
        partnerCoachRepGate = gate
        TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
            safeRepIndex,
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
        )
        repController.completeRepCycleEnd()
        syncRepController(with: engine.phase)
    }

    private func applyPartnerStartNewSessionLocalTeardownOneTouchPassing() {
        guard !isTearingDownForNewSession else { return }
        isTearingDownForNewSession = true
        defer { isTearingDownForNewSession = false }
        pendingNextRepIndex = nil
        blockCoachDrillDuringSessionCountdown = false
        cancelSoloOtpStimulusAfterBeepWork()
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
            print("[PartnerCoach][OTP] nextRep coach ahead of displayTrackedNext: coach=\(repIndex) displayNext=\(partnerCoachRepGate.expectedNextCoachRepIndex)")
        }
        #endif
        let isTerminalPhase = { if case .blockComplete = engine.phase { return true }; return false }()
        if SoloTimeBasedDisplaySessionSupport.shouldRestartEngineForPartnerCoachChunkWrap(
            repIndex: repIndex,
            expectedNextCoachRepIndex: partnerCoachRepGate.expectedNextCoachRepIndex,
            engineCurrentRepIndex: engine.currentRepIndex,
            isTerminalPhase: isTerminalPhase,
            chunkSize: blockTotalReps
        ) {
            restartPartnerEngineChunkForCoachWrap()
        }
        var wrapGate = partnerCoachRepGate
        wrapGate.resetIfCoachWrappedToStartOfChunk(
            repIndex: repIndex,
            chunkSize: blockTotalReps,
            loopsChunks: TimedSessionDisplayIntegration.shouldLoopEngineChunks
        )
        partnerCoachRepGate = wrapGate
        if case .waitingForNextRep = engine.phase, repIndex < partnerCoachRepGate.expectedNextCoachRepIndex {
            if repIndex + 1 == partnerCoachRepGate.expectedNextCoachRepIndex {
                sendRepStartedAck(repIndex: repIndex)
                #if DEBUG
                print("[PartnerCoach][OTP] duplicate nextRep \(repIndex) (already applied) — re-sent repStarted")
                #endif
            } else {
                #if DEBUG
                print("[PartnerCoach][OTP] ignoring stale nextRep \(repIndex) (displayTrackedNext=\(partnerCoachRepGate.expectedNextCoachRepIndex))")
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

    private func restartPartnerEngineChunkForCoachWrap() {
        TimedSessionDisplayIntegration.controller.advanceCycleIfNeeded()
        SoloTimeBasedDisplaySessionSupport.resetDisplayRepStateForEngineChunkRestart(
            mode: mode,
            setNextRepIndex: { nextRepIndex = $0 },
            setPendingNextRepIndex: { pendingNextRepIndex = $0 },
            resetRepController: { repController.reset() },
            resetPartnerCoachRepGate: { partnerCoachRepGate = PartnerCoachRepSequenceGate() }
        )
        engine.restartBlockFromBeginning()
        syncRepController(with: engine.phase)
        if mode.requiresPhoneDisplayRelay {
            TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                0,
                activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
            )
        }
    }

    private func otpDisplayEngineIsMidRep(repIndex: Int) -> Bool {
        switch engine.phase {
        case .armedScanning(let r, _), .beepedAwaitingPass(let r), .cueRevealing(let r, _), .cueVisible(let r, _), .awaitingExitLog(let r):
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
            if !SoloTimeBasedDisplaySessionSupport.allowsPartnerCoachChunkWrapNextRep(
                repIndex: repIndex,
                engineCurrentRepIndex: engine.currentRepIndex
            ) {
                pendingNextRepIndex = nil
                return false
            }
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
            if otpDisplayEngineIsMidRep(repIndex: repIndex) {
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
            print("[PartnerCoach][OTP] onNextRep did not arm (phase still waiting) — reverting repController; no ack")
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

    private func otpAllowsPassTrigger(repIndex: Int, at passTime: Date = Date()) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .beepedAwaitingPass(let r):
            guard r == repIndex else { return false }
        case .armedScanning(let r, _):
            guard r == repIndex else { return false }
            if mode == .solo { return false }
        default:
            return false
        }
        if mode == .solo {
            guard let beepTime = soloRepBeepWallTime else { return false }
            // Wall-time tolerance is measured from the beep (see `playBeep`), not from `armedScanning`.
            return SoloRepTiming.fromCalibration(soloWallCalibration.calibratedReturnTime)
                .acceptsPass(at: passTime, beepTime: beepTime)
        }
        return true
    }

    private func otpAllowsExitLogged(repIndex: Int) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .cueVisible(let r, _), .cueRevealing(let r, _), .awaitingExitLog(let r):
            return r == repIndex
        case .waitingForNextRep:
            // Solo auto-exit runs after cue hide → `waitingForNextRep` (see `applySoloOneTouchAutoExitIfNeeded`).
            return mode == .solo && !mode.requiresPhoneDisplayRelay
        default:
            return false
        }
    }

    private func otpAllowsIncorrectDecision(repIndex: Int) -> Bool {
        otpAllowsExitLogged(repIndex: repIndex)
    }

    private func preloadBeepAssetsForInstantReveal() {
        PBABeepSoundManager.shared.preloadCurrent()
    }

    private func cancelSoloOtpStimulusAfterBeepWork() {
        soloRepTimingScheduler.cancelAll()
        soloRepBeepWallTime = nil
    }

    private func playBeep() {
        if mode == .solo {
            // Solo timing anchor: engine finishes `armedScanning` (unified scan→beep delay) before this runs.
            // `soloRepBeepWallTime` and SoloRepTimingScheduler count from the beep / awaiting-pass moment — not scan start.
            cancelSoloOtpStimulusAfterBeepWork()
            let beepWall = Date()
            soloRepBeepWallTime = beepWall
            if case .beepedAwaitingPass(let r) = engine.phase {
                PBAFlowDebugLog.beep(repId: r, timestamp: beepWall)
            }
            sendBeepArmed(repIndex: engine.currentRepIndex)
            let timing = SoloRepTiming.fromCalibration(soloWallCalibration.calibratedReturnTime)
            let repAtBeep = engine.currentRepIndex
            soloRepTimingScheduler.scheduleRep(
                timing: timing,
                repIndex: repAtBeep,
                onDecisionOpen: { rep in
                    if case .beepedAwaitingPass(let r) = self.engine.phase, r == rep {
                        self.repController.openDecisionWindow()
                    }
                },
                onSyntheticPass: { rep in
                    guard case .beepedAwaitingPass(let r) = self.engine.phase, r == rep else { return }
                    guard self.otpAllowsPassTrigger(repIndex: rep) else { return }
                    guard !self.repController.hasLoggedTap else { return }
                    self.repController.registerTap()
                    #if DEBUG
                    let soloPass = Date()
                    DecisionSpeedDebugLog.logSoloDisplayPassTrigger(activity: .oneTouchPassing, repIndex: rep, displayWallPassTS: soloPass)
                    self.otpApplyPassTrigger(repIndex: rep, passTimestamp: soloPass)
                    #else
                    self.otpApplyPassTrigger(repIndex: rep, passTimestamp: Date())
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
            if case .beepedAwaitingPass(let r) = engine.phase {
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
            otpRelayDisplayLog("send beepArmed repIndex=\(repIndex) (relay)")
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
            otpRelayDisplayLog("send sessionEnded (relay)")
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

    /// **Do not** send ``sessionEnded`` while persisting — that message tells the coach app to clear the join session and return to the hub.
    private func teardownPartnerTransportWhenSessionSuspends() {
        guard mode.requiresPhoneDisplayRelay else { return }
        if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("persist partner pairing — skip sessionEnded + relay tearDown (Home / next activity)")
            }
            if sessionTransportMode == .multipeer {
                print("[Multipeer] TrainingPartnerSession: display onDisappear — skip sessionEnded + stopHosting (training session active)")
            }
            #endif
            return
        }
        sendSessionEndedIfNeeded()
        if sessionTransportMode == .relayWebSocket {
            otpRelayDisplayLog("teardown partner transport (leave or app background)")
            partnerRelaySession.tearDown()
        }
        if sessionTransportMode == .multipeer {
            connectionManager.stopHosting()
        }
    }

    private func schedulePartnerSuspendForBackgroundNotification() {
        guard mode.requiresPhoneDisplayRelay else { return }
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "OTPDisplayPartnerSuspend") {
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
