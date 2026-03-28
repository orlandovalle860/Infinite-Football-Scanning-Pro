//
//  OneTouchPassingCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Coach logs UP / LEFT / RIGHT / DOWN. Any green = correct.
//

import SwiftUI
import AVFoundation
import MultipeerConnectivity

enum OneTouchPassingCoachState {
    case ready
    case logging(repIndex: Int)
    case blockComplete
}

struct OneTouchPassingCoachRemoteView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var didNavigateBackToCoachHubAfterDisplayDisconnect = false
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    private static let partnerTransportMode = PartnerTransportPolicy.transportMode(for: .oneTouchPassing)

    #if DEBUG
    @ObservedObject private var relaySharedRemoteService = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService
    #endif
    @StateObject private var multipeerRemoteService = RemoteService(transport: TwoMinuteSessionTransport.makeInitial(for: .multipeer))

    private var remoteService: RemoteService {
        switch Self.partnerTransportMode {
        case .relayWebSocket:
            #if DEBUG
            return relaySharedRemoteService
            #else
            return multipeerRemoteService
            #endif
        case .multipeer:
            return multipeerRemoteService
        }
    }
    @State private var state: OneTouchPassingCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var volumeTriggerEnabled = true
    @State private var showVolumeEdgeWarning = false
    @State private var coachRelayJoinCodeInput = ""
    @State private var coachRelayJoinError: String?
    @State private var coachRelayJoinBusy = false
    @State private var coachRelayJoinBanner: String?
    @FocusState private var relayJoinCodeFieldFocused: Bool
    @State private var coachRelayDisplayPeerJoined = false
    @State private var didAttemptCoachRelayAutoReconnect = false

    private let totalReps = 12

    private var coachSessionConnected: Bool {
        switch Self.partnerTransportMode {
        case .multipeer:
            return connectionManager.connectedPeerName != nil
        case .relayWebSocket:
            return remoteService.connectionState == .connected
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
            Color.clear.contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 24) {
                switch state {
                case .ready: readyView
                case .logging(let repIndex): loggingView(repIndex: repIndex)
                case .blockComplete: blockCompleteView
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(volumeTriggerOverlay)
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived)) { notification in
            guard let msg = notification.object as? TwoMinuteMessage else { return }
            if case .sessionEnded = msg {
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    otpCoachRelayLog("sessionEnded received")
                    CoachPersistDebug.log("sessionEnded notification — clearing join form", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
                }
                #endif
                if Self.partnerTransportMode == .relayWebSocket {
                    clearCoachRelayJoinForm()
                }
                state = .ready
                volumeTriggerEnabled = true
                popToCoachRemoteHubAfterDisplayDisconnect()
            }
        }
        .onAppear {
            didNavigateBackToCoachHubAfterDisplayDisconnect = false
            didAttemptCoachRelayAutoReconnect = false
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                CoachPersistDebug.log("onAppear", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            }
            #endif
            TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
            if Self.partnerTransportMode == .multipeer {
                TrainingPartnerConnectionCoordinator.shared.prepareMultipeerCoachRemote(connectionManager: connectionManager)
            }
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                attemptCoachRelayAutoReconnectIfNeeded()
            }
            #endif
        }
        .onDisappear {
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                CoachPersistDebug.log("onDisappear — enter", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            }
            #endif
            if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                #if DEBUG
                if Self.partnerTransportMode == .relayWebSocket {
                    otpCoachRelayLog("persist coach pairing — skip relay disconnect on activity disappear")
                    CoachPersistDebug.log("onDisappear — skip remoteService.disconnect (persist pairing)", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
                }
                if Self.partnerTransportMode == .multipeer {
                    print("[Multipeer] TrainingPartnerSession: coach onDisappear — skip stopBrowsing (training session active)")
                }
                #endif
                if Self.partnerTransportMode == .multipeer {
                    return
                }
                return
            }
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                CoachPersistDebug.log("onDisappear — before remoteService.disconnect (pairing not persisting)", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            }
            #endif
            if Self.partnerTransportMode == .multipeer {
                connectionManager.stopBrowsing()
            }
            remoteService.disconnect()
            if Self.partnerTransportMode == .relayWebSocket {
                #if DEBUG
                CoachPersistDebug.log("onDisappear — after remoteService.disconnect, before clearCoachRelayJoinForm", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
                #endif
                clearCoachRelayJoinForm()
            }
        }
        .onChange(of: connectionManager.connectedPeerName) { oldName, newName in
            guard Self.partnerTransportMode == .multipeer else { return }
            guard oldName != nil, newName == nil else { return }
            resetLocalUIForDisconnect(source: "connectedPeerName=nil")
            popToCoachRemoteHubAfterDisplayDisconnect()
        }
        .onChange(of: remoteService.connectionState) { oldState, newState in
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                otpCoachRelayLog("WebSocket remoteService.connectionState -> \(newState.rawValue)")
            }
            #endif
            guard Self.partnerTransportMode == .relayWebSocket else { return }
            guard oldState == .connected, newState == .disconnected else { return }
            #if DEBUG
            CoachPersistDebug.log("onChange remoteService.connectionState connected→disconnected", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
            if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                #if DEBUG
                otpCoachRelayLog("relay socket dropped — partner training still active; no auto-join (confirm code matches iPad)")
                CoachPersistDebug.log("keeping lastCoachRelayJoinCode (persist pairing); next screen may auto HTTP re-join", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
                #endif
                return
            }
            #if DEBUG
            CoachPersistDebug.log("onChange disconnect — clearCoachRelayJoinForm (pairing not active)", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
            clearCoachRelayJoinForm()
            resetLocalUIForDisconnect(source: "relayRemoteService=disconnected")
            popToCoachRemoteHubAfterDisplayDisconnect()
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Coach — One-Touch Passing (12 reps)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            if !coachSessionConnected {
                connectionSection
            } else {
                CoachRemoteConnectionStatusBar(
                    isRelay: Self.partnerTransportMode == .relayWebSocket,
                    peerDisplayName: connectionManager.connectedPeerName
                )
                Text(CoachRemoteCopy.readyForNextRep)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Rep \(currentRepIndex + 1) of \(totalReps)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 16)
                Button {
                    if Self.partnerTransportMode == .multipeer {
                        connectionManager.lastError = nil
                    }
                    #if DEBUG
                    if Self.partnerTransportMode == .relayWebSocket {
                        otpCoachRelayLog("send nextRep repIndex=\(currentRepIndex)")
                    }
                    #endif
                    remoteService.sendNextRep(repIndex: currentRepIndex)
                    state = .logging(repIndex: currentRepIndex)
                } label: {
                    Text("NEXT REP")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                        .background(Color.yellow)
                        .cornerRadius(18)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer(minLength: 0)
            }
        }
    }

    private func loggingView(repIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rep \(repIndex + 1) of \(totalReps)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text(CoachRemoteCopy.partnerCoachSetupLine)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
                Text(CoachRemoteCopy.partnerCoachBallLine)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
                Text(CoachRemoteCopy.passTimingInstruction)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                if showVolumeEdgeWarning {
                    Text(CoachRemoteVolumeTriggerConfig.edgeWarningMessage)
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.95))
                }
                CoachRemoteFeedbackTap(kind: .pass, clipCornerRadius: 16) {
                    #if DEBUG
                    if Self.partnerTransportMode == .relayWebSocket {
                        otpCoachRelayLog("send passTriggered repIndex=\(repIndex)")
                    }
                    #endif
                    remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
                } label: {
                    Text("PASS")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                        .background(Color.yellow)
                        .cornerRadius(16)
                }
                Text(CoachRemoteCopy.volumePassHint)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.38))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(CoachRemoteCopy.coachFirstDecisionLoggingLine)
                    .font(.caption)
                    .foregroundColor(.cyan.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(CoachRemoteCopy.playerDecisionQuestion)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                directionPad
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var directionPad: some View {
        VStack(spacing: 10) {
            directionButton(gate: .up)
            HStack(spacing: 10) {
                directionButton(gate: .left)
                CoachRemoteIncorrectPadButton(action: logIncorrect)
                directionButton(gate: .right)
            }
            directionButton(gate: .down)
        }
        .frame(height: 200)
    }

    private var connectionSection: some View {
        Group {
            #if DEBUG
            if Self.partnerTransportMode == .relayWebSocket {
                VStack(spacing: 20) {
                    Text("Rep \(currentRepIndex + 1) of \(totalReps)")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                    PartnerRelayCoachJoinSection(
                        joinCodeInput: $coachRelayJoinCodeInput,
                        joinFieldFocused: $relayJoinCodeFieldFocused,
                        joinBusy: coachRelayJoinBusy,
                        joinBanner: coachRelayJoinBanner,
                        relayTransportConnected: remoteService.connectionState == .connected,
                        displayPeerJoined: coachRelayDisplayPeerJoined,
                        onJoin: {
                            otpCoachRelayLog("UI: Join session (button or auto-submit)")
                            Task { await startOTPCoachRelayJoin() }
                        }
                    )
                    Color.clear.frame(height: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                multipeerConnectionScrollContent
            }
            #else
            multipeerConnectionScrollContent
            #endif
        }
    }

    private var multipeerConnectionScrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Rep \(currentRepIndex + 1) of \(totalReps)")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))

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
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.2)
                        Text("Searching for Display…").font(.subheadline).foregroundColor(.white.opacity(0.8))
                        Text("Make sure the other device chose \"Display\" and is on the grid screen.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("Select a device to connect:").font(.subheadline).foregroundColor(.white.opacity(0.9))
                        List {
                            ForEach(Array(connectionManager.availablePeers.enumerated()), id: \.offset) { _, peer in
                                Button { connectionManager.invite(peerID: peer) } label: {
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
                    Text(error).font(.subheadline).foregroundColor(.orange).multilineTextAlignment(.center).padding(.horizontal)
                }

                Color.clear.frame(height: 24)
            }
        }
        .padding(.top, 60)
    }

    #if DEBUG
    private func startOTPCoachRelayJoin() async {
        let code = coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        otpCoachRelayLog("join HTTP: start joinCode=\(code)")
        guard !code.isEmpty else {
            otpCoachRelayLog("join HTTP: aborted (empty join code)")
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
            otpCoachRelayLog("join HTTP: success sessionId=\(joined.sessionId)")

            let wsURL = try joined.webSocketURLForCoach()
            otpCoachRelayLog("join HTTP: coach WebSocket URL ready \(wsURL.absoluteString)")

            let config = WebSocketSessionConfig(url: wsURL, sessionId: joined.sessionId, authToken: joined.coachToken)
            let transport = WebSocketRemoteTransport(config: config)
            let displayPeerJoinedBinding = $coachRelayDisplayPeerJoined
            let remote = remoteService
            transport.onRawTextReceived = { text in
                #if DEBUG
                if text.contains("peer_joined") {
                    otpCoachRelayLog("peer_joined detected (raw frame)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = true
                    }
                }
                if text.lowercased().contains("peer_left") {
                    otpCoachRelayLog("peer_left detected — disconnecting coach relay (display socket left room)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = false
                        CoachPersistDebug.log("peer_left — before remote.disconnect", joinField: "", peerJoined: false)
                        remote.disconnect()
                        CoachPersistDebug.log("peer_left — after remote.disconnect", joinField: "", peerJoined: false)
                    }
                }
                #endif
            }

            otpCoachRelayLog("RemoteService.replaceTransport + connect()")
            await MainActor.run {
                TrainingPartnerConnectionCoordinator.shared.recordCoachRelayJoinCode(code)
                remoteService.replaceTransport(transport)
                remoteService.connect()
                coachRelayJoinBanner = nil
                coachRelayJoinBusy = false
            }
        } catch {
            otpCoachRelayLog("join HTTP: failure \(error.localizedDescription)")
            await MainActor.run {
                coachRelayJoinBusy = false
                if let api = error as? WebSocketSessionAPIError {
                    switch api {
                    case .httpError(let code, let body):
                        if code == 409, body?.contains("COACH_SLOT_TAKEN") == true {
                            clearCoachRelayJoinForm()
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

    private func otpCoachRelayLog(_ message: String) {
        print("[RelayWS-DEBUG][OTP Coach] \(message)")
    }

    private func attemptCoachRelayAutoReconnectIfNeeded() {
        guard !didAttemptCoachRelayAutoReconnect else { return }
        let coord = TrainingPartnerConnectionCoordinator.shared
        guard coord.shouldPersistPartnerPairing,
              let code = coord.lastCoachRelayJoinCode,
              !code.isEmpty,
              remoteService.connectionState != .connected else {
            CoachPersistDebug.log("auto-reconnect skipped (no code, not persisting, or already connected)", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            return
        }
        didAttemptCoachRelayAutoReconnect = true
        coachRelayJoinCodeInput = code
        CoachPersistDebug.log("auto-reconnect starting with stored join code", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
        Task { await startOTPCoachRelayJoin() }
    }
    #endif

    private var volumeTriggerOverlay: some View {
        CoachRemoteVolumeTriggerView(
            connected: coachSessionConnected,
            enabled: volumeTriggerEnabled,
            repIndex: { if case .logging(let r) = state { return r }; return nil },
            onTrigger: {
                if case .logging(let repIndex) = state {
                    #if DEBUG
                    if Self.partnerTransportMode == .relayWebSocket {
                        otpCoachRelayLog("send passTriggered (volume) repIndex=\(repIndex)")
                    }
                    #endif
                    remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
                }
            },
            onVolumeEdgeWarningChange: { showVolumeEdgeWarning = $0 }
        )
        .id("vol-\(currentRepIndex)-\(state)")
        .allowsHitTesting(false)
        .frame(width: 1, height: 1)
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

    private func directionButton(gate: Gate) -> some View {
        let name: String
        switch gate {
        case .up: name = "arrow.up"
        case .down: name = "arrow.down"
        case .left: name = "arrow.left"
        case .right: name = "arrow.right"
        }
        return CoachRemoteFeedbackTap(kind: .direction, clipCornerRadius: 12) {
            logExit(gate)
        } label: {
            Image(systemName: name)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
                .contentShape(Rectangle())
        }
    }

    private func logExit(_ gate: Gate) {
        guard case .logging(let repIndex) = state else { return }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            otpCoachRelayLog("send exitLogged repIndex=\(repIndex) gate=\(gate)")
        }
        #endif
        remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: Date())
        currentRepIndex = repIndex + 1
        state = currentRepIndex >= totalReps ? .blockComplete : .ready
    }

    private func logIncorrect() {
        guard case .logging(let repIndex) = state else { return }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            otpCoachRelayLog("send incorrectDecision repIndex=\(repIndex)")
        }
        #endif
        remoteService.sendIncorrectDecision(repIndex: repIndex, timestamp: Date())
        currentRepIndex = repIndex + 1
        state = currentRepIndex >= totalReps ? .blockComplete : .ready
    }

    private func resetLocalUIForDisconnect(source: String) {
        switch state {
        case .ready: return
        case .logging, .blockComplete: break
        }
#if DEBUG
        print("[OTP Coach] disconnect reset -> state=.ready [\(source)]")
#endif
        state = .ready
        volumeTriggerEnabled = true
    }

    private func clearCoachRelayJoinForm() {
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            CoachPersistDebug.log("clearCoachRelayJoinForm BEFORE", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
        }
        #endif
        TrainingPartnerConnectionCoordinator.shared.clearRecordedCoachRelayJoinCode()
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

    private func popToCoachRemoteHubAfterDisplayDisconnect() {
        guard !didNavigateBackToCoachHubAfterDisplayDisconnect else { return }
        didNavigateBackToCoachHubAfterDisplayDisconnect = true
        if router.path.last == .oneTouchPassingCoachRemote {
            router.popLast()
        } else {
            dismiss()
        }
    }
}
