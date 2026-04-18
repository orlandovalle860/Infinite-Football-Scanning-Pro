//
//  TwoMinuteCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Coach remote: Connect, NEXT REP, PASS, arrow log.
//

import SwiftUI
import AVFoundation
import MultipeerConnectivity

enum TwoMinuteCoachState: Equatable {
    case ready
    case waitingForRepStart(repIndex: Int)
    case armedForPass(repIndex: Int)
    case logging(repIndex: Int)
    case complete
}

struct TwoMinuteCoachRemoteView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    /// Avoids duplicate navigation when `sessionEnded` and relay disconnect both fire.
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
    @State private var state: TwoMinuteCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var coachRelayJoinCodeInput = ""
    @State private var coachRelayJoinError: String?
    @State private var coachRelayJoinBusy = false
    /// Visible status for relay DEBUG (keyboard was hiding the small error under the button).
    @State private var coachRelayJoinBanner: String?
    @FocusState private var relayJoinCodeFieldFocused: Bool
    /// DEBUG: set when `control.peer_joined` raw frame is seen (display on relay).
    @State private var coachRelayDisplayPeerJoined = false
    @State private var didAttemptCoachRelayAutoReconnect = false
    @State private var hasCompletedPassTempoCalibration = false
    @State private var partnerCalibration = PartnerPassTempoCalibrationTracker()
    @State private var showConnectedConfirmation = false
    @State private var hasStartedConnectedToCalibrationTransition = false
    @State private var hasChosenCalibrationAction = false
    @State private var shouldRunCalibration = true
    @State private var showCalibrationCompletionFeedback = false
    @State private var repStartAckTimeoutWorkItem: DispatchWorkItem?
    @State private var repStartTapSentTimestamp: TimeInterval = 0
    @State private var pendingRepStartHardResetRepIndex: Int?
    @State private var coachSessionInputResetToken = UUID()
    /// 0-based rep index the display has beeped for; `nil` before any beep in
    /// the current rep. Updated on `.beepArmed` messages and passed to
    /// `CoachSessionView` so the PASS button only arms after the iPad's beep.
    @State private var externalBeepArmedRepIndex: Int? = nil
    @State private var didBroadcastCoachSessionStart = false
    @State private var showReconnectRestartOverlay = false
    @State private var coachRepIndexSnapshotAtDisconnect: Int?
    private let repStartAckTimeoutWindow: TimeInterval = 4.5
    private let repStartLateAckGraceWindow: TimeInterval = 0.6

    private let totalReps = 10

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
                case .ready, .waitingForRepStart, .armedForPass, .logging:
                    readyView
                case .complete: completeView
                }
            }
            if Self.partnerTransportMode == .relayWebSocket {
                PartnerRelayLifecycleBannerOverlay()
            }
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(160)
            if showReconnectRestartOverlay {
                Text("Reconnected — restarting rep")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity)
                    .zIndex(1000)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showReconnectRestartOverlay)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived)) { notification in
            guard let msg = notification.object as? TwoMinuteMessage else { return }
            if case .repStarted(let repIndex, _) = msg {
                handleRepStartedAcknowledgement(repIndex: repIndex)
            }
            if case .beepArmed(let repIndex, _) = msg {
                handleBeepArmed(repIndex: repIndex)
            }
            if case .partnerSessionCheckpoint(let sourceRole, _, let repIndex, _, _, _) = msg, sourceRole == "display" {
                handleDisplayRepSignal(repIndex: repIndex)
            }
            if case .sessionEnded = msg {
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    CoachPersistDebug.log(
                        "sessionEnded notification — preserve join code for quick restart (clear only on explicit end/disconnect)",
                        joinField: coachRelayJoinCodeInput,
                        peerJoined: coachRelayDisplayPeerJoined
                    )
                }
                #endif
                state = .ready
                hasCompletedPassTempoCalibration = true
                partnerCalibration.reset()
                hasChosenCalibrationAction = true
                shouldRunCalibration = false
                showConnectedConfirmation = false
                hasStartedConnectedToCalibrationTransition = false
                clearRepStartAckWaitState()
                resetCoachSessionInput()
                // Stay in activity-ready state; explicit end/disconnect paths handle full reset.
            }
            PartnerRelayCheckpointCoachUI.handleDisplayCheckpointMessage(
                msg,
                relayWebSocket: Self.partnerTransportMode == .relayWebSocket,
                expectedActivityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
                coachSyncRepIndex: coachSyncRepIndexForCheckpoint()
            )
        }
        .onAppear {
            didNavigateBackToCoachHubAfterDisplayDisconnect = false
            didAttemptCoachRelayAutoReconnect = false
            hasCompletedPassTempoCalibration = true
            partnerCalibration.reset()
            showConnectedConfirmation = false
            hasStartedConnectedToCalibrationTransition = false
            hasChosenCalibrationAction = true
            shouldRunCalibration = false
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                CoachPersistDebug.log("onAppear", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            }
            #endif
            TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
            let coordinator = TrainingPartnerConnectionCoordinator.shared
            coordinator.markSessionCalibrationResolved(
                averageTravelTimeSeconds: PartnerPassTempoCalibrationStore.seededAverageTravelTimeSeconds(),
                trainingMode: .partner
            )
            if Self.partnerTransportMode == .multipeer {
                TrainingPartnerConnectionCoordinator.shared.prepareMultipeerCoachRemote(connectionManager: connectionManager)
            }
            if Self.partnerTransportMode == .relayWebSocket {
                attemptCoachRelayAutoReconnectIfNeeded()
            }
            didBroadcastCoachSessionStart = false
            if coachSessionConnected {
                broadcastCoachSessionStartIfNeeded()
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
            guard Self.partnerTransportMode == .relayWebSocket else { return }
            guard oldState == .connected, newState == .disconnected else { return }
            #if DEBUG
            CoachPersistDebug.log("onChange remoteService.connectionState connected→disconnected", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
            if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                #if DEBUG
                print("[RelayWS-DEBUG][Coach] relay dropped — training persists; no auto-join (confirm code matches iPad)")
                CoachPersistDebug.log("keeping lastCoachRelayJoinCode (persist pairing); next screen may auto HTTP re-join", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
                #endif
                return
            }
            #if DEBUG
            CoachPersistDebug.log("onChange disconnect — local UI reset only (pairing teardown belongs to coordinator)", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
            resetLocalUIForDisconnect(source: "relayRemoteService=disconnected")
        }
        .onChange(of: state) { _, newState in
            if case .complete = newState {
                AuthFlowOnboardingSync.markLocalAndSyncRemoteCompleted()
            }
        }
        .onChange(of: coachSessionConnected) { wasConnected, connected in
            if connected {
                if !wasConnected,
                   TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing,
                   let snap = coachRepIndexSnapshotAtDisconnect,
                   snap == coachSyncRepIndexForCheckpoint() {
                    triggerReconnectRestartOverlay()
                }
                coachRepIndexSnapshotAtDisconnect = nil
                broadcastCoachSessionStartIfNeeded()
                beginConnectedToCalibrationTransitionIfNeeded()
            } else {
                if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing, wasConnected {
                    coachRepIndexSnapshotAtDisconnect = coachSyncRepIndexForCheckpoint()
                } else {
                    coachRepIndexSnapshotAtDisconnect = nil
                }
                if !TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                    didBroadcastCoachSessionStart = false
                }
                showConnectedConfirmation = false
                hasStartedConnectedToCalibrationTransition = false
                hasCompletedPassTempoCalibration = true
                hasChosenCalibrationAction = true
                shouldRunCalibration = false
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func broadcastCoachSessionStartIfNeeded() {
        guard !didBroadcastCoachSessionStart else { return }
        didBroadcastCoachSessionStart = true
        TrainingPartnerConnectionCoordinator.shared.broadcastSessionStartedFromCoach(activity: .twoMinuteTest, totalReps: totalReps)
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            if !coachSessionConnected {
                connectionSection
            } else if showConnectedConfirmation {
                PartnerConnectedConfirmationView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                sharedSessionInput(repIndex: currentRepIndex)
            }
        }
    }

    private func sharedSessionInput(repIndex: Int) -> some View {
        CoachSessionView(
            coachRemoteHeaderTitle: "Coach — 2-Minute (\(totalReps) reps)",
            totalReps: totalReps,
            currentRepOneBased: currentRepIndex + 1,
            preBeepDelayRange: 0.0...0.0,
            waitsForExternalBeepArm: true,
            externalBeepArmedRepIndex: $externalBeepArmedRepIndex,
            onRepStarted: { _ in
                startNextRepIfReady()
            },
            onPassTriggered: { _ in
                sendPassTrigger(repIndex: currentRepIndex)
            },
            onDirectionLogged: { _, swipe in
                logExit(repIndex: currentRepIndex, gate: swipe.gate)
            },
            coachFirstRunActivityId: ActivityKind.twoMinuteTest.sessionActivityActivityId,
            coachTransportConnected: coachSessionConnected
        )
        .id(coachSessionInputResetToken)
    }

    @discardableResult
    private func startNextRepIfReady() -> Bool {
        guard case .ready = state, currentRepIndex < totalReps else { return false }
        let now = Date().timeIntervalSince1970
        repStartTapSentTimestamp = now
        pendingRepStartHardResetRepIndex = nil
        if Self.partnerTransportMode == .multipeer {
            connectionManager.lastError = nil
        }
        remoteService.sendNextRep(repIndex: currentRepIndex)
        state = .waitingForRepStart(repIndex: currentRepIndex)
        scheduleRepStartAckTimeout(for: currentRepIndex)
        return true
    }

    private func sendPassTrigger(repIndex: Int) -> Bool {
        guard case .armedForPass(let armedRep) = state, armedRep == repIndex else { return false }
        clearRepStartAckWaitState()
        state = .logging(repIndex: repIndex)
        #if DEBUG
        let t = Date()
        DecisionSpeedDebugLog.logCoachPassSend(activity: .twoMinuteTest, repIndex: repIndex, embeddedTimestamp: t)
        remoteService.sendPassTriggered(repIndex: repIndex, timestamp: t)
        #else
        remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
        #endif
        return true
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
                            #if DEBUG
                            print("[RelayWS-DEBUG][Coach] Join session (button or auto-submit)")
                            #endif
                            Task { await startCoachRelayJoin() }
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
                                        Image(systemName: "tv")
                                            .foregroundColor(.white.opacity(0.8))
                                        Text(peer.displayName)
                                            .foregroundColor(.white)
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

    private func startCoachRelayJoin() async {
        let code = coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        print("[RelayWS-DEBUG][Coach] startCoachRelayJoin() entered joinCode=\(code)")
        #endif
        guard !code.isEmpty else {
            #if DEBUG
            print("[RelayWS-DEBUG][Coach] startCoachRelayJoin() early exit: empty join code")
            #endif
            return
        }
        await MainActor.run {
            coachRelayJoinBusy = true
            coachRelayJoinError = nil
            coachRelayJoinBanner = PartnerRelayJoinCodeConfig.joiningStatusBannerText
            coachRelayDisplayPeerJoined = false
        }
        do {
            #if DEBUG
            print("[RelayWS-DEBUG][Coach] before HTTP POST /v1/sessions/join joinCode=\(code)")
            #endif
            let joined = try await WebSocketSessionAPI.joinSession(joinCode: code)
            #if DEBUG
            print("[RelayWS-DEBUG][Coach] after HTTP join success sessionId=\(joined.sessionId)")
            print("[RelayWS-DEBUG][Coach] coachToken present, wsUrl(base)=\(joined.wsUrl) expiresAt=\(joined.expiresAt ?? "nil")")
            #endif

            let wsURL = try joined.webSocketURLForCoach()
            #if DEBUG
            print("[RelayWS-DEBUG][Coach] WebSocket URL (with query)=\(wsURL.absoluteString)")
            #endif

            TrainingPartnerConnectionCoordinator.shared.recordRelaySessionId(joined.sessionId)
            let config = WebSocketSessionConfig(url: wsURL, sessionId: joined.sessionId, authToken: joined.coachToken)
            let transport = WebSocketRemoteTransport(config: config)
            let displayPeerJoinedBinding = $coachRelayDisplayPeerJoined
            let remote = remoteService
            transport.onRawTextReceived = { text in
                TrainingPartnerConnectionCoordinator.shared.ingestCoachRelayRawControlText(text)
                #if DEBUG
                print("[RelayWS-DEBUG][Coach] received raw: \(text)")
                #endif
                if text.contains("peer_joined") {
                    #if DEBUG
                    print("[RelayWS-DEBUG][Coach] (control.peer_joined in raw frame)")
                    #endif
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = true
                    }
                }
                if text.lowercased().contains("peer_left") {
                    #if DEBUG
                    print("[RelayWS-DEBUG][Coach] peer_left — disconnecting coach relay (display socket left room)")
                    #endif
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = false
                        CoachPersistDebug.log("peer_left — before remote.disconnect", joinField: "", peerJoined: false)
                        remote.disconnect()
                        CoachPersistDebug.log("peer_left — after remote.disconnect", joinField: "", peerJoined: false)
                    }
                }
            }

            #if DEBUG
            print("[RelayWS-DEBUG][Coach] replaceTransport + connect via RemoteService")
            #endif
            await MainActor.run {
                TrainingPartnerConnectionCoordinator.shared.recordCoachRelayJoinCode(code)
                remoteService.replaceTransport(transport)
                remoteService.connect()
                coachRelayJoinBanner = nil
                coachRelayJoinBusy = false
            }
        } catch {
            #if DEBUG
            print("[RelayWS-DEBUG][Coach] after HTTP join failure (or post-join error): \(error)")
            #endif
            if WebSocketSessionAPI.isInvalidOrExpiredJoinSessionError(error) {
                await MainActor.run {
                    TrainingPartnerConnectionCoordinator.shared.recoverCoachRelayStateAfterExpiredJoinCode()
                    coachRelayJoinCodeInput = ""
                    coachRelayJoinBusy = false
                    coachRelayDisplayPeerJoined = false
                    coachRelayJoinError = WebSocketSessionAPI.relayJoinCodeExpiredUserMessage
                    coachRelayJoinBanner = WebSocketSessionAPI.relayJoinCodeExpiredUserMessage
                }
                return
            }
            await MainActor.run {
                coachRelayJoinBusy = false
                let friendly = WebSocketSessionAPI.userFacingJoinErrorMessage(error)
                coachRelayJoinError = friendly
                coachRelayJoinBanner = friendly
                #if DEBUG
                print("[RelayWS-DEBUG][Coach] join/connect failed (UI error set): \(error)")
                #endif
            }
        }
    }

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
        Task { await startCoachRelayJoin() }
    }

    private var completeView: some View {
        VStack(spacing: 20) {
            Text("Rep \(totalReps) of \(totalReps)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text("Test complete")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Results are on the Display.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
            Button {
                coachStartNextBlockTapped()
            } label: {
                Text("Start Next Block")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 8)
            .padding(.top, 8)
            Spacer()
        }
    }

    private func coachStartNextBlockTapped() {
        didNavigateBackToCoachHubAfterDisplayDisconnect = false
        router.popCoachRemoteToStartSessionHub(dismiss: dismiss, expectingTopRoute: .twoMinuteCoachRemote)
    }

    private func logExit(repIndex: Int, gate: Gate) {
        guard case .logging(let ri) = state, ri == repIndex else { return }
        #if DEBUG
        let t = Date()
        DecisionSpeedDebugLog.logCoachExitSend(activity: .twoMinuteTest, repIndex: repIndex, gate: gate, embeddedTimestamp: t)
        remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: t)
        #else
        remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: Date())
        #endif
        currentRepIndex = repIndex + 1
        clearRepStartAckWaitState()
        if currentRepIndex >= totalReps {
            CoachFirstRunGuidanceStore.markCompletedFirstRun(activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId)
            state = .complete
        } else {
            state = .ready
            resetCoachSessionInput()
        }
    }

    private func triggerReconnectRestartOverlay() {
        showReconnectRestartOverlay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showReconnectRestartOverlay = false
        }
    }

    private func coachSyncRepIndexForCheckpoint() -> Int {
        switch state {
        case .ready: return currentRepIndex
        case .waitingForRepStart(let r): return r
        case .armedForPass(let r): return r
        case .logging(let r): return r
        case .complete: return totalReps
        }
    }

    private func resetLocalUIForDisconnect(source: String) {
        guard state != .ready else { return }
#if DEBUG
        print("[2MT Coach] disconnect reset -> state=.ready [\(source)]")
#endif
        clearRepStartAckWaitState()
        state = .ready
        resetCoachSessionInput()
    }

    private func handleRepStartedAcknowledgement(repIndex: Int) {
        if case .waitingForRepStart(let waitingRep) = state, waitingRep == repIndex {
            clearRepStartAckWaitState()
            state = .armedForPass(repIndex: repIndex)
            #if DEBUG
            let deltaMs = Int((Date().timeIntervalSince1970 - repStartTapSentTimestamp) * 1000)
            print("[2MT Coach] repStarted ACK in \(deltaMs)ms for rep \(repIndex)")
            #endif
            return
        }
        if case .armedForPass(let r) = state, r == repIndex {
            clearRepStartAckWaitState()
            return
        }
        if case .logging(let r) = state, r == repIndex {
            clearRepStartAckWaitState()
            return
        }
        if case .ready = state, currentRepIndex == repIndex {
            clearRepStartAckWaitState()
            pendingRepStartHardResetRepIndex = nil
            state = .armedForPass(repIndex: repIndex)
            #if DEBUG
            print("[2MT Coach] repStarted ACK accepted while .ready (late after timeout) rep \(repIndex)")
            #endif
            return
        }
        guard pendingRepStartHardResetRepIndex == repIndex else { return }
        clearRepStartAckWaitState()
        pendingRepStartHardResetRepIndex = nil
        state = .armedForPass(repIndex: repIndex)
        #if DEBUG
        let deltaMs = Int((Date().timeIntervalSince1970 - repStartTapSentTimestamp) * 1000)
        print("[2MT Coach] late repStarted ACK accepted in \(deltaMs)ms for rep \(repIndex)")
        #endif
    }

    private func handleDisplayRepSignal(repIndex: Int) {
        guard case .waitingForRepStart(let waitingRep) = state, waitingRep == repIndex else { return }
        clearRepStartAckWaitState()
        pendingRepStartHardResetRepIndex = nil
        state = .armedForPass(repIndex: repIndex)
    }

    private func scheduleRepStartAckTimeout(for repIndex: Int) {
        repStartAckTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard case .waitingForRepStart(let waitingRep) = state, waitingRep == repIndex else { return }
            pendingRepStartHardResetRepIndex = repIndex
            let hardReset = DispatchWorkItem {
                guard case .waitingForRepStart(let stillWaitingRep) = state, stillWaitingRep == repIndex else { return }
                guard pendingRepStartHardResetRepIndex == repIndex else { return }
                state = .ready
                pendingRepStartHardResetRepIndex = nil
                resetCoachSessionInput()
            }
            repStartAckTimeoutWorkItem = hardReset
            DispatchQueue.main.asyncAfter(deadline: .now() + repStartLateAckGraceWindow, execute: hardReset)
        }
        repStartAckTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + repStartAckTimeoutWindow, execute: work)
    }

    private func clearRepStartAckWaitState() {
        repStartAckTimeoutWorkItem?.cancel()
        repStartAckTimeoutWorkItem = nil
        pendingRepStartHardResetRepIndex = nil
    }

    private func resetCoachSessionInput() {
        coachSessionInputResetToken = UUID()
        // Drop any stale beep-arm signal so a leftover value from the previous
        // rep can't pre-arm the next rep's PASS button before the display beeps.
        externalBeepArmedRepIndex = nil
    }

    private func handleBeepArmed(repIndex: Int) {
        guard repIndex == currentRepIndex else {
            #if DEBUG
            print("[2MT Coach] beepArmed ignored: repIndex=\(repIndex) currentRepIndex=\(currentRepIndex)")
            #endif
            return
        }
        externalBeepArmedRepIndex = repIndex
    }

    /// Clears join code + relay banners when the relay drops or the session ends so a new display session gets a fresh field.

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
        guard coachSessionConnected else { return }
        relayJoinCodeFieldFocused = false
        PartnerRelayCoachJoinKeyboard.dismiss()
        showConnectedConfirmation = false
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
        if router.path.last == .twoMinuteCoachRemote {
            router.popLast()
        } else {
            dismiss()
        }
    }
}
