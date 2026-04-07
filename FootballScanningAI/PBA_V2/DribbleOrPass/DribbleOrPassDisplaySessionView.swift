//
//  DribbleOrPassDisplaySessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Same layout as 2-min/AFP; gates show red/green/empty after PASS.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine

struct DribbleOrPassDisplaySessionView: View {
    let config: DribbleOrPassConfig
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @StateObject private var engine: DribbleOrPassEngine
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigateToBlockSummary = false
    @State private var showLeaveAlert = false
    @State private var nextRepIndex = 0
    @State private var audioInterruptionObserver: NSObjectProtocol?
    @State private var hasSentSessionEnded = false
    /// True while ``SessionCountdownModifier`` shows 3–2–1–Go; coach drill messages must not advance the engine until the drill is visible.
    @State private var blockCoachDrillDuringSessionCountdown = false
    @State private var pendingCoachNextRepWhileCountdown: Int?
    /// Red opponent wedge: same adaptive style as Playing Away From Pressure (`WedgeDifficultyEngine`).
    @State private var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    /// Display-side relay (join code, WebSocket, coach paired). Shared across partner activities in one training session.
    @ObservedObject private var partnerRelaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession

    private var sessionTransportMode: SessionTransportMode {
        PartnerTransportPolicy.transportMode(for: .dribbleOrPass, trainingMode: mode)
    }

