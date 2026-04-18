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

private func routeForActivity(_ activity: ActivityKind) -> AppRoute {
    PBASessionFlowPolicy.routeForActivityLaunch(activity)
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
    @State private var audioInterruptionObserver: NSObjectProtocol?
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
    /// Tracks applied coach reps for stale detection (debug); coach index is authoritative when advancing.
    @State private var partnerCoachRepGate = PartnerCoachRepSequenceGate()
    @StateObject private var repController = RepStateController()
    /// Display-side relay (join code, WebSocket, coach paired). Used when `partnerTransportMode == .relayWebSocket`.
    /// Conforms to ``PartnerRelayDisplayControlling``; concrete type is ``PartnerRelayDisplaySession``.
    @ObservedObject private var partnerRelaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
    @State private var showPocketMomentToast = false
    @State private var hasCompletedPassTempoCalibration = false
    @State private var showPassTempoCalibration = false
    @State private var showCalibrationChoicePrompt = false
    @State private var partnerCalibration = PartnerPassTempoCalibrationTracker()
    @State private var showConnectedConfirmation = false
    @State private var hasStartedConnectedToCalibrationTransition = false
    @State private var soloGetReadyVisible = false
    @State private var soloRepFeedback: String?
    @State private var soloCalibrationNudge: String?
    @State private var soloFirstRepScheduled = false
    @State private var startedWithoutSavedCalibration = false
    @State private var justCompletedCalibrationThisSession = false
    @State private var pendingPostCalibrationReinforcementReps = 0
    @State private var shouldShowNoticeDifference = false
    @State private var recentTimingZones: [SoloTimingZone] = []
    @State private var soloGetReadyWorkItem: DispatchWorkItem?
    @State private var soloBeepRushWorkItem: DispatchWorkItem?
    @State private var soloAutoNextRepWorkItem: DispatchWorkItem?
    private static let pocketMomentToastShownKey = "hasShownPocketMomentToast"
    @State private var playerFirstRunGuidanceText: String?
    @State private var playerFirstRunGuidanceOpacity = 0.0
    @State private var playerFirstRunGuidanceTask: Task<Void, Never>?

    private enum SoloTimingZone {
        case early
        case onTime
        case late
    }

    init(config: TwoMinuteTestConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        let repCount = TrainingPartnerConnectionCoordinator.shared.partnerBlockTotalReps(
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
            soloFallback: 10,
            mode: mode
        )
        _engine = StateObject(wrappedValue: TwoMinuteCriticalScanEngine(
            config: config,
            repPlans: TwoMinuteRepPlanner.generatePlan(forBlockSize: repCount)
        ))
    }

    private var blockTotalReps: Int {
        TrainingPartnerConnectionCoordinator.shared.partnerBlockTotalReps(
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
            soloFallback: 10,
            mode: mode
        )
    }

    private var sessionTransportMode: SessionTransportMode {
        PartnerTransportPolicy.transportMode(for: .twoMinute, trainingMode: mode)
    }

    private var isBallVisible: Bool {
        if case .ballVisible = engine.phase { return true }
        return false
    }

    private var sessionStack: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            dribbleOrPassLayout
            statusOverlay
                .opacity(isBallVisible ? 0.25 : 1)
            waitingForCoachOverlay
            repCountOverlay
            if showExitLogButtons, let repIndex = repIndexForExit {
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
            PlayerFirstRunGuidanceToastOverlay(message: playerFirstRunGuidanceText, opacity: playerFirstRunGuidanceOpacity)
                .zIndex(124)
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(125)
            if showPocketMomentToast {
                VStack {
                    Spacer()
                    Text("That was your pocket moment.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        )
                        .cornerRadius(12)
                        .padding(.bottom, 36)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.25), value: showPocketMomentToast)
                .allowsHitTesting(false)
            }
            if let soloRepFeedback {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Text(soloRepFeedback)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        if let soloCalibrationNudge {
                            Text(soloCalibrationNudge)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.82))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .padding(.bottom, 36)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.2), value: soloRepFeedback)
                .allowsHitTesting(false)
                .zIndex(6)
            }
        }
    }

    private var sessionContentWithCover: some View {
        sessionStack
            .contentShape(Rectangle())
            .onTapGesture {
                if mode == .solo { handleWallSoloTrigger() }
            }
            .fullScreenCover(item: $testResultItem) { item in
                NavigationStack(path: $resultsCoverPathHolder.path) {
                    TwoMinuteTestResultsView(
                        result: item.result,
                        repLogs: item.logs,
                        profileManager: profileManager,
                        settingsViewModel: settingsViewModel,
                        onDismissCover: { testResultItem = nil },
                        onStartTraining: { activity in
                            let route = routeForActivity(activity)
                            #if DEBUG
                            print("[PBA-Debug] TwoMinute StartTraining tapped: selectedPlayerId=\(playerStore.selectedPlayerId?.uuidString ?? "nil"), route=\(route)")
                            #endif
                            pendingTrainingRoute = route
                            testResultItem = nil
                        }
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
            .onChange(of: engine.repLogs.count) { _, newCount in
                guard newCount == 1,
                      !UserDefaults.standard.bool(forKey: Self.pocketMomentToastShownKey) else { return }
                UserDefaults.standard.set(true, forKey: Self.pocketMomentToastShownKey)
                showPocketMomentToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    showPocketMomentToast = false
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
    }

    var body: some View {
        sessionContentWithSessionModifiers
            .sessionCountdown(waitForPartnerReady: mode.requiresPhoneDisplayRelay, partnerReady: partnerReadyForCountdown, suppressCoachMessagesDuringCountdown: $blockCoachDrillDuringSessionCountdown)
            .onChange(of: blockCoachDrillDuringSessionCountdown) { old, new in
                guard mode.requiresPhoneDisplayRelay, old == true, new == false else { return }
                flushPendingCoachNextRepAfterCountdown()
            }
            .onChange(of: showPassTempoCalibration) { old, new in
                guard old == true, new == false else { return }
                scheduleSoloFirstRepIfNeeded()
            }
            .onChange(of: showCalibrationChoicePrompt) { old, new in
                guard old == true, new == false else { return }
                scheduleSoloFirstRepIfNeeded()
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
                        pendingPostCalibrationReinforcementReps = 2
                        shouldShowNoticeDifference = startedWithoutSavedCalibration
                    }
                    hasCompletedPassTempoCalibration = true
                    showPassTempoCalibration = false
                }
                .interactiveDismissDisabled()
            }
            .onReceive(NotificationCenter.default.publisher(for: .relayForegroundReconnectCompleted)) { _ in
                guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket else { return }
                engine.synchronizeTimersAfterEnteringForeground()
                PartnerRelayCheckpointDisplaySend.sendIfReady(
                    engine: engine,
                    activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
                    relay: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
                )
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
        }
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
            print("[NEXTREP DEFERRED] buffering until phase=waitingForNextRep")
            pendingNextRepIndex = repIndex
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
        if !repController.acceptIncomingNextRep() {
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

    private func twoMTAllowsPassTrigger(repIndex: Int) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .beepedAwaitingPass(let r, _):
            return r == repIndex
        case .armedScanning(let r, _, _):
            return r == repIndex
        default:
            return false
        }
    }

    private func twoMTAllowsExitLogged(repIndex: Int) -> Bool {
        guard repIndex == engine.currentRepIndex else { return false }
        switch engine.phase {
        case .ballVisible(let r, _, _), .awaitingExitLog(let r, _):
            return r == repIndex
        default:
            return false
        }
    }

    private func twoMTAllowsIncorrectDecision(repIndex: Int) -> Bool {
        twoMTAllowsExitLogged(repIndex: repIndex)
    }

    private func twoMinutePlayerFirstRunGuidanceIfNeeded(oldPhase: CriticalScanPhase, newPhase: CriticalScanPhase) {
        let activityId = ActivityKind.twoMinuteTest.sessionActivityActivityId
        guard !PlayerFirstRunGuidanceStore.hasCompletedFirstRun(activityId: activityId) else { return }
        guard engine.currentRepIndex <= 1 else { return }

        if case .ballVisible(let r, _, _) = newPhase, r == 0 {
            if case .ballVisible(let rOld, _, _) = oldPhase, rOld == 0 { return }
            guard let msg = PlayerFirstRunGuidanceCopy.message(for: .twoMinuteTest, repIndexZeroBased: 0) else { return }
            PlayerFirstRunGuidanceToastAnimator.schedule(
                text: msg,
                task: &playerFirstRunGuidanceTask,
                message: $playerFirstRunGuidanceText,
                opacity: $playerFirstRunGuidanceOpacity
            )
        }
        if case .armedScanning(let r, _, _) = newPhase, r == 1 {
            if case .armedScanning(let rOld, _, _) = oldPhase, rOld == 1 { return }
            guard let msg = PlayerFirstRunGuidanceCopy.message(for: .twoMinuteTest, repIndexZeroBased: 1) else { return }
            PlayerFirstRunGuidanceToastAnimator.schedule(
                text: msg,
                task: &playerFirstRunGuidanceTask,
                message: $playerFirstRunGuidanceText,
                opacity: $playerFirstRunGuidanceOpacity
            )
        }
    }

    private func handlePhaseChange(_ oldPhase: CriticalScanPhase, _ newPhase: CriticalScanPhase) {
        syncRepController(with: newPhase)
        if case .complete = newPhase {
            PlayerFirstRunGuidanceStore.markCompletedFirstRun(activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId)
            pendingNextRepIndex = nil
            DispatchQueue.main.async {
                testResultItem = TwoMinuteResultItem(
                    result: TwoMinuteTestResult.from(logs: engine.repLogs, difficulty: config.difficulty),
                    logs: engine.repLogs
                )
                AnalyticsManager.shared.track(.twoMinuteTestCompleted, playerId: playerStore.selectedPlayerId)
            }
        }
        twoMinutePlayerFirstRunGuidanceIfNeeded(oldPhase: oldPhase, newPhase: newPhase)
        if case .armedScanning(let repIndex, let ballGate, _) = newPhase {
            preloadBeepAssetsForInstantReveal()
            scheduleSoloRushBeepIfNeeded(repIndex: repIndex, ballGate: ballGate)
        }
        if case .beepedAwaitingPass(let repIndex, _) = newPhase {
            playBeep()
            scheduleSoloPassTriggerIfNeeded(repIndex: repIndex)
        }
        if case .waitingForNextRep = newPhase {
            scheduleSoloAutoNextRepIfNeeded()
        }
    }

    private func twoMinuteApplyPassTrigger(repIndex: Int, passTimestamp: Date) {
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
        #if DEBUG
        PartnerPersistDebug.log("TwoMinuteCriticalScanSessionView onAppear")
        #endif
        onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        hasCompletedPassTempoCalibration = false
        showCalibrationChoicePrompt = false
        showPassTempoCalibration = false
        startedWithoutSavedCalibration = !PartnerPassTempoCalibrationStore.hasSavedCalibration
        justCompletedCalibrationThisSession = false
        pendingPostCalibrationReinforcementReps = 0
        shouldShowNoticeDifference = false
        partnerCalibration.reset()
        showConnectedConfirmation = false
        hasStartedConnectedToCalibrationTransition = false
        beginConnectedToCalibrationTransitionIfNeeded()
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
        subscribeToAudioInterruption()
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
        configureCalibrationStartFlowForCurrentMode()
    }

    private func handleOnDisappear() {
        soloGetReadyWorkItem?.cancel()
        soloGetReadyWorkItem = nil
        soloBeepRushWorkItem?.cancel()
        soloBeepRushWorkItem = nil
        soloAutoNextRepWorkItem?.cancel()
        soloAutoNextRepWorkItem = nil
        pendingNextRepIndex = nil
        PlayerFirstRunGuidanceToastAnimator.cancel(
            task: &playerFirstRunGuidanceTask,
            message: $playerFirstRunGuidanceText,
            opacity: $playerFirstRunGuidanceOpacity
        )
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
        unsubscribeFromAudioInterruption()
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

    private func scheduleSoloFirstRepIfNeeded() {
        guard mode == .solo,
              !soloFirstRepScheduled,
              !showPassTempoCalibration,
              !showCalibrationChoicePrompt else { return }
        soloFirstRepScheduled = true
        let showGetReady = !justCompletedCalibrationThisSession
        soloGetReadyVisible = showGetReady
        soloGetReadyWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard engine.phase == .waitingForNextRep else { return }
            soloGetReadyVisible = false
            repController.completeRepCycleEnd()
            repController.startRep()
            engine.onNextRep(repIndex: nextRepIndex)
            justCompletedCalibrationThisSession = false
        }
        soloGetReadyWorkItem = work
        let delay = showGetReady ? 0.8 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleSoloRushBeepIfNeeded(repIndex: Int, ballGate: Gate) {
        guard mode == .solo else { return }
        soloBeepRushWorkItem?.cancel()
        let rushDelay = Double.random(in: 0.14...0.30)
        let work = DispatchWorkItem {
            engine.onBeepFire(repIndex: repIndex, ballGate: ballGate)
        }
        soloBeepRushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + rushDelay, execute: work)
    }

    private func scheduleSoloPassTriggerIfNeeded(repIndex: Int) {
        guard mode == .solo else { return }
        let passDelay = Double.random(in: 0.08...0.22)
        DispatchQueue.main.asyncAfter(deadline: .now() + passDelay) {
            guard case .beepedAwaitingPass(let currentRep, _) = engine.phase, currentRep == repIndex else { return }
            twoMinuteApplyPassTrigger(repIndex: repIndex, passTimestamp: Date())
        }
    }

    private func scheduleSoloAutoNextRepIfNeeded() {
        guard mode == .solo, nextRepIndex < blockTotalReps else { return }
        soloAutoNextRepWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard engine.phase == .waitingForNextRep else { return }
            repController.completeRepCycleEnd()
            repController.startRep()
            engine.onNextRep(repIndex: nextRepIndex)
        }
        soloAutoNextRepWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func handleScenePhaseChange(old: ScenePhase, new: ScenePhase) {
        if new == .background {
            engine.applicationDidEnterBackground()
        } else if new == .active {
            engine.synchronizeTimersAfterEnteringForeground()
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
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .awayFromPressureTrainingModeSelection:
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .awayFromPressureSetup:
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .dribbleOrPassRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassSetup:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingSetup:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        default:
            EmptyView()
        }
    }

    private func handleWallSoloTrigger() {
        switch engine.phase {
        case .waitingForNextRep:
            repController.completeRepCycleEnd()
            guard repController.acceptIncomingNextRep() else { return }
            engine.onNextRep(repIndex: nextRepIndex)
        case .beepedAwaitingPass(repIndex: let ri, ballGate: _):
            guard twoMTAllowsPassTrigger(repIndex: ri) else { return }
            guard !repController.hasLoggedTap else { return }
            repController.registerTap()
            #if DEBUG
            let soloPass = Date()
            DecisionSpeedDebugLog.logSoloDisplayPassTrigger(activity: .twoMinuteTest, repIndex: ri, displayWallPassTS: soloPass)
            twoMinuteApplyPassTrigger(repIndex: ri, passTimestamp: soloPass)
            #else
            twoMinuteApplyPassTrigger(repIndex: ri, passTimestamp: Date())
            #endif
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
            Text(ActivityDisplaySessionCopy.tapTwoMinuteOrDOP)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
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
        guard twoMTAllowsExitLogged(repIndex: repIndex) else { return }
        guard !repController.hasLoggedSwipe else { return }
        var savedLog: RepLog?
        #if DEBUG
        let soloExit = Date()
        DecisionSpeedDebugLog.logSoloDisplayExitTrigger(activity: .twoMinuteTest, repIndex: repIndex, gate: gate, displayWallExitTS: soloExit)
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: soloExit) != nil, let log = engine.repLogs.last {
            repController.registerSwipe()
            syncRepController(with: engine.phase)
            saveDecisionForRep(log: log)
            savedLog = log
        }
        #else
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let log = engine.repLogs.last {
            repController.registerSwipe()
            syncRepController(with: engine.phase)
            saveDecisionForRep(log: log)
            savedLog = log
        }
        #endif
        if let savedLog {
            showSoloRepFeedback(for: savedLog)
        }
        nextRepIndex = repIndex + 1
    }

    private func syncRepController(with phase: CriticalScanPhase) {
        switch phase {
        case .waitingForNextRep:
            repController.completeRepCycleEnd()
        case .armedScanning:
            repController.startRep()
        case .beepedAwaitingPass, .ballVisible:
            repController.openDecisionWindow()
        case .awaitingExitLog:
            // Partner coach may log exit while engine is here — keep swipe acceptance open until `waitingForNextRep`.
            repController.openDecisionWindow()
        case .complete:
            repController.completeRepCycleEnd()
        }
        if mode.requiresPhoneDisplayRelay, case .waitingForNextRep = phase {
            flushPendingPartnerCoachNextRepIfNeeded()
        }
    }

    private func showSoloRepFeedback(for log: RepLog) {
        guard mode == .solo else { return }
        let timing = timingAssessment(for: log)
        appendRecentTimingZone(timing.zone)
        let feedback = soloRepFeedbackText(for: log, timing: timing)
        soloRepFeedback = feedback
        soloCalibrationNudge = postCalibrationReinforcementText(for: log)
            ?? (shouldShowCalibrationNudgeThisRep() ? "Improve accuracy with quick calibration" : nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if soloRepFeedback == feedback {
                soloRepFeedback = nil
                soloCalibrationNudge = nil
            }
        }
    }

    private func shouldShowCalibrationNudgeThisRep() -> Bool {
        guard !PartnerPassTempoCalibrationStore.hasSavedCalibration else { return false }
        // Keep this occasional: roughly 1 out of 4 reps once feedback is already shown.
        return Int.random(in: 0..<4) == 0
    }

    private func postCalibrationReinforcementText(for log: RepLog) -> String? {
        guard pendingPostCalibrationReinforcementReps > 0 else { return nil }
        pendingPostCalibrationReinforcementReps -= 1
        let travelTime = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
        let reactionTime = max(0, log.exitLoggedAt.timeIntervalSince(log.passTriggeredAt ?? log.infoShownAt))
        let decisionWindowSeconds = travelTime - reactionTime
        if shouldShowNoticeDifference {
            shouldShowNoticeDifference = false
            return "Notice the difference?"
        }
        if log.correct, decisionWindowSeconds >= 0 {
            return "That’s it — right on time"
        }
        return "Close — that timing is now exact"
    }

    private func appendRecentTimingZone(_ zone: SoloTimingZone) {
        recentTimingZones.append(zone)
        if recentTimingZones.count > 3 {
            recentTimingZones.removeFirst(recentTimingZones.count - 3)
        }
    }

    private func timingAssessment(for log: RepLog) -> (zone: SoloTimingZone, ratio: Double, isBorderline: Bool) {
        let travelTime = max(
            0.01,
            CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
                ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
        )
        let decisionTime = max(0, log.exitLoggedAt.timeIntervalSince(log.passTriggeredAt ?? log.infoShownAt))
        let ratio = decisionTime / travelTime

        let earlyThreshold = 0.75
        let lateThreshold = PartnerPassTempoCalibrationStore.hasSavedCalibration ? 1.15 : 1.20
        let borderlineLateSlack = 0.05

        if ratio < earlyThreshold { return (.early, ratio, false) }
        if ratio <= lateThreshold { return (.onTime, ratio, false) }
        // Fairness: borderline reps are treated as on-time, not late.
        if ratio <= lateThreshold + borderlineLateSlack { return (.onTime, ratio, true) }
        return (.late, ratio, false)
    }

    private func soloRepFeedbackText(for log: RepLog, timing: (zone: SoloTimingZone, ratio: Double, isBorderline: Bool)) -> String {
        if log.correct, timing.zone == .early {
            return "Excellent — early and correct"
        }
        if !log.correct, timing.zone != .late {
            return "Good early decision — now choose the right option"
        }

        let lateCountInRecent = recentTimingZones.filter { $0 == .late }.count
        let hasMixedPattern = Set(recentTimingZones.map {
            switch $0 {
            case .early: return "early"
            case .onTime: return "onTime"
            case .late: return "late"
            }
        }).count >= 2

        if timing.isBorderline || (hasMixedPattern && lateCountInRecent < 2) {
            return "Close — decide a bit earlier"
        }
        if lateCountInRecent >= 2 {
            return "Late — decide earlier"
        }
        return "Close — decide a bit earlier"
    }

    private func saveDecisionForRep(log: RepLog) {
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

    /// Same layout as Dribble or Pass: center "X" marker, no players. Ball at one of four slots when visible.
    private var dribbleOrPassLayout: some View {
        GeometryReader { geo in
            let ballSide = TwoMinuteSlotPositions.ballSideLength(in: geo.size, safeAreaInsets: geo.safeAreaInsets)
            let positions = TwoMinuteSlotPositions.positions(in: geo.size, safeAreaInsets: geo.safeAreaInsets, ballSideLength: ballSide)
            let center = TwoMinuteSlotPositions.centerPosition(in: geo.size, safeAreaInsets: geo.safeAreaInsets, ballSideLength: ballSide)

            ZStack {
                // Center marker (same as Dribble or Pass)
                VStack(spacing: 10) {
                    Text("X")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                }
                .position(x: center.x, y: center.y)

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
            .offset(y: PartnerDisplayLayout.drillFocalCenterYOffset)
        }
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
        soloFirstRepScheduled = false
        if !PBASessionFlowPolicy.shouldPromptCalibration(for: mode),
           let calibrated = PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds() {
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(calibrated)
            showCalibrationChoicePrompt = false
            showPassTempoCalibration = false
            scheduleSoloFirstRepIfNeeded()
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
                        activityTitle: "2-Minute Test",
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
        VStack {
            if !mode.requiresPhoneDisplayRelay {
                Text("Tap screen to trigger")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                phaseStatusContent
            }
            .padding(.bottom, 32)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var phaseStatusContent: some View {
        if mode == .solo, soloGetReadyVisible {
            phaseVStack(title: "Get ready...", subtitle: "Session starts now")
        } else
        if shouldShowWaitingForCoachOverlay {
            EmptyView()
        } else {
            switch engine.phase {
            case .waitingForNextRep:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(
                        title: "Scan",
                        subtitle: "Waiting for coach..."
                    )
                } else {
                    phaseVStack(title: "Waiting for coach…", subtitle: "Keep moving. Check both shoulders.")
                }
            case .armedScanning:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(
                        title: "Scan",
                        subtitle: "Check surroundings early.\nRecognize the open gate."
                    )
                } else {
                    phaseVStack(title: "Scan early", subtitle: "Know your decision.")
                }
            case .beepedAwaitingPass:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(title: "Ball is coming", subtitle: "")
                } else {
                    phaseVStack(title: "Ball is coming", subtitle: "Swipe your decision as soon as the ball arrives.")
                }
            case .awaitingExitLog:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(title: "Swipe now", subtitle: "Coach: log the swipe direction that matches the ball.")
                } else {
                    phaseVStack(title: "Swipe now", subtitle: "Waiting for coach swipe log…")
                }
            default:
                Text(phaseStatusText)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
    }

    private func phaseVStack(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
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

    private var phaseStatusText: String {
        switch engine.phase {
        case .waitingForNextRep: return "Waiting for coach…"
        case .armedScanning(_, _, let endsAt):
            let sec = max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up)))
            if sec > 0 { return "Scan freely — beep in \(sec)s" }
            return "Scan freely"
        case .beepedAwaitingPass: return "Ball is coming — swipe your decision as it arrives"
        case .ballVisible: return ""
        case .awaitingExitLog: return "Waiting for coach swipe log…"
        case .complete: return ""
        }
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
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
            PBABeepSoundManager.shared.play(soundEnabled: settingsViewModel.soundEnabled)
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

    private func subscribeToAudioInterruption() {
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .ended {
                self.activateAudioSession()
            }
        }
    }

    private func unsubscribeFromAudioInterruption() {
        if let observer = audioInterruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            audioInterruptionObserver = nil
        }
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
