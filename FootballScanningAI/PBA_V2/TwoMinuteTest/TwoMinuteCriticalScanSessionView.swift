//
//  TwoMinuteCriticalScanSessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Display: same layout as Dribble or Pass (center X, four slots). Ball appears at one slot when coach triggers (PASS/volume).
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
    switch activity {
    case .twoMinuteTest: return .twoMinuteRoleSelection
    case .awayFromPressure: return .awayFromPressureRoleSelection
    case .dribbleOrPass: return .dribbleOrPassRoleSelection
    case .oneTouchPassing: return .oneTouchPassingRoleSelection
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var testResultItem: TwoMinuteResultItem?
    @State private var showLeaveAlert = false
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
    /// Coach `nextRep` received during the countdown (otherwise dropped); applied when the overlay dismisses.
    @State private var pendingCoachNextRepWhileCountdown: Int?
    /// Display-side relay (join code, WebSocket, coach paired). Used when `partnerTransportMode == .relayWebSocket`.
    /// Conforms to ``PartnerRelayDisplayControlling``; concrete type is ``PartnerRelayDisplaySession``.
    @ObservedObject private var partnerRelaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession

    init(config: TwoMinuteTestConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _engine = StateObject(wrappedValue: TwoMinuteCriticalScanEngine(config: config))
    }

    private static let totalReps = 10

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
            if mode != .partner {
                SessionVolumeTriggerView(enabled: canVolumeTrigger) { handleWallSoloTrigger() }
                    .allowsHitTesting(false)
            }
            if showExitLogButtons, let repIndex = repIndexForExit {
                twoMinuteExitLogOverlay(repIndex: repIndex)
                    .zIndex(2)
            }
            if mode.requiresPhoneDisplayRelay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }
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

    var body: some View {
        sessionContentWithCover
            .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main), perform: handleTwoMinuteMessage)
            .onChange(of: engine.phase, handlePhaseChange)
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
            .preferredColorScheme(.dark)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { leaveToolbarItem }
            .alert("Leave training?", isPresented: $showLeaveAlert) {
                Button("Stay", role: .cancel) {}
                Button("Leave", role: .destructive) { router.popToRoot(endingPartnerSession: false) }
            } message: {
                Text("Your current block will not be saved.")
            }
            .sessionCountdown(waitForPartnerReady: mode.requiresPhoneDisplayRelay, partnerReady: partnerReadyForCountdown, suppressCoachMessagesDuringCountdown: $blockCoachDrillDuringSessionCountdown)
            .onChange(of: blockCoachDrillDuringSessionCountdown) { old, new in
                guard mode.requiresPhoneDisplayRelay, old == true, new == false else { return }
                flushPendingCoachNextRepAfterCountdown()
            }
    }

    private func handleTwoMinuteMessage(_ notification: Notification) {
        guard mode.requiresPhoneDisplayRelay, let msg = notification.object as? TwoMinuteMessage else { return }
        if PartnerCountdownCoachMessagePolicy.shouldDeferWhileCountdown(
            msg: msg,
            isBlockingDrillMessagesFromCoach: blockCoachDrillDuringSessionCountdown,
            pendingNextRepIndex: &pendingCoachNextRepWhileCountdown
        ) {
            return
        }
        switch msg {
        case .nextRep(let repIndex):
            pendingCoachNextRepWhileCountdown = nil
            guard sessionManager.isConnected else { return }
            engine.onNextRep(repIndex: repIndex)
        case .passTriggered(let repIndex, let timestamp):
            #if DEBUG
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .twoMinuteTest, kind: "passTriggered", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            #endif
            twoMinuteApplyPassTrigger(repIndex: repIndex, passTimestamp: timestamp)
        case .exitLogged(let repIndex, let gate, let timestamp):
            #if DEBUG
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .twoMinuteTest, kind: "exitLogged", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .twoMinuteTest, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "exitLogged")
            #endif
            if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                saveDecisionForRep(log: log)
            }
        case .incorrectDecision(let repIndex, let timestamp):
            #if DEBUG
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .twoMinuteTest, kind: "incorrectDecision", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            let wallBeforeEngine = Date()
            DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .twoMinuteTest, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "incorrectDecision")
            #endif
            if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let log = engine.repLogs.last {
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
        }
    }

    private func flushPendingCoachNextRepAfterCountdown() {
        guard let idx = pendingCoachNextRepWhileCountdown else { return }
        pendingCoachNextRepWhileCountdown = nil
        guard sessionManager.isConnected else { return }
        engine.onNextRep(repIndex: idx)
    }

    private func handlePhaseChange(_: CriticalScanPhase, _ newPhase: CriticalScanPhase) {
        if case .complete = newPhase {
            DispatchQueue.main.async {
                testResultItem = TwoMinuteResultItem(
                    result: TwoMinuteTestResult.from(logs: engine.repLogs, difficulty: config.difficulty),
                    logs: engine.repLogs
                )
                AnalyticsManager.shared.track(.twoMinuteTestCompleted, playerId: playerStore.selectedPlayerId)
            }
        }
        if case .armedScanning = newPhase {
            preloadBeepAssetsForInstantReveal()
        }
        if case .beepedAwaitingPass = newPhase { playBeep() }
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
                blockSize: Self.totalReps,
                playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
            )
        }
    }

    private func handleOnDisappear() {
        pendingCoachNextRepWhileCountdown = nil
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

    private func handleScenePhaseChange(old: ScenePhase, new: ScenePhase) {
        if new == .background {
            engine.applicationDidEnterBackground()
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
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .awayFromPressureTrainingModeSelection:
            TrainingModeSelectionView(activityTitle: "Playing Away From Pressure", onSelectMode: { mode in
                pathHolder.push(.awayFromPressureSetup(mode: mode))
            }) { _ in EmptyView() }
        case .awayFromPressureSetup(let mode):
            AwayFromPressureSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .dribbleOrPassRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                TrainingModeSelectionView(activityTitle: "Dribble or Pass", onSelectMode: { mode in
                    pathHolder.push(.dribbleOrPassSetup(mode: mode))
                }) { _ in EmptyView() }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassSetup(let mode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                DribbleOrPassSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                TrainingModeSelectionView(activityTitle: "One-Touch Passing", onSelectMode: { mode in
                    pathHolder.push(.oneTouchPassingSetup(mode: mode))
                }) { _ in EmptyView() }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingSetup(let mode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                OneTouchPassingSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        default:
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var leaveToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showLeaveAlert = true } label: {
                Image(systemName: "house.fill")
            }
            .foregroundColor(.white.opacity(0.9))
        }
    }

    private var canVolumeTrigger: Bool {
        switch engine.phase {
        case .waitingForNextRep, .beepedAwaitingPass: return true
        default: return false
        }
    }

    private func handleWallSoloTrigger() {
        switch engine.phase {
        case .waitingForNextRep:
            engine.onNextRep(repIndex: nextRepIndex)
        case .beepedAwaitingPass(repIndex: let ri, ballGate: _):
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
        #if DEBUG
        let soloExit = Date()
        DecisionSpeedDebugLog.logSoloDisplayExitTrigger(activity: .twoMinuteTest, repIndex: repIndex, gate: gate, displayWallExitTS: soloExit)
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: soloExit) != nil, let log = engine.repLogs.last {
            saveDecisionForRep(log: log)
        }
        #else
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let log = engine.repLogs.last {
            saveDecisionForRep(log: log)
        }
        #endif
        nextRepIndex = repIndex + 1
    }

    private func saveDecisionForRep(log: RepLog) {
        guard let sessionId = CurrentSessionStore.shared.sessionId,
              let passTriggeredAt = log.passTriggeredAt else { return }
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
        }
        // Full-screen geometry + `safeAreaInsets` so slot math matches the physical display (esp. landscape iPad).
        .ignoresSafeArea()
    }

    private var twoMinutePartnerConnectionState: ConnectionState {
        guard mode.requiresPhoneDisplayRelay else { return connectionManager.connectionState }
        if sessionTransportMode == .relayWebSocket {
            // Do not treat “relay WebSocket open” as coach paired — only `peer_joined` sets relay paired state.
            return PartnerRelayDisplayUI.statusConnectionState(
                socketState: partnerRelaySession.socketConnectionState,
                isCoachPairedWithRelay: partnerRelaySession.isCoachPaired
            )
        }
        return connectionManager.connectionState
    }

    private var connectionStatusContent: some View {
        Group {
            if mode.requiresPhoneDisplayRelay {
                CoachRemoteConnectionStatusView(connectionState: twoMinutePartnerConnectionState)
            } else {
                Text(mode == .solo ? "Tap screen or volume to trigger" : "Volume button to trigger")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    /// Partner “waiting for coach” overlay: show until the coach is paired (Multipeer peer or relay `peer_joined`).
    private var shouldShowWaitingForCoachOverlay: Bool {
        guard mode.requiresPhoneDisplayRelay else { return false }
        if sessionTransportMode == .relayWebSocket {
            return !partnerRelaySession.isCoachPaired
        }
        return !sessionManager.isConnected
    }

    /// Partner: 3–2–1–Go only after coach is connected (same signal as waiting overlay). Solo: always ready.
    private var partnerReadyForCountdown: Bool {
        guard mode.requiresPhoneDisplayRelay else { return true }
        if sessionTransportMode == .relayWebSocket {
            return partnerRelaySession.isCoachPaired
        }
        return sessionManager.isConnected
    }

    private var waitingForCoachOverlay: some View {
        Group {
            if shouldShowWaitingForCoachOverlay {
                if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                    PartnerRelayDisplayWaitingWithSessionErrorOverlay(
                        joinCode: partnerRelaySession.joinCode,
                        isDatabaseSessionCreating: sessionManager.isCreating,
                        databaseSessionError: sessionManager.creationError,
                        onRetryDatabaseSession: {
                            Task {
                                await sessionManager.startSession(
                                    activity: .twoMinuteTest,
                                    blockSize: Self.totalReps,
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
                                    blockSize: Self.totalReps,
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
        guard shouldShowWaitingForCoachOverlay else { return false }
        if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket,
           let err = sessionManager.creationError, !err.isEmpty {
            return true
        }
        return false
    }

    private var statusOverlay: some View {
        VStack {
            connectionStatusContent
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                phaseStatusContent
            }
            .padding(.bottom, 32)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var phaseStatusContent: some View {
        if shouldShowWaitingForCoachOverlay {
            if sessionTransportMode == .relayWebSocket {
                phaseVStack(title: "Waiting for Coach (Relay)…", subtitle: "Enter the join code on the coach device")
            } else {
                phaseVStack(title: "Waiting for Coach Remote…", subtitle: "On the coach device: tap Connect to Display, then select this device.")
            }
        } else {
            switch engine.phase {
            case .waitingForNextRep:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(
                        title: "Waiting for coach…",
                        subtitle: "\(ActivityInstructionData.partnerCoachSetupLine)\n\(ActivityInstructionData.partnerCoachBallLine)"
                    )
                } else {
                    phaseVStack(title: "Waiting for coach…", subtitle: "Keep moving. Check both shoulders.")
                }
            case .armedScanning:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(
                        title: "Scan",
                        subtitle: "\(ActivityInstructionData.partnerPlayerBeepLine)\n\(ActivityInstructionData.timingLine)"
                    )
                } else {
                    phaseVStack(title: "Keep moving. Check both shoulders.", subtitle: "Beep is coming.")
                }
            case .beepedAwaitingPass:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(title: "Ball is coming", subtitle: ActivityInstructionData.partnerCoachPassTimingLine)
                } else {
                    phaseVStack(title: "Ball is coming. Check again.", subtitle: "Coach: press PASS when it leaves your foot.")
                }
            case .awaitingExitLog:
                if mode.requiresPhoneDisplayRelay {
                    phaseVStack(title: "Play the rep.", subtitle: "Coach: log the direction that matches the ball (first decision).")
                } else {
                    phaseVStack(title: "Play the rep.", subtitle: "Waiting for coach log…")
                }
            default:
                Text(phaseStatusText)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func phaseVStack(title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    /// Rep count and timer visible only after connection event (State 2). Hidden in State 1 (waiting for pairing).
    private var repCountOverlay: some View {
        Group {
            if !mode.requiresPhoneDisplayRelay || sessionManager.isConnected {
                VStack {
                    HStack {
                        Text(repCountText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var repCountText: String {
        let rep: String
        if mode.requiresPhoneDisplayRelay, !sessionManager.isConnected {
            rep = "—"
        } else {
            switch engine.phase {
            case .waitingForNextRep: rep = "\(nextRepIndex + 1)"
            case .complete: rep = "\(Self.totalReps)"
            case .armedScanning(let r, _, _), .beepedAwaitingPass(let r, _), .ballVisible(let r, _, _), .awaitingExitLog(let r, _):
                rep = "\(r + 1)"
            }
        }
        return "Rep \(rep) of \(Self.totalReps)"
    }

    private var phaseStatusText: String {
        switch engine.phase {
        case .waitingForNextRep: return "Waiting for coach…"
        case .armedScanning(_, _, let endsAt):
            let sec = max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up)))
            if sec > 0 { return "Scan freely — beep in \(sec)s" }
            return "Scan freely"
        case .beepedAwaitingPass: return "Ball is coming — tap PASS on phone"
        case .ballVisible: return ""
        case .awaitingExitLog: return "Waiting for coach log…"
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
        if case .beepedAwaitingPass(let r, _) = engine.phase {
            PBAFlowDebugLog.beep(repId: r, timestamp: Date())
        }
        DispatchQueue.main.async {
            self.activateAudioSession()
            self.preloadBeepAssetsForInstantReveal()
            PBABeepSoundManager.shared.play(soundEnabled: settingsViewModel.soundEnabled)
        }
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

}
