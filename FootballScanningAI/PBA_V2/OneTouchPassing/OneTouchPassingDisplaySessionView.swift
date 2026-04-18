//
//  OneTouchPassingDisplaySessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Layout like others; CHECK flash then green/red teammates after PASS.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine

#if DEBUG
private enum OTPPersistDebug {
    static func log(_ message: String) {
        print("[OTP-Persist-Debug] \(message)")
    }
}
#endif

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
    @State private var blockSummaryCalibratedTravelSeconds: Double?
    @State private var blockSummaryShowTimingAdaptationFeedback = false
    @State private var nextRepIndex = 0
    @State private var audioInterruptionObserver: NSObjectProtocol?
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
    @ObservedObject private var partnerRelaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
    @State private var playerFirstRunGuidanceText: String?
    @State private var playerFirstRunGuidanceOpacity = 0.0
    @State private var playerFirstRunGuidanceTask: Task<Void, Never>?

    private var sessionTransportMode: SessionTransportMode {
        PartnerTransportPolicy.transportMode(for: .oneTouchPassing, trainingMode: mode)
    }

    init(config: OneTouchPassingConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        let repCount = TrainingPartnerConnectionCoordinator.shared.partnerBlockTotalReps(
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
            soloFallback: 12,
            mode: mode
        )
        let plan = OneTouchPassingScenarioGenerator.generatePlan(forBlockSize: repCount)
        _engine = StateObject(wrappedValue: OneTouchPassingEngine(config: config, trainingMode: mode, plan: plan))
    }

    private var blockTotalReps: Int {
        TrainingPartnerConnectionCoordinator.shared.partnerBlockTotalReps(
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId,
            soloFallback: 12,
            mode: mode
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            layoutWithGates
            statusOverlay
                .opacity(statusOverlayOpacity)
            repCountOverlay
            if showExitLogButtons, let repIndex = repIndexForExit {
                exitLogOverlay(repIndex: repIndex)
                    .zIndex(2)
            }
            waitingForCoachRelayOverlay
            if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
            }
            PlayerFirstRunGuidanceToastOverlay(message: playerFirstRunGuidanceText, opacity: playerFirstRunGuidanceOpacity)
                .zIndex(119)
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(120)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if mode == .solo { handleWallSoloTrigger() }
        }
        .navigationDestination(isPresented: $navigateToBlockSummary) {
            OneTouchPassingBlockSummaryView(
                results: engine.repResults,
                config: config,
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
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main), perform: handleOneTouchCoachRelayMessage)
        .onReceive(NotificationCenter.default.publisher(for: .partnerSoftReconnectRepRestart).receive(on: RunLoop.main)) { _ in
            guard !TrainingPartnerConnectionCoordinator.shared.isPartnerSoftReconnectRepRestartSuppressed else { return }
            applyPartnerSoftReconnectAfterTransportRestoreOneTouchPassing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .partnerDisplayWillStartNewSessionFromDisconnect).receive(on: RunLoop.main)) { _ in
            applyPartnerStartNewSessionLocalTeardownOneTouchPassing()
        }
        .onChange(of: engine.currentRepIndex) { _, newValue in
            if newValue >= 2 {
                PlayerFirstRunGuidanceToastAnimator.cancel(
                    task: &playerFirstRunGuidanceTask,
                    message: $playerFirstRunGuidanceText,
                    opacity: $playerFirstRunGuidanceOpacity
                )
            }
            guard mode.requiresPhoneDisplayRelay else { return }
            TrainingPartnerConnectionCoordinator.shared.syncDisplaySessionCurrentRepIndex(
                newValue,
                activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
            )
        }
        .onChange(of: engine.phase) { oldPhase, newPhase in
            #if DEBUG
            OTPPersistDebug.log("engine.phase -> \(String(describing: newPhase)) | blockCoachDrillDuringSessionCountdown=\(blockCoachDrillDuringSessionCountdown) waitingOverlay=\(shouldShowRelayWaiting) relayCoachPaired=\(partnerRelaySession.isCoachPaired)")
            #endif
            syncRepController(with: newPhase)
            if case .blockComplete = newPhase {
                PlayerFirstRunGuidanceStore.markCompletedFirstRun(activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId)
                pendingNextRepIndex = nil
                if mode.requiresPhoneDisplayRelay {
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
                DispatchQueue.main.async { navigateToBlockSummary = true }
            }
            if case .armedScanning = newPhase {
                preloadBeepAssetsForInstantReveal()
            }
            if case .showingCheck = newPhase {
                #if DEBUG
                OTPPersistDebug.log("phase showingCheck — playBeep() armed from phase handler")
                #endif
                playBeep()
            }
            oneTouchPassingPlayerFirstRunGuidanceIfNeeded(oldPhase: oldPhase, newPhase: newPhase)
        }
        .onAppear(perform: oneTouchPassingDisplaySessionOnAppear)
        .onDisappear {
            pendingNextRepIndex = nil
            PlayerFirstRunGuidanceToastAnimator.cancel(
                task: &playerFirstRunGuidanceTask,
                message: $playerFirstRunGuidanceText,
                opacity: $playerFirstRunGuidanceOpacity
            )
            #if DEBUG
            PartnerPersistDebug.log("OneTouchPassingDisplaySessionView onDisappear")
            otpPersistDebugSnapshot("onDisappear")
            #endif
            if mode.requiresPhoneDisplayRelay {
                teardownPartnerTransportWhenSessionSuspends()
            }
            unsubscribeFromAudioInterruption()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                engine.applicationDidEnterBackground()
            } else if newPhase == .active {
                engine.synchronizeTimersAfterEnteringForeground()
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
        .sessionCountdown(waitForPartnerReady: mode.requiresPhoneDisplayRelay, partnerReady: partnerReadyForCountdown, suppressCoachMessagesDuringCountdown: $blockCoachDrillDuringSessionCountdown)
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
            OTPPersistDebug.log("blockCoachDrillDuringSessionCountdown=\(new) (session 3–2–1–Go overlay \(new ? "visible — drill messages suppressed" : "cleared after Go"))")
            #endif
            guard mode.requiresPhoneDisplayRelay, old == true, new == false else { return }
            flushPendingCoachNextRepAfterCountdown()
        }
        #if DEBUG
        .onChange(of: partnerRelaySession.isCoachPaired) { _, paired in
            otpPersistDebugSnapshot("relay isCoachPaired=\(paired)")
        }
        .onChange(of: connectionManager.connectedPeerName) { _, name in
            guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .multipeer else { return }
            otpPersistDebugSnapshot("multipeer connectedPeerName=\(name ?? "nil")")
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

    private func handleOneTouchCoachRelayMessage(_ notification: Notification) {
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
            OTPPersistDebug.log("deferred drill message during session countdown (nextRep queued if applicable): \(otpMessageKind(msg))")
            #endif
            return
        }
        #if DEBUG
        OTPPersistDebug.log("coach message received: \(otpMessageKind(msg))")
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
        case .sessionEnded:
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
        }
    }

    private func handleWallSoloTrigger() {
        switch engine.phase {
        case .waitingForNextRep:
            repController.completeRepCycleEnd()
            guard repController.acceptIncomingNextRep() else { return }
            engine.onNextRep(repIndex: nextRepIndex)
        case .awaitingPassTrigger(repIndex: let ri):
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
        return (hasGatesVisible || engine.showCheckCue) ? 0.25 : 1
    }

    private var shouldShowRelayWaiting: Bool {
        mode.requiresPhoneDisplayRelay
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
        case .armedScanning(let r, _), .showingCheck(let r), .awaitingPassTrigger(let r), .cueRevealing(let r, _), .cueVisible(let r, _), .awaitingExitLog(let r):
            rep = "\(r + 1)"
        }
        return "Rep \(rep) of \(blockTotalReps)"
    }

    private func exitLogOverlay(repIndex: Int) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 20) {
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
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        hasCompletedPassTempoCalibration = false
        if mode.requiresPhoneDisplayRelay {
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
            showPassTempoCalibration = PBASessionFlowPolicy.shouldPromptCalibration(for: mode)
            if let calibrated = PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds(),
               !PBASessionFlowPolicy.shouldPromptCalibration(for: mode) {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(calibrated)
                hasCompletedPassTempoCalibration = true
            } else {
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nil)
            }
        }
        partnerCalibration.reset()
        showConnectedConfirmation = false
        hasStartedConnectedToCalibrationTransition = false
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
        subscribeToAudioInterruption()
        AnalyticsManager.shared.track(.trainingSessionStarted, playerId: playerStore.selectedPlayerId)
        registerSupabaseOneTouchPassingBlockSession()
    }

    private func registerSupabaseOneTouchPassingBlockSession() {
        CurrentSessionStore.shared.resetDecisionTimingCalibrationForNewDrillBlock(
            activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId
        )
        Task {
            guard let sessionId = await SupabaseSessionService.shared.createSessionForDrill(activity: .oneTouchPassing, blockSize: blockTotalReps, playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id) else { return }
            let activityId = await SupabaseSessionService.shared.createSessionActivity(sessionId: sessionId, activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId, blockNumber: 1)
            await MainActor.run {
                CurrentSessionStore.shared.setSessionIdOnly(sessionId)
                if let activityId = activityId { CurrentSessionStore.shared.setCurrentSessionActivityId(activityId) }
            }
        }
    }

    private func runItBackFromSummary() {
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
        registerSupabaseOneTouchPassingBlockSession()
    }

    private func oneTouchPassingPlayerFirstRunGuidanceIfNeeded(oldPhase: OneTouchPassingPhase, newPhase: OneTouchPassingPhase) {
        let activityId = ActivityKind.oneTouchPassing.sessionActivityActivityId
        guard !PlayerFirstRunGuidanceStore.hasCompletedFirstRun(activityId: activityId) else { return }
        guard engine.currentRepIndex <= 1 else { return }

        if case .cueVisible(let r, _) = newPhase, r == 0 {
            if case .cueVisible(let rOld, _) = oldPhase, rOld == 0 { return }
            guard let msg = PlayerFirstRunGuidanceCopy.message(for: .oneTouchPassing, repIndexZeroBased: 0) else { return }
            PlayerFirstRunGuidanceToastAnimator.schedule(
                text: msg,
                task: &playerFirstRunGuidanceTask,
                message: $playerFirstRunGuidanceText,
                opacity: $playerFirstRunGuidanceOpacity
            )
        }
        if case .cueVisible(let r, _) = newPhase, r == 1 {
            if case .cueVisible(let rOld, _) = oldPhase, rOld == 1 { return }
            guard let msg = PlayerFirstRunGuidanceCopy.message(for: .oneTouchPassing, repIndexZeroBased: 1) else { return }
            PlayerFirstRunGuidanceToastAnimator.schedule(
                text: msg,
                task: &playerFirstRunGuidanceTask,
                message: $playerFirstRunGuidanceText,
                opacity: $playerFirstRunGuidanceOpacity
            )
        }
    }

    private func syncRepController(with phase: OneTouchPassingPhase) {
        switch phase {
        case .waitingForNextRep:
            repController.completeRepCycleEnd()
        case .armedScanning:
            repController.startRep()
        case .showingCheck, .awaitingPassTrigger, .cueRevealing, .cueVisible:
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
        guard let sessionId = CurrentSessionStore.shared.sessionId else { return }
        if mode.requiresPhoneDisplayRelay, result.repIndex < 3 {
            let updated = PartnerPassTempoCalibrationStore.updateRollingAverageTravelTime(
                observedSeconds: max(0.01, result.decisionTime),
                trainingMode: .partner
            )
            TrainingPartnerConnectionCoordinator.shared.markSessionCalibrationResolved(
                averageTravelTimeSeconds: updated,
                trainingMode: .partner
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

    private var hasGatesVisible: Bool {
        !engine.revealedGates.isEmpty
    }

    private var otpShouldPreloadGateCueLayers: Bool {
        switch engine.phase {
        case .armedScanning, .showingCheck, .awaitingPassTrigger, .cueRevealing, .cueVisible, .awaitingExitLog:
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

    /// Drives `.id` so `DangerZoneOverlay` reveal animation replays each rep (same pattern as Away From Pressure).
    private var oneTouchActiveCueRepIndex: Int {
        switch engine.phase {
        case .armedScanning(let r, _): return r
        case .showingCheck(let r): return r
        case .awaitingPassTrigger(let r): return r
        case .cueRevealing(let r, _): return r
        case .cueVisible(let r, _): return r
        case .awaitingExitLog(let r): return r
        case .waitingForNextRep, .blockComplete: return -1
        }
    }

    private var layoutWithGates: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                VStack(spacing: 10) {
                    Text("X")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                }
                .position(x: center.x, y: center.y)

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
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: PartnerDisplayLayout.drillFocalCenterYOffset)
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
                activityTitle: "One-Touch Passing",
                onExitSession: {
                    router.popToRoot(endingPartnerSession: false)
                }
            )
        }
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
        OTPPersistDebug.log("\(tag) | partnerTrainingSessionActive=\(sessionActive) relayCoachPaired=\(paired) otpThinksCoachPaired(relay)=\(paired) partnerReadyForCountdown=\(ready) waitingForCoachOverlay=\(waiting) reason=\(waiting ? "!isCoachPaired (relay)" : "paired or not relay") blockCoachDrillDuringSessionCountdown=\(block) phase=\(phase)")
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
        case .sessionEnded(_): return "sessionEnded"
        case .partnerTrainingEnded(_): return "partnerTrainingEnded"
        case .partnerSessionCheckpoint(_, _, _, _, _, _): return "partnerSessionCheckpoint"
        case .sessionStarted(let id, let n, _): return "sessionStarted(\(id),\(n))"
        case .calibrationPassTapped: return "calibrationPassTapped"
        case .calibrationArrivalTapped: return "calibrationArrivalTapped"
        case .calibrationFinished(let s): return "calibrationFinished(\(String(describing: s)))"
        case .startNextBlock: return "startNextBlock"
        }
    }
    #endif

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func subscribeToAudioInterruption() {
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .ended { self.activateAudioSession() }
        }
    }

    private func unsubscribeFromAudioInterruption() {
        if let observer = audioInterruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            audioInterruptionObserver = nil
        }
    }

    private func flushPendingCoachNextRepAfterCountdown() {
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
        engine.invalidateAllTimers()
        repController.resetForNewSession()
        PlayerFirstRunGuidanceToastAnimator.cancel(
            task: &playerFirstRunGuidanceTask,
            message: $playerFirstRunGuidanceText,
            opacity: $playerFirstRunGuidanceOpacity
        )
    }

    private func applyPartnerCoachNextRep(repIndex: Int) {
        #if DEBUG
        if repIndex > partnerCoachRepGate.expectedNextCoachRepIndex {
            print("[PartnerCoach][OTP] nextRep coach ahead of displayTrackedNext: coach=\(repIndex) displayNext=\(partnerCoachRepGate.expectedNextCoachRepIndex)")
        }
        #endif
        if case .blockComplete = engine.phase { return }
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
            print("[NEXTREP DEFERRED] buffering until phase=waitingForNextRep")
            pendingNextRepIndex = repIndex
            return
        }
        _ = tryCommitPartnerCoachNextRep(repIndex: repIndex)
    }

    private func otpDisplayEngineIsMidRep(repIndex: Int) -> Bool {
        switch engine.phase {
        case .armedScanning(let r, _), .showingCheck(let r), .awaitingPassTrigger(let r), .cueRevealing(let r, _), .cueVisible(let r, _), .awaitingExitLog(let r):
            return r == repIndex
        case .waitingForNextRep, .blockComplete:
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
        if !repController.acceptIncomingNextRep() {
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
        guard let idx = pendingNextRepIndex else { return }
        guard case .waitingForNextRep = engine.phase else { return }
        _ = tryCommitPartnerCoachNextRep(repIndex: idx)
    }

    private func otpAllowsPassTrigger(repIndex: Int) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .awaitingPassTrigger(let r):
            return r == repIndex
        case .armedScanning(let r, _):
            return r == repIndex
        case .showingCheck(let r):
            return r == repIndex
        default:
            return false
        }
    }

    private func otpAllowsExitLogged(repIndex: Int) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .cueVisible(let r, _), .cueRevealing(let r, _), .awaitingExitLog(let r):
            return r == repIndex
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

    private func playBeep() {
        #if DEBUG
        OTPPersistDebug.log("playBeep() executing (CHECK cue)")
        #endif
        repController.openDecisionWindow()
        if case .showingCheck(let r) = engine.phase {
            PBAFlowDebugLog.beep(repId: r, timestamp: Date())
        }
        // Tell the coach the iPad just beeped so its PASS button can arm.
        // See DribbleOrPassDisplaySessionView.playBeep for full rationale.
        sendBeepArmed(repIndex: engine.currentRepIndex)
        DispatchQueue.main.async {
            self.repController.openDecisionWindow()
            self.activateAudioSession()
            self.preloadBeepAssetsForInstantReveal()
            PBABeepSoundManager.shared.play(soundEnabled: settingsViewModel.soundEnabled)
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
