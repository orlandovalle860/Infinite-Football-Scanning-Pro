//
//  OneTouchPassingDisplaySessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Layout like others; CHECK flash then green/red teammates after PASS.
//

import SwiftUI
import AVFoundation
import Combine

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
    @State private var showLeaveAlert = false
    @State private var nextRepIndex = 0
    @State private var audioInterruptionObserver: NSObjectProtocol?

    init(config: OneTouchPassingConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _engine = StateObject(wrappedValue: OneTouchPassingEngine(config: config))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            layoutWithGates
            statusOverlay
                .opacity(hasGatesVisible || engine.showCheckCue ? 0.25 : 1)
            repCountOverlay
            if mode != .partner {
                SessionVolumeTriggerView(enabled: canVolumeTrigger) { handleWallSoloTrigger() }
                    .allowsHitTesting(false)
            }
            if showExitLogButtons, let repIndex = repIndexForExit {
                exitLogOverlay(repIndex: repIndex)
                    .zIndex(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if mode == .solo { handleWallSoloTrigger() }
        }
        .navigationDestination(isPresented: $navigateToBlockSummary) {
            OneTouchPassingBlockSummaryView(results: engine.repResults, config: config, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main)) { notification in
            guard mode == .partner, let msg = notification.object as? TwoMinuteMessage else { return }
            switch msg {
            case .nextRep(let repIndex):
                engine.onNextRep(repIndex: repIndex)
            case .passTriggered(let repIndex, let timestamp):
                engine.onPassTrigger(repIndex: repIndex, timestamp: timestamp)
            case .exitLogged(let repIndex, let gate, let timestamp):
                if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let result = engine.repResults.last {
                    saveDecisionForRep(result: result)
                }
            case .firstTouchLogged: break
            case .incorrectDecision(let repIndex, let timestamp):
                if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let result = engine.repResults.last {
                    saveDecisionForRep(result: result)
                }
            case .coachPaired:
                break
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            if case .blockComplete = newPhase {
                DispatchQueue.main.async { navigateToBlockSummary = true }
            }
            if case .showingCheck = newPhase { playBeep() }
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            if mode == .partner { connectionManager.startHosting() }
            activateAudioSession()
            subscribeToAudioInterruption()
            AnalyticsManager.shared.track(.trainingSessionStarted, playerId: playerStore.selectedPlayerId)
            Task {
                guard let sessionId = await SupabaseSessionService.shared.createSessionForDrill(activity: .oneTouchPassing, blockSize: 12, playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id) else { return }
                let activityId = await SupabaseSessionService.shared.createSessionActivity(sessionId: sessionId, activityId: ActivityKind.oneTouchPassing.sessionActivityActivityId, blockNumber: 1)
                await MainActor.run {
                    CurrentSessionStore.shared.setSessionIdOnly(sessionId)
                    if let activityId = activityId { CurrentSessionStore.shared.setCurrentSessionActivityId(activityId) }
                }
            }
        }
        .onDisappear {
            if mode == .partner { connectionManager.stopHosting() }
            unsubscribeFromAudioInterruption()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { engine.applicationDidEnterBackground() }
        }
        .onChange(of: connectionManager.connectedPeerName) { _, name in
            guard mode == .partner, name != nil else { return }
            let flag = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
            connectionManager.sendDisplaySessionInfo(hasCompletedInitialTest: flag)
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
                router.popToRoot()
            }
        } message: {
            Text("Your current block will not be saved.")
        }
        .sessionCountdown()
    }

    private var canVolumeTrigger: Bool {
        switch engine.phase {
        case .waitingForNextRep, .awaitingPassTrigger: return true
        default: return false
        }
    }

    private func handleWallSoloTrigger() {
        switch engine.phase {
        case .waitingForNextRep:
            engine.onNextRep(repIndex: nextRepIndex)
        case .awaitingPassTrigger(repIndex: let ri):
            engine.onPassTrigger(repIndex: ri, timestamp: Date())
        default:
            break
        }
    }

    private var showExitLogButtons: Bool {
        guard mode != .partner else { return false }
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

    private var repCountOverlay: some View {
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

    private var repCountText: String {
        let rep: String
        switch engine.phase {
        case .waitingForNextRep: rep = "—"
        case .blockComplete: rep = "\(Self.totalReps)"
        case .armedScanning(let r, _), .showingCheck(let r), .awaitingPassTrigger(let r), .cueRevealing(let r, _), .cueVisible(let r, _), .awaitingExitLog(let r):
            rep = "\(r + 1)"
        }
        return "Rep \(rep) of \(Self.totalReps)"
    }

    private func exitLogOverlay(repIndex: Int) -> some View {
        VStack {
            Spacer()
            Text("Tap your pass direction")
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
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let result = engine.repResults.last {
            saveDecisionForRep(result: result)
        }
        nextRepIndex = repIndex + 1
    }

    private func saveDecisionForRep(result: OneTouchRepResult) {
        guard let sessionId = CurrentSessionStore.shared.sessionId else { return }
        let reactionTimeMs = Int(result.decisionTime * 1000)
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

    private var layoutWithGates: some View {
        GeometryReader { geo in
            let center = TwoMinuteSlotPositions.centerPosition()
            ZStack {
                VStack(spacing: 10) {
                    Text("X")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                }
                .position(x: center.x, y: center.y)

                if let plan = engine.currentPlan {
                    ForEach(Gate.allCases, id: \.self) { gate in
                        if engine.revealedGates.contains(gate) {
                            OneTouchGateOverlay(gate: gate, isGreen: plan.isGreen(gate))
                                .zIndex(1)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var statusOverlay: some View {
        VStack {
            if mode == .partner {
                CoachRemoteConnectionStatusView(connectionState: connectionManager.connectionState)
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

    private func playBeep() {
        DispatchQueue.main.async {
            self.activateAudioSession()
            PBABeepSoundManager.shared.play(soundEnabled: settingsViewModel.soundEnabled)
        }
    }
}