    init(config: DribbleOrPassConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _engine = StateObject(wrappedValue: DribbleOrPassEngine(config: config, trainingMode: mode))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            layoutWithGates
            statusOverlay
                .opacity(statusOverlayOpacity)
            repCountOverlay
            if mode != .partner {
                SessionVolumeTriggerView(enabled: canVolumeTrigger) { handleWallSoloTrigger() }
                    .allowsHitTesting(false)
            }
            if showExitLogButtons, let repIndex = repIndexForExit {
                exitLogOverlay(repIndex: repIndex)
                    .zIndex(2)
            }
            waitingForCoachRelayOverlay
            if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if mode == .solo { handleWallSoloTrigger() }
        }
        .navigationDestination(isPresented: $navigateToBlockSummary) {
            DribbleOrPassBlockSummaryView(results: engine.repResults, config: config, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main)) { notification in
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
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    if !partnerRelaySession.isCoachPaired {
                        dopRelayDisplayLog("incoming nextRep repIndex=\(repIndex) while isCoachPaired=false (still applying — relay UI can lag peer_joined)")
                    }
                    dopRelayDisplayLog("incoming nextRep repIndex=\(repIndex)")
                }
                #endif
                engine.onNextRep(repIndex: repIndex)
            case .passTriggered(let repIndex, let timestamp):
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    dopRelayDisplayLog("incoming passTriggered repIndex=\(repIndex)")
                }
                let displayReceiveWall = Date()
                DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .dribbleOrPass, kind: "passTriggered", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
                #endif
                dopApplyPassTrigger(repIndex: repIndex, passTimestamp: timestamp)
            case .exitLogged(let repIndex, let gate, let timestamp):
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    dopRelayDisplayLog("incoming exitLogged repIndex=\(repIndex) gate=\(gate)")
                }
                let displayReceiveWall = Date()
                DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .dribbleOrPass, kind: "exitLogged", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
                let wallBeforeEngine = Date()
                DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .dribbleOrPass, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "exitLogged")
                #endif
                if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let result = engine.repResults.last {
                    saveDecisionForRep(result: result)
                }
            case .firstTouchLogged(let repIndex, let gate, let timestamp):
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    dopRelayDisplayLog("incoming firstTouchLogged repIndex=\(repIndex) gate=\(gate)")
                }
                #endif
                engine.onFirstTouchLogged(repIndex: repIndex, gate: gate, timestamp: timestamp)
            case .incorrectDecision(let repIndex, let timestamp):
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    dopRelayDisplayLog("incoming incorrectDecision repIndex=\(repIndex)")
                }
                let displayReceiveWall = Date()
                DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .dribbleOrPass, kind: "incorrectDecision", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
                let wallBeforeEngine = Date()
                DecisionSpeedDebugLog.logDisplayBeforeEngineExit(activity: .dribbleOrPass, repIndex: repIndex, embeddedDirection: timestamp, displayWallBeforeEngine: wallBeforeEngine, kind: "incorrectDecision")
                #endif
                if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let result = engine.repResults.last {
                    saveDecisionForRep(result: result)
                }
            case .coachPaired:
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    dopRelayDisplayLog("incoming coachPaired (envelope; DOP engine no-op)")
                }
                #endif
                break
            case .sessionEnded:
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    dopRelayDisplayLog("sessionEnded received")
                }
                #endif
                break
            case .partnerTrainingEnded:
                #if DEBUG
                if sessionTransportMode == .relayWebSocket {
                    dopRelayDisplayLog("partnerTrainingEnded received (coordinator also tears down relay)")
                }
                #endif
                break
            case .partnerSessionCheckpoint:
                break
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            if case .blockComplete = newPhase {
                DispatchQueue.main.async { navigateToBlockSummary = true }
            }
            if case .armedScanning = newPhase {
                preloadBeepAssetsForInstantReveal()
            }
            if case .beepedAwaitingPass = newPhase { playBeep() }
        }
        .onAppear {
            #if DEBUG
            PartnerPersistDebug.log("DribbleOrPassDisplaySessionView onAppear")
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
                dopRelayDisplayLog("relay pipeline starting (POST /v1/sessions + WebSocket display)")
                partnerRelaySession.onCoachPairingChanged = { [partnerRelaySession] connected in
                    if connected {
                        dopRelayDisplayLog("coach peer_joined")
                    } else {
                        let socket = partnerRelaySession.socketConnectionState
                        if socket == .disconnected {
                            dopRelayDisplayLog("coach unpaired (relay socket disconnected)")
                        } else {
                            dopRelayDisplayLog("coach peer_left")
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
            Task {
                guard let sessionId = await SupabaseSessionService.shared.createSessionForDrill(activity: .dribbleOrPass, blockSize: 12, playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id) else { return }
                let activityId = await SupabaseSessionService.shared.createSessionActivity(sessionId: sessionId, activityId: ActivityKind.dribbleOrPass.sessionActivityActivityId, blockNumber: 1)
                await MainActor.run {
                    CurrentSessionStore.shared.setSessionIdOnly(sessionId)
                    if let activityId = activityId { CurrentSessionStore.shared.setCurrentSessionActivityId(activityId) }
                }
            }
        }
        .onDisappear {
            pendingCoachNextRepWhileCountdown = nil
            #if DEBUG
            PartnerPersistDebug.log("DribbleOrPassDisplaySessionView onDisappear")
            #endif
            if mode.requiresPhoneDisplayRelay {
                teardownPartnerTransportWhenSessionSuspends()
            }
            unsubscribeFromAudioInterruption()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                engine.applicationDidEnterBackground()
            }
        }
        // `scenePhase == .background` is unreliable for partner teardown (often missed before suspend).
        // System notifications fire when Home / app switcher backgrounds the app or scene; use both App + Scene.
        // `beginBackgroundTask` gives a short window so disconnect runs before the system freezes the process.
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
        .onChange(of: playerStore.selectedPlayerId) { _, _ in
            wedgeStyle = WedgeDifficultyEngine.currentStyle(playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id)
        }
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLeaveAlert = true
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .alert("Leave training?", isPresented: $showLeaveAlert) {
            Button("Stay", role: .cancel) {}
            Button("Leave", role: .destructive) {
                if let id = CurrentSessionStore.shared.currentSessionActivityId {
                    Task {
                        await SupabaseSessionService.shared.endSessionActivity(sessionActivityId: id)
                        await MainActor.run { CurrentSessionStore.shared.clear() }
                    }
                }
                router.popToRoot(endingPartnerSession: false)
            }
        } message: {
            Text("Your current block will not be saved.")
        }
        .sessionCountdown(waitForPartnerReady: mode.requiresPhoneDisplayRelay, partnerReady: partnerReadyForCountdown, suppressCoachMessagesDuringCountdown: $blockCoachDrillDuringSessionCountdown)
        .onReceive(NotificationCenter.default.publisher(for: .relayForegroundReconnectCompleted)) { _ in
            guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket else { return }
            PartnerRelayCheckpointDisplaySend.sendIfReady(
                engine: engine,
                activityId: ActivityKind.dribbleOrPass.sessionActivityActivityId,
                relay: TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
            )
        }
        .onChange(of: blockCoachDrillDuringSessionCountdown) { old, new in
            guard mode.requiresPhoneDisplayRelay, old == true, new == false else { return }
            flushPendingCoachNextRepAfterCountdown()
        }
        #if DEBUG
        .onChange(of: partnerRelaySession.joinCode) { _, newCode in
            guard mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket, let code = newCode else { return }
            dopRelayDisplayLog("relay session created (HTTP OK)")
            dopRelayDisplayLog("join code assigned code=\(code)")
        }
        #endif
    }

    private func flushPendingCoachNextRepAfterCountdown() {
        guard let idx = pendingCoachNextRepWhileCountdown else { return }
        pendingCoachNextRepWhileCountdown = nil
        engine.onNextRep(repIndex: idx)
    }

    private func dopRelayDisplayLog(_ message: String) {
        #if DEBUG
        print("[RelayWS-DEBUG][DOP Display] \(message)")
        #endif
    }

    /// Ends partner transport when leaving the drill **or** when the app backgrounds (Home / app switcher), since `onDisappear` may not run.
    /// While ``TrainingPartnerConnectionCoordinator`` has an active training session, keeps relay + multipeer host alive for the next activity.
    /// **Do not** send ``sessionEnded`` while persisting — that message tells the coach app to clear the join session and return to the hub.
    private func teardownPartnerTransportWhenSessionSuspends() {
        guard mode.requiresPhoneDisplayRelay else { return }
        if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                dopRelayDisplayLog("persist partner pairing — skip sessionEnded + relay tearDown (Home / next activity)")
            }
            if sessionTransportMode == .multipeer {
                print("[Multipeer] TrainingPartnerSession: display onDisappear — skip sessionEnded + stopHosting (training session active)")
            }
            #endif
            return
        }
        sendSessionEndedIfNeeded()
        if sessionTransportMode == .relayWebSocket {
            dopRelayDisplayLog("teardown partner transport (leave or app background)")
            partnerRelaySession.tearDown()
        }
        if sessionTransportMode == .multipeer {
            connectionManager.stopHosting()
        }
    }

    private func schedulePartnerSuspendForBackgroundNotification() {
        guard mode.requiresPhoneDisplayRelay else { return }
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "DOPDisplayPartnerSuspend") {
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
        case .beepedAwaitingPass(repIndex: let ri):
            #if DEBUG
            let soloPass = Date()
            DecisionSpeedDebugLog.logSoloDisplayPassTrigger(activity: .dribbleOrPass, repIndex: ri, displayWallPassTS: soloPass)
            dopApplyPassTrigger(repIndex: ri, passTimestamp: soloPass)
            #else
            dopApplyPassTrigger(repIndex: ri, passTimestamp: Date())
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

    private static let totalReps = 12

    /// DEBUG relay: full opacity while waiting; otherwise match gate visibility dimming.
    private var statusOverlayOpacity: CGFloat {
        if shouldShowRelayWaiting { return 1 }
        return hasGatesVisible ? 0.25 : 1
    }

    private var shouldShowRelayWaiting: Bool {
        mode.requiresPhoneDisplayRelay && sessionTransportMode == .relayWebSocket && !partnerRelaySession.isCoachPaired
    }

    /// Partner: countdown only after coach is connected (Multipeer) or paired on relay. Solo: always ready.
    private var partnerReadyForCountdown: Bool {
        guard mode.requiresPhoneDisplayRelay else { return true }
        switch sessionTransportMode {
        case .multipeer:
            return connectionManager.connectedPeerName != nil
        case .relayWebSocket:
            return partnerRelaySession.isCoachPaired
        }
    }

    private var dopPartnerConnectionState: ConnectionState {
        guard mode.requiresPhoneDisplayRelay else { return connectionManager.connectionState }
        if sessionTransportMode == .relayWebSocket {
            return PartnerRelayDisplayUI.statusConnectionState(
                socketState: partnerRelaySession.socketConnectionState,
                isCoachPairedWithRelay: partnerRelaySession.isCoachPaired
            )
        }
        return connectionManager.connectionState
    }

    private var repCountOverlay: some View {
        Group {
            if !mode.requiresPhoneDisplayRelay || sessionTransportMode != .relayWebSocket || partnerRelaySession.isCoachPaired {
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
        switch engine.phase {
        case .waitingForNextRep: rep = "—"
        case .blockComplete: rep = "\(Self.totalReps)"
        case .armedScanning(let r, _), .beepedAwaitingPass(let r), .cueRevealing(let r, _), .cueVisible(let r, _), .awaitingExitLog(let r):
            rep = "\(r + 1)"
        }
        return "Rep \(rep) of \(Self.totalReps)"
    }

    private func exitLogOverlay(repIndex: Int) -> some View {
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
        DecisionSpeedDebugLog.logSoloDisplayExitTrigger(activity: .dribbleOrPass, repIndex: repIndex, gate: gate, displayWallExitTS: soloExit)
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: soloExit) != nil, let result = engine.repResults.last {
            saveDecisionForRep(result: result)
        }
        #else
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let result = engine.repResults.last {
            saveDecisionForRep(result: result)
        }
        #endif
        nextRepIndex = repIndex + 1
    }

    private func saveDecisionForRep(result: DribbleOrPassRepResult) {
        guard let sessionId = CurrentSessionStore.shared.sessionId else { return }
        let reactionTimeMs = Int(result.decisionTime * 1000)
        guard reactionTimeMs <= SupabaseDecisionService.maxReactionTimeMs else { return }
        let decision = Decision(
            sessionId: sessionId,
            playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id,
            activityName: ActivityKind.dribbleOrPass.rawValue,
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

    private var dopShouldPreloadGateCueLayers: Bool {
        switch engine.phase {
        case .armedScanning, .beepedAwaitingPass, .cueRevealing, .cueVisible, .awaitingExitLog:
            return true
        case .waitingForNextRep, .blockComplete:
            return false
        }
    }

    private func dopGateCueOpacity(for gate: Gate) -> Double {
        engine.revealedGates.contains(gate) ? 1 : 0
    }

    private func dopApplyPassTrigger(repIndex: Int, passTimestamp: Date) {
        PBAFlowDebugLog.passReceived(repId: repIndex, timestamp: passTimestamp)
        #if DEBUG
        let wallBeforeEngine = Date()
        DecisionSpeedDebugLog.logDisplayBeforeEnginePass(activity: .dribbleOrPass, repIndex: repIndex, embeddedPass: passTimestamp, displayWallBeforeEngine: wallBeforeEngine)
        #endif
        engine.onPassTrigger(repIndex: repIndex, timestamp: passTimestamp)
        PBAFlowDebugLog.reveal(repId: repIndex, timestamp: Date())
    }

    /// Drives `.id` so `DangerZoneOverlay` reveal animation replays each rep (same pattern as Away From Pressure).
    private var dribbleOrPassActiveCueRepIndex: Int {
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
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                VStack(spacing: 10) {
                    Text("X")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                }
                .position(x: center.x, y: center.y)

                if let plan = engine.currentPlan, dopShouldPreloadGateCueLayers {
                    ForEach(Gate.allCases, id: \.self) { gate in
                        DribbleOrPassGateOverlay(
                            gate: gate,
                            content: plan.content(for: gate),
                            wedgeStyle: wedgeStyle,
                            isDecisionRevealActive: engine.revealedGates.contains(gate)
                        )
                            .id("\(dribbleOrPassActiveCueRepIndex)-\(gate.rawValue)")
                            .opacity(dopGateCueOpacity(for: gate))
                            .animation(nil, value: engine.revealedGates)
                            .zIndex(1)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var statusOverlay: some View {
        VStack {
            if mode.requiresPhoneDisplayRelay {
                CoachRemoteConnectionStatusView(connectionState: dopPartnerConnectionState)
            } else {
                Text(mode == .solo ? "Tap screen or volume to trigger" : "Volume button to trigger")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            VStack(spacing: 6) {
                Text(engine.instructionTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                if !engine.instructionSubtitle.isEmpty {
                    Text(engine.instructionSubtitle)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 32)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var waitingForCoachRelayOverlay: some View {
        if shouldShowRelayWaiting {
            PartnerRelayDisplayWaitingOverlay(joinCode: partnerRelaySession.joinCode)
        }
    }

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

    private func preloadBeepAssetsForInstantReveal() {
        PBABeepSoundManager.shared.preloadCurrent()
    }

    private func playBeep() {
        if case .beepedAwaitingPass(let r) = engine.phase {
            PBAFlowDebugLog.beep(repId: r, timestamp: Date())
        }
        DispatchQueue.main.async {
            self.activateAudioSession()
            self.preloadBeepAssetsForInstantReveal()
            PBABeepSoundManager.shared.play(soundEnabled: settingsViewModel.soundEnabled)
        }
    }

    private func sendSessionEndedIfNeeded() {
        guard !hasSentSessionEnded else { return }
        hasSentSessionEnded = true
        if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
            dopRelayDisplayLog("send sessionEnded (relay)")
            partnerRelaySession.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
            return
        }
        connectionManager.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
    }
}
