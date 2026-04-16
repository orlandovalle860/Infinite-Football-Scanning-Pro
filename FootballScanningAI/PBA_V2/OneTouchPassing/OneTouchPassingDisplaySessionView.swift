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
    @State private var showLeaveAlert = false
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
    @State private var pendingCoachNextRepWhileCountdown: Int?
    /// Red covered gate wedge: same adaptive style as Playing Away From Pressure (`WedgeDifficultyEngine`).
    @State private var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    @ObservedObject private var partnerRelaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession

    private var sessionTransportMode: SessionTransportMode {
        PartnerTransportPolicy.transportMode(for: .oneTouchPassing, trainingMode: mode)
    }

    init(config: OneTouchPassingConfig, mode: TrainingMode, settingsViewModel: SettingsViewModel, profileManager: UserProfileManager) {
        self.config = config
        self.mode = mode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _engine = StateObject(wrappedValue: OneTouchPassingEngine(config: config, trainingMode: mode))
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
            if showConnectedConfirmation {
                PartnerConnectedConfirmationView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(5)
            }
            if mode.requiresPhoneDisplayRelay, sessionTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
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
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived).receive(on: RunLoop.main), perform: handleOneTouchCoachRelayMessage)
        .onChange(of: engine.phase) { _, newPhase in
            #if DEBUG
            OTPPersistDebug.log("engine.phase -> \(String(describing: newPhase)) | blockCoachDrillDuringSessionCountdown=\(blockCoachDrillDuringSessionCountdown) waitingOverlay=\(shouldShowRelayWaiting) relayCoachPaired=\(partnerRelaySession.isCoachPaired)")
            #endif
            if case .blockComplete = newPhase {
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
        }
        .onAppear {
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
            pendingCoachNextRepWhileCountdown = nil
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
            if newPhase == .background { engine.applicationDidEnterBackground() }
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
        default:
            break
        }
        if !hasCompletedPassTempoCalibration && !mode.requiresPhoneDisplayRelay { return }
        let shouldBlockCoachDrillMessages = blockCoachDrillDuringSessionCountdown && !coachConnectedForCalibration
        if PartnerCountdownCoachMessagePolicy.shouldDeferWhileCountdown(
            msg: msg,
            isBlockingDrillMessagesFromCoach: shouldBlockCoachDrillMessages,
            pendingNextRepIndex: &pendingCoachNextRepWhileCountdown
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
        case .nextRep(let repIndex):
            pendingCoachNextRepWhileCountdown = nil
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                if !partnerRelaySession.isCoachPaired {
                    otpRelayDisplayLog("incoming nextRep repIndex=\(repIndex) while isCoachPaired=false (still applying — relay UI can lag peer_joined)")
                }
                otpRelayDisplayLog("incoming nextRep repIndex=\(repIndex)")
            }
            #endif
            engine.onNextRep(repIndex: repIndex)
        case .passTriggered(let repIndex, let timestamp):
            if case .waitingForNextRep = engine.phase {
                print("Ignoring late message for completed rep:", repIndex)
                break
            }
            #if DEBUG
            if sessionTransportMode == .relayWebSocket {
                otpRelayDisplayLog("incoming passTriggered repIndex=\(repIndex)")
            }
            let displayReceiveWall = Date()
            DecisionSpeedDebugLog.logDisplayRelayIngress(activity: .oneTouchPassing, kind: "passTriggered", repIndex: repIndex, embeddedTimestamp: timestamp, displayReceiveWallTime: displayReceiveWall)
            #endif
            otpApplyPassTrigger(repIndex: repIndex, passTimestamp: timestamp)
        case .exitLogged(let repIndex, let gate, let timestamp):
            if case .waitingForNextRep = engine.phase {
                print("Ignoring late message for completed rep:", repIndex)
                break
            }
            print("🔥🔥 DISPLAY RECEIVED exitLogged -> rep:", repIndex)
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
                saveDecisionForRep(result: result)
            }
        case .firstTouchLogged: break
        case .incorrectDecision(let repIndex, let timestamp):
            if case .waitingForNextRep = engine.phase {
                print("Ignoring late message for completed rep:", repIndex)
                break
            }
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
        case .calibrationPassTapped, .calibrationArrivalTapped, .calibrationFinished:
            break
        }
    }

    private func handleWallSoloTrigger() {
        switch engine.phase {
        case .waitingForNextRep:
            engine.onNextRep(repIndex: nextRepIndex)
        case .awaitingPassTrigger(repIndex: let ri):
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

    private static let totalReps = 12

    private var statusOverlayOpacity: CGFloat {
        if shouldShowRelayWaiting { return 1 }
        return (hasGatesVisible || engine.showCheckCue) ? 0.25 : 1
    }

    private var shouldShowRelayWaiting: Bool {
        mode.requiresPhoneDisplayRelay && sessionTransportMode == .relayWebSocket && !partnerRelaySession.isCoachPaired
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

    private var otpPartnerConnectionState: ConnectionState {
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
                    VStack(spacing: 2) {
                        HStack {
                            Text(repCountText)
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        HStack {
                            Text("Tempo: \(config.difficulty.passTempo.displayName)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.62))
                            Spacer()
                        }
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
        case .armedScanning(let r, _), .showingCheck(let r), .awaitingPassTrigger(let r), .cueRevealing(let r, _), .cueVisible(let r, _), .awaitingExitLog(let r):
            rep = "\(r + 1)"
        }
        return "Rep \(rep) of \(Self.totalReps)"
    }

    private func exitLogOverlay(repIndex: Int) -> some View {
        VStack {
            Spacer()
            Text(ActivityDisplaySessionCopy.tapOneTouchPassing)
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
        DecisionSpeedDebugLog.logSoloDisplayExitTrigger(activity: .oneTouchPassing, repIndex: repIndex, gate: gate, displayWallExitTS: soloExit)
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

    private func saveDecisionForRep(result: OneTouchRepResult) {
        guard let sessionId = CurrentSessionStore.shared.sessionId else { return }
        let travelTimeSeconds = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
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
        }
    }

    private var statusOverlay: some View {
        VStack {
            if mode.requiresPhoneDisplayRelay {
                CoachRemoteConnectionStatusView(connectionState: otpPartnerConnectionState)
            } else {
                Text("Tap screen to trigger")
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
            PartnerRelayDisplayWaitingOverlay(
                joinCode: partnerRelaySession.joinCode,
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
        case .passTriggered(let i, _): return "passTriggered(\(i))"
        case .exitLogged(let i, let g, _): return "exitLogged(\(i),\(g))"
        case .firstTouchLogged(let i, let g, _): return "firstTouchLogged(\(i),\(g))"
        case .incorrectDecision(let i, _): return "incorrectDecision(\(i))"
        case .coachPaired(let sid): return "coachPaired(\(sid))"
        case .sessionEnded(_): return "sessionEnded"
        case .partnerTrainingEnded(_): return "partnerTrainingEnded"
        case .partnerSessionCheckpoint(_, _, _, _, _, _): return "partnerSessionCheckpoint"
        case .calibrationPassTapped: return "calibrationPassTapped"
        case .calibrationArrivalTapped: return "calibrationArrivalTapped"
        case .calibrationFinished(let s): return "calibrationFinished(\(String(describing: s)))"
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
        guard let idx = pendingCoachNextRepWhileCountdown else { return }
        pendingCoachNextRepWhileCountdown = nil
        engine.onNextRep(repIndex: idx)
    }

    private func preloadBeepAssetsForInstantReveal() {
        PBABeepSoundManager.shared.preloadCurrent()
    }

    private func playBeep() {
        #if DEBUG
        OTPPersistDebug.log("playBeep() executing (CHECK cue)")
        #endif
        if case .showingCheck(let r) = engine.phase {
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
            otpRelayDisplayLog("send sessionEnded (relay)")
            partnerRelaySession.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
            return
        }
        connectionManager.sendTwoMinuteMessage(.sessionEnded(timestamp: Date()))
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
