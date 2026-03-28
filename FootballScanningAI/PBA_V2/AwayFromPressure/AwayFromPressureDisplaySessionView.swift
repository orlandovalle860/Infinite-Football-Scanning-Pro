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
    @State private var showLeaveAlert = false
    @State private var nextRepIndex = 0
    @State private var audioInterruptionObserver: NSObjectProtocol?
    @State private var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    @State private var hasSentSessionEnded = false
    /// True while ``SessionCountdownModifier`` shows 3–2–1–Go; coach drill messages must not advance the engine until the drill is visible.
    @State private var blockCoachDrillDuringSessionCountdown = false
    @ObservedObject private var partnerRelaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession

    private static let partnerTransportMode = PartnerTransportPolicy.transportMode(for: .awayFromPressure)

    init(config: AwayFromPressureConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _engine = StateObject(wrappedValue: AwayFromPressureEngine(config: config, trainingMode: mode))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            dribbleOrPassLayout
            statusOverlay
                .opacity(statusOverlayOpacity)
            repCountOverlay
            if mode != .partner {
                wallSoloTriggerOverlay
            }
            if showExitLogButtons {
                exitLogOverlay
            }
            waitingForCoachRelayOverlay
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if mode == .solo { handleWallSoloTrigger() }
        }
        .navigationDestination(isPresented: $navigateToBlockSummary) {
            AwayFromPressureBlockSummaryView(logs: engine.repLogs, config: config, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main)) { notification in
            guard mode == .partner, let msg = notification.object as? TwoMinuteMessage else { return }
            if blockCoachDrillDuringSessionCountdown && msg.isDrillInteractionFromCoach { return }
            switch msg {
            case .nextRep(let repIndex):
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    if !partnerRelaySession.isCoachPaired {
                        afpRelayDisplayLog("incoming nextRep repIndex=\(repIndex) while isCoachPaired=false (still applying — relay UI can lag peer_joined)")
                    }
                    afpRelayDisplayLog("incoming nextRep repIndex=\(repIndex)")
                }
                #endif
                engine.onNextRep(repIndex: repIndex)
            case .passTriggered(let repIndex, let timestamp):
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpRelayDisplayLog("incoming passTriggered repIndex=\(repIndex)")
                }
                #endif
                engine.onPassTrigger(repIndex: repIndex, timestamp: timestamp)
            case .exitLogged(let repIndex, let gate, let timestamp):
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpRelayDisplayLog("incoming exitLogged repIndex=\(repIndex) gate=\(gate)")
                }
                #endif
                if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                    saveDecisionForRep(log: log)
                }
            case .firstTouchLogged(let repIndex, let gate, let timestamp):
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpRelayDisplayLog("incoming firstTouchLogged repIndex=\(repIndex) gate=\(gate)")
                }
                #endif
                engine.onFirstTouchLogged(repIndex: repIndex, gate: gate, timestamp: timestamp)
            case .incorrectDecision(let repIndex, let timestamp):
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpRelayDisplayLog("incoming incorrectDecision repIndex=\(repIndex)")
                }
                #endif
                if engine.onIncorrectDecision(repIndex: repIndex, timestamp: timestamp) != nil, let log = engine.repLogs.last {
                    saveDecisionForRep(log: log)
                }
            case .coachPaired:
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpRelayDisplayLog("incoming coachPaired (envelope)")
                }
                #endif
                break
            case .sessionEnded:
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpRelayDisplayLog("sessionEnded received")
                }
                #endif
                break
            case .partnerTrainingEnded:
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpRelayDisplayLog("partnerTrainingEnded received (coordinator also tears down relay)")
                }
                #endif
                break
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            if case .blockComplete = newPhase {
                DispatchQueue.main.async { navigateToBlockSummary = true }
            }
            if case .beepedAwaitingPass = newPhase { playBeep() }
            if case .waitingForNextRep = newPhase, mode != .partner {
                // Next rep index already set when user tapped exit direction
            }
        }
        .onAppear {
            #if DEBUG
            PartnerPersistDebug.log("AwayFromPressureDisplaySessionView onAppear")
            #endif
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            hasSentSessionEnded = false
            if mode == .partner {
                TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
                if Self.partnerTransportMode == .multipeer {
                    TrainingPartnerConnectionCoordinator.shared.prepareMultipeerDisplayPartner(connectionManager: connectionManager)
                }
            }
            #if DEBUG
            if mode == .partner, Self.partnerTransportMode == .relayWebSocket {
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
            #endif
            let pid = playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
            wedgeStyle = WedgeDifficultyEngine.currentStyle(playerId: pid)
            activateAudioSession()
            subscribeToAudioInterruption()
            AnalyticsManager.shared.track(.trainingSessionStarted, playerId: playerStore.selectedPlayerId)
            Task {
                guard let sessionId = await SupabaseSessionService.shared.createSessionForDrill(activity: .awayFromPressure, blockSize: 12, playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id) else { return }
                let activityId = await SupabaseSessionService.shared.createSessionActivity(sessionId: sessionId, activityId: ActivityKind.awayFromPressure.sessionActivityActivityId, blockNumber: 1)
                await MainActor.run {
                    CurrentSessionStore.shared.setSessionIdOnly(sessionId)
                    if let activityId = activityId { CurrentSessionStore.shared.setCurrentSessionActivityId(activityId) }
                }
            }
        }
        .onDisappear {
            #if DEBUG
            PartnerPersistDebug.log("AwayFromPressureDisplaySessionView onDisappear")
            #endif
            if mode == .partner {
                teardownPartnerTransportWhenSessionSuspends()
            }
            unsubscribeFromAudioInterruption()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { engine.applicationDidEnterBackground() }
        }
        // `onDisappear` may not run when Home / app switcher backgrounds the app; mirror DOP / Two Minute.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            schedulePartnerSuspendForBackgroundNotification()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification)) { _ in
            schedulePartnerSuspendForBackgroundNotification()
        }
        .sessionCountdown(waitForPartnerReady: mode == .partner, partnerReady: partnerReadyForCountdown, suppressCoachMessagesDuringCountdown: $blockCoachDrillDuringSessionCountdown)
        .onChange(of: connectionManager.connectedPeerName) { _, name in
            guard mode == .partner, Self.partnerTransportMode == .multipeer, name != nil else { return }
            let flag = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
            connectionManager.sendDisplaySessionInfo(hasCompletedInitialTest: flag)
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .onChange(of: partnerRelaySession.joinCode) { _, newCode in
            guard mode == .partner, Self.partnerTransportMode == .relayWebSocket, let code = newCode else { return }
            afpRelayDisplayLog("relay session created (HTTP OK)")
            afpRelayDisplayLog("join code assigned code=\(code)")
        }
        #endif
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
                // Same intent as Get Ready / Home toolbar: return to Pathway without ending the shared relay run.
                router.popToRoot(endingPartnerSession: false)
            }
        } message: {
            Text("Your current block will not be saved.")
        }
    }

    private var showExitLogButtons: Bool {
        guard mode != .partner else { return false }
        if case .awaitingExitLog = engine.phase { return true }
        if case .markerVisible = engine.phase { return true }
        return false
    }

    private var wallSoloTriggerOverlay: some View {
        SessionVolumeTriggerView(enabled: canVolumeTrigger) {
            handleWallSoloTrigger()
        }
        .allowsHitTesting(false)
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
        case .beepedAwaitingPass(repIndex: let ri, _):
            engine.onPassTrigger(repIndex: ri, timestamp: Date())
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

    private static let totalReps = 12

    /// DEBUG relay: full opacity while waiting; otherwise match marker dimming.
    private var statusOverlayOpacity: CGFloat {
        if shouldShowRelayWaiting { return 1 }
        return isMarkerVisible ? 0.25 : 1
    }

    private var shouldShowRelayWaiting: Bool {
        mode == .partner && Self.partnerTransportMode == .relayWebSocket && !partnerRelaySession.isCoachPaired
    }

    /// Partner: countdown only after coach is connected (Multipeer) or paired on relay. Solo: always ready.
    private var partnerReadyForCountdown: Bool {
        guard mode == .partner else { return true }
        switch Self.partnerTransportMode {
        case .multipeer:
            return connectionManager.connectedPeerName != nil
        case .relayWebSocket:
            return partnerRelaySession.isCoachPaired
        }
    }

    private var afpPartnerConnectionState: ConnectionState {
        guard mode == .partner else { return connectionManager.connectionState }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            return PartnerRelayDisplayUI.statusConnectionState(
                socketState: partnerRelaySession.socketConnectionState,
                isCoachPairedWithRelay: partnerRelaySession.isCoachPaired
            )
        }
        #endif
        return connectionManager.connectionState
    }

    private var repCountOverlay: some View {
        Group {
            if mode != .partner || Self.partnerTransportMode != .relayWebSocket || partnerRelaySession.isCoachPaired {
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
        case .armedScanning(let r, _, _), .beepedAwaitingPass(let r, _), .markerVisible(let r, _, _), .awaitingExitLog(let r, _):
            rep = "\(r + 1)"
        }
        return "Rep \(rep) of \(Self.totalReps)"
    }

    private var exitLogOverlay: some View {
        Group {
            if let repIndex = repIndexForExit {
                VStack {
                    Spacer()
                    Text(ActivityDisplaySessionCopy.tapAwayFromPressure)
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
        }
        .zIndex(2)
    }

    private func logExit(repIndex: Int, gate: Gate) {
        if engine.onExitLogged(repIndex: repIndex, gate: gate, timestamp: Date()) != nil, let log = engine.repLogs.last {
            saveDecisionForRep(log: log)
        }
        nextRepIndex = repIndex + 1
    }

    private func saveDecisionForRep(log: AwayFromPressureRepLog) {
        guard let sessionId = CurrentSessionStore.shared.sessionId,
              let sec = log.decisionTimeSeconds else { return }
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

    private var isMarkerVisible: Bool {
        if case .markerVisible = engine.phase { return true }
        return false
    }

    private var dribbleOrPassLayout: some View {
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

                if case .markerVisible(_, let pressureGate, _) = engine.phase {
                    DangerZoneOverlay(gate: pressureGate, style: wedgeStyle)
                        .zIndex(1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var statusOverlay: some View {
        VStack {
            if mode == .partner {
                CoachRemoteConnectionStatusView(connectionState: afpPartnerConnectionState)
            } else {
                Text(mode == .solo ? "Tap screen or volume to trigger" : "Volume button to trigger")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            instructionBlock
                .padding(.bottom, 32)
        }
        .padding(.top, 16)
    }

    private var instructionBlock: some View {
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
    }

    @ViewBuilder
    private var waitingForCoachRelayOverlay: some View {
        if shouldShowRelayWaiting {
            PartnerRelayDisplayWaitingOverlay(joinCode: partnerRelaySession.joinCode)
        }
    }

    #if DEBUG
    private func afpRelayDisplayLog(_ message: String) {
        print("[RelayWS-DEBUG][AFP Display] \(message)")
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

    private func playBeep() {
        DispatchQueue.main.async {
            self.activateAudioSession()
            PBABeepSoundManager.shared.play(soundEnabled: settingsViewModel.soundEnabled)
        }
    }

    private func sendSessionEndedIfNeeded() {
        guard !hasSentSessionEnded else { return }
        hasSentSessionEnded = true
        #if DEBUG
        if mode == .partner, Self.partnerTransportMode == .relayWebSocket {
            afpRelayDisplayLog("send sessionEnded (relay)")
            partnerRelaySession.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
            return
        }
        #endif
        connectionManager.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
    }

    /// Ends partner transport when leaving the drill **or** when the app backgrounds (Home / app switcher).
    /// **Do not** send ``sessionEnded`` while persisting — that message tells the coach app to clear the join session and return to the hub.
    private func teardownPartnerTransportWhenSessionSuspends() {
        guard mode == .partner else { return }
        if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                afpRelayDisplayLog("persist partner pairing — skip sessionEnded + relay tearDown (Home / next activity)")
            }
            if Self.partnerTransportMode == .multipeer {
                print("[Multipeer] TrainingPartnerSession: display onDisappear — skip sessionEnded + stopHosting (training session active)")
            }
            #endif
            return
        }
        sendSessionEndedIfNeeded()
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            afpRelayDisplayLog("teardown partner transport (leave or app background)")
            partnerRelaySession.tearDown()
        }
        #endif
        if Self.partnerTransportMode == .multipeer {
            connectionManager.stopHosting()
        }
    }

    /// iOS Home / app switcher backgrounds the process — **do not** end training pairing (that forced a new join code).
    private func schedulePartnerSuspendForBackgroundNotification() {
        guard mode == .partner else { return }
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
