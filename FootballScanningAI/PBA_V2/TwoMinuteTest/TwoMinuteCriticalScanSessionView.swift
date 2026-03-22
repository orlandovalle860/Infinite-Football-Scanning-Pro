//
//  TwoMinuteCriticalScanSessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Display: same layout as Dribble or Pass (center X, four slots). Ball appears at one slot when coach triggers (PASS/volume).
//

import SwiftUI
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
    /// Partner relay path (DEBUG): WebSocket transport for display; same message path as Multipeer via NotificationCenter.
    @State private var relayWebSocketTransport: WebSocketRemoteTransport?
    /// Relay join code from POST /v1/sessions (shown when using relay).
    @State private var relayDisplayJoinCode: String?
    /// Mirror relay socket state for status UI when partner uses relay transport.
    @State private var relayWebSocketConnectionState: ConnectionState = .disconnected

    init(config: TwoMinuteTestConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _engine = StateObject(wrappedValue: TwoMinuteCriticalScanEngine(config: config))
    }

    private static let totalReps = 10

    /// Two Minute partner transport: DEBUG uses relay WebSocket; Release uses Multipeer. Evaluated once (not per view body).
    private static let partnerTransportMode: SessionTransportMode = {
        #if DEBUG
        return .relayWebSocket
        #else
        return .multipeer
        #endif
    }()

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
            if mode == .partner {
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
            .onChange(of: connectionManager.connectedPeerName, handleConnectedPeerChange)
            .onChange(of: relayWebSocketConnectionState, handleRelayConnectionStateChange)
            .preferredColorScheme(.dark)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { leaveToolbarItem }
            .alert("Leave training?", isPresented: $showLeaveAlert) {
                Button("Stay", role: .cancel) {}
                Button("Leave", role: .destructive) { router.popToRoot() }
            } message: {
                Text("Your current block will not be saved.")
            }
            .sessionCountdown()
    }

    private func handleTwoMinuteMessage(_ notification: Notification) {
        guard mode == .partner, let msg = notification.object as? TwoMinuteMessage else { return }
        switch msg {
        case .nextRep(let repIndex):
            guard sessionManager.isConnected else { return }
            engine.onNextRep(repIndex: repIndex)
        case .passTriggered(let repIndex, let timestamp):
            engine.onPassTrigger(repIndex: repIndex, timestamp: timestamp)
        case .exitLogged(let repIndex, let gate, let timestamp):
            if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                saveDecisionForRep(log: log)
            }
        case .incorrectDecision(let repIndex, let timestamp):
            if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                saveDecisionForRep(log: log)
            }
        case .firstTouchLogged:
            break
        case .coachPaired:
            break
        case .sessionEnded:
            break
        }
    }

    private func handlePhaseChange(_ oldPhase: CriticalScanPhase, _ newPhase: CriticalScanPhase) {
        if case .complete = newPhase {
            DispatchQueue.main.async {
                testResultItem = TwoMinuteResultItem(
                    result: TwoMinuteTestResult.from(logs: engine.repLogs, difficulty: config.difficulty),
                    logs: engine.repLogs
                )
                AnalyticsManager.shared.track(.twoMinuteTestCompleted, playerId: playerStore.selectedPlayerId)
            }
        }
        if case .beepedAwaitingPass = newPhase { playBeep() }
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
        onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        hasSentSessionEnded = false
        if mode == .partner, Self.partnerTransportMode == .multipeer {
            connectionManager.startHosting()
        }
        activateAudioSession()
        subscribeToAudioInterruption()
        AnalyticsManager.shared.track(.twoMinuteTestStarted, playerId: playerStore.selectedPlayerId)
        Task {
            await sessionManager.startSession(
                activity: .twoMinuteTest,
                blockSize: Self.totalReps,
                playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
            )
        }
        #if DEBUG
        if mode == .partner, Self.partnerTransportMode == .relayWebSocket {
            print("[RelayWS-DEBUG] about to start relay partner session")
            Task { await startRelayWebSocketPartnerSession() }
        }
        #endif
    }

    private func handleOnDisappear() {
        #if DEBUG
        relayWebSocketTransport?.disconnect()
        relayWebSocketTransport = nil
        relayDisplayJoinCode = nil
        relayWebSocketConnectionState = .disconnected
        #endif
        if mode == .partner {
            sendSessionEndedIfNeeded()
            if Self.partnerTransportMode == .multipeer {
                connectionManager.stopHosting()
            }
        }
        unsubscribeFromAudioInterruption()
        sessionManager.clear()
        if testResultItem == nil { currentSessionStore.clear() }
    }

    private func handleScenePhaseChange(old: ScenePhase, new: ScenePhase) {
        if new == .background { engine.applicationDidEnterBackground() }
    }

    private func handleConnectedPeerChange(old: String?, name: String?) {
        guard mode == .partner, Self.partnerTransportMode == .multipeer, name != nil else { return }
        sessionManager.setConnected(true)
        let flag = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
        connectionManager.sendDisplaySessionInfo(hasCompletedInitialTest: flag)
    }

    private func handleRelayConnectionStateChange(old: ConnectionState, new: ConnectionState) {
        #if DEBUG
        guard mode == .partner, Self.partnerTransportMode == .relayWebSocket else { return }
        if new == .disconnected {
            sessionManager.setConnected(false)
        }
        #endif
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
            engine.onPassTrigger(repIndex: ri, timestamp: Date())
        default:
            break
        }
    }

    private var showExitLogButtons: Bool {
        guard mode != .partner else { return false }
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
            Text("Tap your exit direction")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
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
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let log = engine.repLogs.last {
            saveDecisionForRep(log: log)
        }
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
            let positions = TwoMinuteSlotPositions.positions(in: geo.size, safeAreaInsets: geo.safeAreaInsets)
            let center = TwoMinuteSlotPositions.centerPosition(in: geo.size)

            ZStack {
                // Center marker (same as Dribble or Pass)
                VStack(spacing: 10) {
                    Text("X")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                }
                .position(x: center.x, y: center.y)

                // Soccer ball at gate position when visible (same slots as where defenders/teammates would be)
                if case .ballVisible(_, let ballGate, _) = engine.phase,
                   let pt = positions[ballGate] {
                    Image("SoccerBall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .shadow(radius: 4)
                        .position(x: pt.x, y: pt.y)
                        .zIndex(1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var twoMinutePartnerConnectionState: ConnectionState {
        guard mode == .partner else { return connectionManager.connectionState }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            // Do not treat “relay WebSocket open” as coach paired — only `peer_joined` sets sessionManager connected.
            if relayWebSocketConnectionState == .disconnected {
                return .disconnected
            }
            if sessionManager.isConnected {
                return .connected
            }
            return .connecting
        }
        #endif
        return connectionManager.connectionState
    }

    private var connectionStatusContent: some View {
        Group {
            if mode == .partner {
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
        guard mode == .partner else { return false }
        return !sessionManager.isConnected
    }

    private var waitingForCoachOverlay: some View {
        Group {
            if shouldShowWaitingForCoachOverlay {
                if sessionManager.isCreating {
                    VStack(spacing: 12) {
                        #if DEBUG
                        relayJoinCodeOnScreenBanner
                        #endif
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
                        #if DEBUG
                        relayJoinCodeOnScreenBanner
                        #endif
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
                        #if DEBUG
                        relayJoinCodeOnScreenBanner
                        #endif
                        VStack(spacing: 8) {
                            if Self.partnerTransportMode == .relayWebSocket {
                                Text("Waiting for Coach (Relay)…")
                                    .font(.title3.weight(.medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("Enter the join code on the coach device")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            } else {
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
                    }
                    .padding(.top, 200)
                    .allowsHitTesting(false)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    #if DEBUG
    @ViewBuilder
    private var relayJoinCodeOnScreenBanner: some View {
        if let code = relayDisplayJoinCode {
            VStack(spacing: 6) {
                Text("Relay join code")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.cyan.opacity(0.9))
                Text(code)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(12)
                Text("Enter on coach iPhone: Relay DEBUG")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 4)
        }
    }
    #endif

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
            if Self.partnerTransportMode == .relayWebSocket {
                phaseVStack(title: "Waiting for Coach (Relay)…", subtitle: "Enter the join code on the coach device")
            } else {
                phaseVStack(title: "Waiting for Coach Remote…", subtitle: "On the coach device: tap Connect to Display, then select this device.")
            }
        } else {
            switch engine.phase {
            case .waitingForNextRep:
                phaseVStack(title: "Waiting for coach…", subtitle: "Keep moving. Check both shoulders.")
            case .armedScanning:
                phaseVStack(title: "Keep moving. Check both shoulders.", subtitle: "Beep is coming.")
            case .beepedAwaitingPass:
                phaseVStack(title: "Ball is coming. Check again.", subtitle: "Coach: press PASS when it leaves your foot.")
            case .awaitingExitLog:
                phaseVStack(title: "Play the rep.", subtitle: "Waiting for coach log…")
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
            if mode != .partner || sessionManager.isConnected {
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
        if mode == .partner, !sessionManager.isConnected {
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

    private func playBeep() {
        DispatchQueue.main.async {
            self.activateAudioSession()
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
        #if DEBUG
        if mode == .partner, Self.partnerTransportMode == .relayWebSocket {
            relayWebSocketTransport?.send(.sessionEnded(timestamp: Date()))
            return
        }
        #endif
        connectionManager.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
    }

    #if DEBUG
    /// Partner relay: HTTP create session + WebSocket display role. `TwoMinuteMessage` delivery matches Multipeer via `NotificationCenter`.
    private func startRelayWebSocketPartnerSession() async {
        print("[RelayWS-DEBUG] startRelayWebSocketPartnerSession entered")
        guard mode == .partner else { return }
        do {
            let created = try await WebSocketSessionAPI.createSession()
            await MainActor.run {
                relayDisplayJoinCode = created.joinCode
            }
            print("[RelayWS-DEBUG] session creation OK sessionId=\(created.sessionId)")
            print("[RelayWS-DEBUG] joinCode=\(created.joinCode) (share with coach for relay join)")
            print("[RelayWS-DEBUG] wsUrl(base)=\(created.wsUrl) expiresAt=\(created.expiresAt ?? "nil")")

            let wsURL = try created.webSocketURLForDisplay()
            print("[RelayWS-DEBUG] WebSocket URL (with query)=\(wsURL.absoluteString)")

            let config = WebSocketSessionConfig(url: wsURL, sessionId: created.sessionId, authToken: created.displayToken)
            let transport = WebSocketRemoteTransport(config: config)
            transport.onConnectionStateChanged = { state in
                Task { @MainActor in
                    relayWebSocketConnectionState = state
                }
                switch state {
                case .searching:
                    print("[RelayWS-DEBUG] connection state: searching")
                case .connecting:
                    print("[RelayWS-DEBUG] connection state: connecting")
                case .connected:
                    print("[RelayWS-DEBUG] connection state: connected")
                case .disconnected:
                    print("[RelayWS-DEBUG] connection state: disconnected")
                }
            }
            transport.onRawTextReceived = { text in
                print("[RelayWS-DEBUG] received raw: \(text)")
                if text.contains("peer_joined") {
                    Task { @MainActor in
                        sessionManager.setConnected(true)
                    }
                }
            }

            await MainActor.run {
                relayWebSocketTransport = transport
                print("[RelayWS-DEBUG] calling connect()")
                transport.connect()
            }
        } catch {
            print("[RelayWS-DEBUG] relay session/WebSocket setup failed: \(error)")
        }
    }
    #endif
}
