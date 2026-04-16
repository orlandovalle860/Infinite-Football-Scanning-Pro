//
//  AwayFromPressureCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Coach remote: same as 2-min (Connect, NEXT REP, PASS, arrows). 12 reps per block.
//

import SwiftUI
import AVFoundation
import MultipeerConnectivity

enum AwayFromPressureCoachState {
    case ready
    case logging(repIndex: Int)
    case blockComplete
}

struct AwayFromPressureCoachRemoteView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    /// Avoids duplicate navigation when `sessionEnded`, Multipeer drop, and/or relay disconnect both fire.
    @State private var didNavigateBackToCoachHubAfterDisplayDisconnect = false
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    private static let partnerTransportMode = PartnerTransportPolicy.coachRemoteTransportMode

    @ObservedObject private var relaySharedRemoteService = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService
    @StateObject private var multipeerRemoteService = RemoteService(transport: TwoMinuteSessionTransport.makeInitial(for: .multipeer))

    private var remoteService: RemoteService {
        switch Self.partnerTransportMode {
        case .relayWebSocket:
            return relaySharedRemoteService
        case .multipeer:
            return multipeerRemoteService
        }
    }
    @State private var state: AwayFromPressureCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var coachRelayJoinCodeInput = ""
    @State private var coachRelayJoinError: String?
    @State private var coachRelayJoinBusy = false
    @State private var coachRelayJoinBanner: String?
    @FocusState private var relayJoinCodeFieldFocused: Bool
    @State private var coachRelayDisplayPeerJoined = false
    @State private var didAttemptCoachRelayAutoReconnect = false
    @State private var hasCompletedPassTempoCalibration = false
    @State private var partnerCalibration = PartnerPassTempoCalibrationTracker()
    @State private var showConnectedConfirmation = false
    @State private var hasStartedConnectedToCalibrationTransition = false
    @State private var hasChosenCalibrationAction = false
    @State private var shouldRunCalibration = true
    @State private var showCalibrationCompletionFeedback = false

    private let totalReps = 12

    /// Whether the active transport is connected (Multipeer peer name vs relay WebSocket).
    private var coachSessionConnected: Bool {
        if TrainingPartnerConnectionCoordinator.shared.isConnected {
            return true
        }
        switch Self.partnerTransportMode {
        case .multipeer:
            return connectionManager.connectedPeerName != nil
        case .relayWebSocket:
            return remoteService.connectionState == .connected && coachRelayDisplayPeerJoined
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { }
            VStack(spacing: 24) {
                switch state {
                case .ready, .logging:
                    readyView
                case .blockComplete: blockCompleteView
                }
            }
            if Self.partnerTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived)) { notification in
            guard let msg = notification.object as? TwoMinuteMessage else { return }
            if case .sessionEnded = msg {
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    afpCoachRelayLog("sessionEnded received")
                    CoachPersistDebug.log(
                        "sessionEnded notification — preserve join code for quick restart (clear only on explicit end/disconnect)",
                        joinField: coachRelayJoinCodeInput,
                        peerJoined: coachRelayDisplayPeerJoined
                    )
                }
                #endif
                state = .ready
                hasCompletedPassTempoCalibration = false
                partnerCalibration.reset()
                hasChosenCalibrationAction = false
                shouldRunCalibration = true
                showConnectedConfirmation = false
                hasStartedConnectedToCalibrationTransition = false
                // Stay in activity-ready state; explicit end/disconnect paths handle full reset.
            }
            PartnerRelayCheckpointCoachUI.handleDisplayCheckpointMessage(
                msg,
                relayWebSocket: Self.partnerTransportMode == .relayWebSocket,
                expectedActivityId: ActivityKind.awayFromPressure.sessionActivityActivityId,
                coachSyncRepIndex: coachSyncRepIndexForCheckpoint()
            )
        }
        .onAppear {
            didNavigateBackToCoachHubAfterDisplayDisconnect = false
            didAttemptCoachRelayAutoReconnect = false
            hasCompletedPassTempoCalibration = false
            partnerCalibration.reset()
            showConnectedConfirmation = false
            hasStartedConnectedToCalibrationTransition = false
            hasChosenCalibrationAction = false
            shouldRunCalibration = true
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                CoachPersistDebug.log("onAppear", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            }
            #endif
            TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
            let coordinator = TrainingPartnerConnectionCoordinator.shared
            if coordinator.sessionCalibrationResolved {
                hasCompletedPassTempoCalibration = true
                hasChosenCalibrationAction = true
                shouldRunCalibration = false
            } else if coordinator.isConnected,
                      !PartnerPassTempoCalibrationStore.requiresCalibration(for: .partner) {
                hasCompletedPassTempoCalibration = true
                hasChosenCalibrationAction = true
                shouldRunCalibration = false
                coordinator.markSessionCalibrationResolved(
                    averageTravelTimeSeconds: PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds(),
                    trainingMode: .partner
                )
            }
            if Self.partnerTransportMode == .multipeer {
                TrainingPartnerConnectionCoordinator.shared.prepareMultipeerCoachRemote(connectionManager: connectionManager)
            }
            if Self.partnerTransportMode == .relayWebSocket {
                attemptCoachRelayAutoReconnectIfNeeded()
            }
            beginConnectedToCalibrationTransitionIfNeeded()
        }
        .onDisappear {
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                CoachPersistDebug.log("onDisappear — enter", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            }
            #endif
            #if DEBUG
            CoachPersistDebug.log("onDisappear — no transport teardown from view", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
        }
        .onChange(of: connectionManager.connectedPeerName) { oldName, newName in
            guard Self.partnerTransportMode == .multipeer else { return }
            guard oldName != nil, newName == nil else { return }
            resetLocalUIForDisconnect(source: "connectedPeerName=nil")
        }
        .onChange(of: remoteService.connectionState) { oldState, newState in
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                afpCoachRelayLog("WebSocket remoteService.connectionState -> \(newState.rawValue)")
            }
            #endif
            guard Self.partnerTransportMode == .relayWebSocket else { return }
            guard oldState == .connected, newState == .disconnected else { return }
            #if DEBUG
            CoachPersistDebug.log("onChange remoteService.connectionState connected→disconnected", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
            // Display often reconnects the same relay when changing activities; do not wipe the one-time join code.
            if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                #if DEBUG
                afpCoachRelayLog("relay socket dropped — partner training still active; no auto-join (confirm code matches iPad)")
                CoachPersistDebug.log("keeping lastCoachRelayJoinCode (persist pairing); next screen may auto HTTP re-join", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
                #endif
                return
            }
            #if DEBUG
            CoachPersistDebug.log("onChange disconnect — local UI reset only (pairing teardown belongs to coordinator)", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
            resetLocalUIForDisconnect(source: "relayRemoteService=disconnected")
        }
        .onChange(of: coachSessionConnected) { _, connected in
            if connected {
                beginConnectedToCalibrationTransitionIfNeeded()
            } else {
                showConnectedConfirmation = false
                hasStartedConnectedToCalibrationTransition = false
                hasChosenCalibrationAction = false
                shouldRunCalibration = true
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Coach — Playing Away From Pressure (12 reps)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            if !coachSessionConnected {
                connectionSection
            } else if showConnectedConfirmation {
                PartnerConnectedConfirmationView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if !hasChosenCalibrationAction {
                CoachCalibrationDecisionView(
                    hasPreviousCalibration: PartnerPassTempoCalibrationStore.hasSavedCalibration,
                    onStartCalibration: chooseStartCalibration,
                    onSkip: skipCalibrationAndStartSession
                )
            } else if shouldRunCalibration && !hasCompletedPassTempoCalibration {
                CoachRemotePassTempoCalibrationView(
                    sampleCount: partnerCalibration.sampleCount,
                    targetSamples: partnerCalibration.targetSamples,
                    step: partnerCalibration.step,
                    canFinish: partnerCalibration.canFinish,
                    onTapPass: handleCalibrationPassTap,
                    onTapArrival: handleCalibrationArrivalTap,
                    onFinish: finishCalibrationAndStartSession,
                    showCompletionFeedback: showCalibrationCompletionFeedback
                )
            } else {
                VStack(spacing: 10) {
                    sharedSessionInput(repIndex: currentRepIndex)
                    Button("Recalibrate timing") {
                        chooseStartCalibration()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sharedSessionInput(repIndex: Int) -> some View {
        CoachSessionView(
            mode: .playPicture,
            totalReps: totalReps,
            preBeepDelayRange: 0.0...0.0,
            onRepStarted: { _ in
                startNextRepIfReady()
            },
            onPassTriggered: { rep in
                sendPassTrigger(repIndex: rep)
            },
            onDirectionLogged: { rep, swipe in
                logDecision(repIndex: rep, gate: swipe.gate)
            }
        )
    }

    private func startNextRepIfReady() {
        guard case .ready = state, currentRepIndex < totalReps else { return }
        if Self.partnerTransportMode == .multipeer {
            connectionManager.lastError = nil
        }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            afpCoachRelayLog("send nextRep repIndex=\(currentRepIndex)")
        }
        #endif
        remoteService.sendNextRep(repIndex: currentRepIndex)
        state = .logging(repIndex: currentRepIndex)
    }

    private func sendPassTrigger(repIndex: Int) {
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            afpCoachRelayLog("send passTriggered repIndex=\(repIndex)")
        }
        let t = Date()
        DecisionSpeedDebugLog.logCoachPassSend(activity: .awayFromPressure, repIndex: repIndex, embeddedTimestamp: t)
        remoteService.sendPassTriggered(repIndex: repIndex, timestamp: t)
        #else
        remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
        #endif
    }

    private var connectionSection: some View {
        Group {
            if Self.partnerTransportMode == .relayWebSocket {
                VStack(spacing: 20) {
                    PartnerRelayCoachJoinSection(
                        joinCodeInput: $coachRelayJoinCodeInput,
                        joinFieldFocused: $relayJoinCodeFieldFocused,
                        joinBusy: coachRelayJoinBusy,
                        joinBanner: coachRelayJoinBanner,
                        onJoin: {
                            afpCoachRelayLog("UI: Join session (button or auto-submit)")
                            Task { await startAFPCoachRelayJoin() }
                        }
                    )
                    Color.clear.frame(height: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                multipeerConnectionScrollContent
            }
        }
    }

    private var multipeerConnectionScrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(CoachRemoteCopy.multipeerSetupHint)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !connectionManager.isBrowsing {
                    Button("Connect to Display") {
                        connectionManager.lastError = nil
                        connectionManager.startBrowsing()
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                } else if connectionManager.connectedPeerName == nil {
                    if connectionManager.availablePeers.isEmpty {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Searching for Display…")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Make sure the other device chose \"Display\" and is on the activity screen.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("Select a device to connect:")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                        List {
                            ForEach(Array(connectionManager.availablePeers.enumerated()), id: \.offset) { _, peer in
                                Button {
                                    connectionManager.invite(peerID: peer)
                                } label: {
                                    HStack {
                                        Image(systemName: "tv").foregroundColor(.white.opacity(0.8))
                                        Text(peer.displayName).foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                    }
                    Button("Cancel") {
                        connectionManager.stopBrowsing()
                    }
                    .foregroundColor(.white.opacity(0.9))
                }

                if let error = connectionManager.lastError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Color.clear.frame(height: 24)
            }
        }
        .padding(.top, 60)
    }

    private func afpCoachRelayLog(_ message: String) {
        #if DEBUG
        print("[RelayWS-DEBUG][AFP Coach] \(message)")
        #endif
    }

    private func startAFPCoachRelayJoin() async {
        let code = coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        afpCoachRelayLog("join HTTP: start joinCode=\(code)")
        guard !code.isEmpty else {
            afpCoachRelayLog("join HTTP: aborted (empty join code)")
            return
        }
        await MainActor.run {
            coachRelayJoinBusy = true
            coachRelayJoinError = nil
            coachRelayJoinBanner = PartnerRelayJoinCodeConfig.joiningStatusBannerText
            coachRelayDisplayPeerJoined = false
        }
        do {
            let joined = try await WebSocketSessionAPI.joinSession(joinCode: code)
            afpCoachRelayLog("join HTTP: success sessionId=\(joined.sessionId)")

            let wsURL = try joined.webSocketURLForCoach()
            afpCoachRelayLog("join HTTP: coach WebSocket URL ready \(wsURL.absoluteString)")

            TrainingPartnerConnectionCoordinator.shared.recordRelaySessionId(joined.sessionId)
            let config = WebSocketSessionConfig(url: wsURL, sessionId: joined.sessionId, authToken: joined.coachToken)
            let transport = WebSocketRemoteTransport(config: config)
            let displayPeerJoinedBinding = $coachRelayDisplayPeerJoined
            let remote = remoteService
            transport.onRawTextReceived = { text in
                if text.contains("peer_joined") {
                    afpCoachRelayLog("peer_joined detected (raw frame)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = true
                    }
                }
                if text.lowercased().contains("peer_left") {
                    afpCoachRelayLog("peer_left detected — disconnecting coach relay (display socket left room)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = false
                        CoachPersistDebug.log("peer_left — before remote.disconnect (socket may reopen on display activity change)", joinField: "", peerJoined: false)
                        remote.disconnect()
                        CoachPersistDebug.log("peer_left — after remote.disconnect", joinField: "", peerJoined: false)
                    }
                }
            }

            afpCoachRelayLog("RemoteService.replaceTransport + connect()")
            await MainActor.run {
                TrainingPartnerConnectionCoordinator.shared.recordCoachRelayJoinCode(code)
                remoteService.replaceTransport(transport)
                remoteService.connect()
                coachRelayJoinBanner = nil
                coachRelayJoinBusy = false
            }
        } catch {
            afpCoachRelayLog("join HTTP: failure \(error.localizedDescription)")
            await MainActor.run {
                coachRelayJoinBusy = false
                if let api = error as? WebSocketSessionAPIError {
                    switch api {
                    case .httpError(let code, let body):
                        if code == 409, body?.contains("COACH_SLOT_TAKEN") == true {
                            let friendly = "That code doesn’t match the relay session on the iPad. Enter the join code shown on the display **right now**, then tap Join session."
                            coachRelayJoinError = friendly
                            coachRelayJoinBanner = friendly
                        } else {
                            let friendly = "Join failed (\(code)): \(body ?? "")"
                            coachRelayJoinError = friendly
                            coachRelayJoinBanner = friendly
                        }
                    case .decodingFailed:
                        coachRelayJoinError = "Join response decode failed."
                        coachRelayJoinBanner = coachRelayJoinError
                    case .invalidURL:
                        coachRelayJoinError = "Invalid URL."
                        coachRelayJoinBanner = coachRelayJoinError
                    }
                } else {
                    coachRelayJoinError = error.localizedDescription
                    coachRelayJoinBanner = error.localizedDescription
                }
            }
        }
    }

    /// After navigating hub → another activity coach screen, HTTP re-join with the last successful code if the shared socket is not connected.
    private func attemptCoachRelayAutoReconnectIfNeeded() {
        guard !didAttemptCoachRelayAutoReconnect else { return }
        let coord = TrainingPartnerConnectionCoordinator.shared
        guard let code = coord.lastCoachRelayJoinCode,
              !code.isEmpty,
              remoteService.connectionState != .connected else {
            CoachPersistDebug.log("auto-reconnect skipped (no code or already connected)", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            return
        }
        didAttemptCoachRelayAutoReconnect = true
        coachRelayJoinCodeInput = code
        CoachPersistDebug.log("auto-reconnect starting with stored join code", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
        Task { await startAFPCoachRelayJoin() }
    }

    private var blockCompleteView: some View {
        VStack(spacing: 20) {
            Text("Rep \(totalReps) of \(totalReps)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            Text("Block complete")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Results on the Display.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
    }

    private func logDecision(repIndex: Int, gate: Gate) {
        guard case .logging(let ri) = state, ri == repIndex else { return }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            afpCoachRelayLog("send exitLogged repIndex=\(repIndex) gate=\(gate)")
        }
        let t = Date()
        DecisionSpeedDebugLog.logCoachExitSend(activity: .awayFromPressure, repIndex: repIndex, gate: gate, embeddedTimestamp: t)
        remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: t)
        #else
        remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: Date())
        #endif
        advanceToNextRep(after: repIndex)
    }

    private func advanceToNextRep(after repIndex: Int) {
        currentRepIndex = repIndex + 1
        state = currentRepIndex >= totalReps ? .blockComplete : .ready
    }

    /// Aligns with display ``partnerSessionCheckpoint`` rep index (0-based).
    private func coachSyncRepIndexForCheckpoint() -> Int {
        switch state {
        case .ready: return currentRepIndex
        case .logging(let r): return r
        case .blockComplete: return totalReps
        }
    }

    private func resetLocalUIForDisconnect(source: String) {
        switch state {
        case .ready: return
        case .logging, .blockComplete: break
        }
#if DEBUG
        print("[AFP Coach] disconnect reset -> state=.ready [\(source)]")
#endif
        state = .ready
    }

    /// Clears join code + relay banners when the session ends or the relay drops so a new display session gets a fresh field.

    private func handleCalibrationPassTap() {
        let now = Date()
        partnerCalibration.handlePassTap(timestamp: now)
        remoteService.sendCalibrationPassTapped(timestamp: now)
    }

    private func handleCalibrationArrivalTap() {
        let now = Date()
        partnerCalibration.handleArrivalTap(timestamp: now)
        remoteService.sendCalibrationArrivalTapped(timestamp: now)
        if partnerCalibration.reachedTarget {
            showCalibrationCompletionAndAutoStart()
        }
    }

    private func finishCalibrationAndStartSession() {
        guard partnerCalibration.canFinish else { return }
        let avg = partnerCalibration.averageTravelTime
        PartnerPassTempoCalibrationStore.save(averageTravelTimeSeconds: avg, trainingMode: .partner)
        TrainingPartnerConnectionCoordinator.shared.markSessionCalibrationResolved(
            averageTravelTimeSeconds: avg,
            trainingMode: .partner
        )
        remoteService.sendCalibrationFinished(averageTravelTimeSeconds: avg)
        showCalibrationCompletionFeedback = false
        hasCompletedPassTempoCalibration = true
    }

    private func chooseStartCalibration() {
        hasChosenCalibrationAction = true
        shouldRunCalibration = true
        showCalibrationCompletionFeedback = false
        partnerCalibration.reset()
    }

    private func skipCalibrationAndStartSession() {
        hasChosenCalibrationAction = true
        shouldRunCalibration = false
        showCalibrationCompletionFeedback = false
        hasCompletedPassTempoCalibration = true
        let fallback = PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds()
        TrainingPartnerConnectionCoordinator.shared.markSessionCalibrationResolved(
            averageTravelTimeSeconds: fallback,
            trainingMode: .partner
        )
        remoteService.sendCalibrationFinished(averageTravelTimeSeconds: fallback)
    }

    private func showCalibrationCompletionAndAutoStart() {
        guard !showCalibrationCompletionFeedback else { return }
        showCalibrationCompletionFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            finishCalibrationAndStartSession()
        }
    }


    private func beginConnectedToCalibrationTransitionIfNeeded() {
        guard coachSessionConnected,
              !hasCompletedPassTempoCalibration,
              !hasStartedConnectedToCalibrationTransition else { return }
        hasStartedConnectedToCalibrationTransition = true
        relayJoinCodeFieldFocused = false
        PartnerRelayCoachJoinKeyboard.dismiss()
        withAnimation(.easeInOut(duration: 0.2)) {
            showConnectedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PartnerCalibrationTransition.connectedConfirmationDuration) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showConnectedConfirmation = false
            }
        }
    }

    private func clearCoachRelayJoinForm() {
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            CoachPersistDebug.log("clearCoachRelayJoinForm BEFORE", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
        }
        #endif
        coachRelayJoinCodeInput = ""
        coachRelayJoinError = nil
        coachRelayJoinBanner = nil
        coachRelayJoinBusy = false
        relayJoinCodeFieldFocused = false
        coachRelayDisplayPeerJoined = false
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            CoachPersistDebug.log("clearCoachRelayJoinForm AFTER", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
        }
        #endif
    }

    /// After the display disconnects or ends the session, return to the Coach Remote activity hub (or dismiss if nested under another stack).
    private func popToCoachRemoteHubAfterDisplayDisconnect() {
        guard !didNavigateBackToCoachHubAfterDisplayDisconnect else { return }
        didNavigateBackToCoachHubAfterDisplayDisconnect = true
        if router.path.last == .awayFromPressureCoachRemote {
            router.popLast()
        } else {
            dismiss()
        }
    }
}
