//
//  TwoMinuteCriticalScanSessionView.swift
//  FootballScanningAI
//
//  PBA V2 — Display: same layout as Dribble or Pass (center X, four slots). Star appears at one slot when coach triggers (PASS/volume).
//

import SwiftUI
import AVFoundation
import Combine

struct TwoMinuteCriticalScanSessionView: View {
    let config: TwoMinuteTestConfig
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @StateObject private var engine: TwoMinuteCriticalScanEngine
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var testResult: TwoMinuteTestResult?
    @State private var showLeaveAlert = false
    @State private var nextRepIndex = 0
    @State private var beepPlayer: AVAudioPlayer?
    @State private var audioInterruptionObserver: NSObjectProtocol?
    @Environment(\.dismiss) private var dismiss

    init(config: TwoMinuteTestConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _engine = StateObject(wrappedValue: TwoMinuteCriticalScanEngine(config: config))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            dribbleOrPassLayout
            statusOverlay
                .opacity(isStarVisible ? 0.25 : 1)
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
        .contentShape(Rectangle())
        .onTapGesture {
            if mode == .solo { handleWallSoloTrigger() }
        }
        .fullScreenCover(item: $testResult) { result in
            NavigationStack {
                TwoMinuteTestResultsView(
                    result: result,
                    profileManager: profileManager,
                    settingsViewModel: settingsViewModel,
                    onDismissCover: { testResult = nil }
                )
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main)) { notification in
            guard mode == .partner, let msg = notification.object as? TwoMinuteMessage else { return }
            switch msg {
            case .nextRep(let repIndex):
                engine.onNextRep(repIndex: repIndex)
            case .passTriggered(let repIndex, let timestamp):
                engine.onPassTrigger(repIndex: repIndex, timestamp: timestamp)
            case .exitLogged(let repIndex, let gate, let timestamp):
                engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp)
            case .firstTouchLogged:
                break // Only used by Away From Pressure
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            if case .complete = newPhase {
                DispatchQueue.main.async {
                    testResult = TwoMinuteTestResult.from(logs: engine.repLogs, difficulty: config.difficulty)
                }
            }
            if case .beepedAwaitingPass = newPhase { playBeep() }
        }
        .onChange(of: testResult) { old, new in
            // When user taps "Back to Home", cover dismisses (testResult = nil). Trigger cascade so this view dismisses too.
            if old != nil && new == nil {
                popToRootTrigger.request = true
            }
        }
        .onChange(of: popToRootTrigger.request) { _, new in
            if new { dismiss() }
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            if mode == .partner { multipeerManager.startAdvertising() }
            activateAudioSession()
            subscribeToAudioInterruption()
        }
        .onDisappear {
            if mode == .partner { multipeerManager.stopAdvertising() }
            unsubscribeFromAudioInterruption()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { engine.applicationDidEnterBackground() }
        }
        .onChange(of: multipeerManager.connectedPeerName) { _, name in
            guard mode == .partner, name != nil else { return }
            let flag = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
            multipeerManager.sendDisplaySessionInfo(hasCompletedInitialTest: flag)
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
                router.popToRoot()
            }
        } message: {
            Text("Your current block will not be saved.")
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
        case .beepedAwaitingPass(repIndex: let ri, starGate: _):
            engine.onPassTrigger(repIndex: ri, timestamp: Date())
        default:
            break
        }
    }

    private var showExitLogButtons: Bool {
        guard mode != .partner else { return false }
        if case .awaitingExitLog = engine.phase { return true }
        if case .starVisible = engine.phase { return true }
        return false
    }

    private var repIndexForExit: Int? {
        switch engine.phase {
        case .awaitingExitLog(let ri, _), .starVisible(let ri, _, _): return ri
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
        engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date())
        nextRepIndex = repIndex + 1
    }

    /// Same layout as Dribble or Pass: center "X" marker, no players. Star at one of four slots when visible.
    private var dribbleOrPassLayout: some View {
        GeometryReader { geo in
            let positions = TwoMinuteSlotPositions.positionsForCurrentScreen()
            let center = TwoMinuteSlotPositions.centerPosition()

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
                if case .starVisible(_, let starGate, _) = engine.phase,
                   let pt = positions[starGate] {
                    Image("SoccerBall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .shadow(radius: 4)
                        .position(x: pt.x, y: pt.y)
                        .zIndex(1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Peer name when connected; explicitly Optional so conditional binding is valid.
    private var connectedPeerDisplayName: String? { multipeerManager.connectedPeerName }

    private var statusOverlay: some View {
        VStack {
            if mode == .partner {
                if let name = connectedPeerDisplayName {
                    Text("Connected to \(name)")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if multipeerManager.isAdvertising {
                    Text("Advertising… Tap Connect on the coach device.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("Starting…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                Text(mode == .solo ? "Tap screen or volume to trigger" : "Volume button to trigger")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Group {
                    if case .waitingForNextRep = engine.phase {
                        VStack(spacing: 4) {
                            Text("Waiting for coach…")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Keep moving. Check both shoulders.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else if case .armedScanning = engine.phase {
                        VStack(spacing: 4) {
                            Text("Keep moving. Check both shoulders.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Beep is coming.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else if case .beepedAwaitingPass = engine.phase {
                        VStack(spacing: 4) {
                            Text("Ball is coming. Check again.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Coach: press PASS when it leaves your foot.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else if case .awaitingExitLog = engine.phase {
                        VStack(spacing: 4) {
                            Text("Play the rep.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Waiting for coach log…")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else {
                        Text(phaseStatusText)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.top, 16)
    }

    /// Overlay text fades during starVisible so the star is the focus.
    private var isStarVisible: Bool {
        if case .starVisible = engine.phase { return true }
        return false
    }

    private var phaseStatusText: String {
        switch engine.phase {
        case .waitingForNextRep: return "Waiting for coach…"
        case .armedScanning(_, _, let endsAt):
            let sec = max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up)))
            return sec > 0 ? "Scan freely — beep in \(sec)s" : "Scan freely"
        case .beepedAwaitingPass: return "Ball is coming — tap PASS on phone"
        case .starVisible: return ""
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
            guard let url = Bundle.main.url(forResource: "short-beep-351721", withExtension: "mp3") else { return }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                self.beepPlayer = player
                player.prepareToPlay()
                player.play()
            } catch {}
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
}
