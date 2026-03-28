//
//  DribbleOrPassCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Coach logs UP / LEFT / RIGHT / DOWN. DOWN is never correct.
//

import SwiftUI
import AVFoundation
import MultipeerConnectivity

enum DribbleOrPassCoachState {
    case ready
    case logging(repIndex: Int)
    case blockComplete
}

struct DribbleOrPassCoachRemoteView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    /// Avoids a second `sessionEnded` + relay disconnect both popping/dismissing.
    @State private var didNavigateBackToCoachHubAfterDisplayDisconnect = false
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    private static let partnerTransportMode = PartnerTransportPolicy.transportMode(for: .dribbleOrPass)

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
    @State private var state: DribbleOrPassCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var volumeTriggerEnabled = true
    @State private var showVolumeEdgeWarning = false
    @State private var coachRelayJoinCodeInput = ""
    @State private var coachRelayJoinError: String?
    @State private var coachRelayJoinBusy = false
    @State private var coachRelayJoinBanner: String?
    @FocusState private var relayJoinCodeFieldFocused: Bool
    /// DEBUG: set when `control.peer_joined` raw frame is seen (display on relay).
    @State private var coachRelayDisplayPeerJoined = false
    @State private var didAttemptCoachRelayAutoReconnect = false

    private let totalReps = 12

    /// Whether the active transport is connected (Multipeer peer name vs relay WebSocket).
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
                    dopCoachRelayLog("sessionEnded received")
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
                    dopCoachRelayLog("persist coach pairing — skip relay disconnect on activity disappear")
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
                dopCoachRelayLog("WebSocket remoteService.connectionState -> \(newState.rawValue)")
            }
            #endif
            guard Self.partnerTransportMode == .relayWebSocket else { return }
            guard oldState == .connected, newState == .disconnected else { return }
            #if DEBUG
            CoachPersistDebug.log("onChange remoteService.connectionState connected→disconnected", joinField: coachRelayJoinCodeInput, peerJoined: coachRelayDisplayPeerJoined)
            #endif
            if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                #if DEBUG
                dopCoachRelayLog("relay socket dropped — partner training still active; no auto-join (confirm code matches iPad)")
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
        .navigationTitle("Coach — Dribble or Pass (12 reps)")
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
                        dopCoachRelayLog("send nextRep repIndex=\(currentRepIndex)")
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
                        dopCoachRelayLog("send passTriggered repIndex=\(repIndex)")
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
                decisionPad(repIndex: repIndex)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decisionPad(repIndex: Int) -> some View {
        VStack(spacing: 10) {
            directionButton(repIndex: repIndex, gate: .up)
            HStack(spacing: 10) {
                directionButton(repIndex: repIndex, gate: .left)
                CoachRemoteIncorrectPadButton { logIncorrect(repIndex: repIndex) }
                directionButton(repIndex: repIndex, gate: .right)
            }
            directionButton(repIndex: repIndex, gate: .down)
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
                            dopCoachRelayLog("UI: Join session (button or auto-submit)")
                            Task { await startDOPCoachRelayJoin() }
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
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Searching for Display…")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Make sure the other device chose \"Display\" and is on the grid screen.")
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

    #if DEBUG
    private func startDOPCoachRelayJoin() async {
        let code = coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        dopCoachRelayLog("join HTTP: start joinCode=\(code)")
        guard !code.isEmpty else {
            dopCoachRelayLog("join HTTP: aborted (empty join code)")
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
            dopCoachRelayLog("join HTTP: success sessionId=\(joined.sessionId)")

            let wsURL = try joined.webSocketURLForCoach()
            dopCoachRelayLog("join HTTP: coach WebSocket URL ready \(wsURL.absoluteString)")

            let config = WebSocketSessionConfig(url: wsURL, sessionId: joined.sessionId, authToken: joined.coachToken)
            let transport = WebSocketRemoteTransport(config: config)
            let displayPeerJoinedBinding = $coachRelayDisplayPeerJoined
            // Capture service for peer_left: relay sends this when the display disconnects; the coach WebSocket can
            // otherwise stay `.connected` until TCP times out, so the UI must react to control frames explicitly.
            let remote = remoteService
            transport.onRawTextReceived = { text in
                #if DEBUG
                if text.contains("peer_joined") {
                    dopCoachRelayLog("peer_joined detected (raw frame)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = true
                    }
                }
                if text.lowercased().contains("peer_left") {
                    dopCoachRelayLog("peer_left detected — disconnecting coach relay (display socket left room)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = false
                        CoachPersistDebug.log("peer_left — before remote.disconnect", joinField: "", peerJoined: false)
                        remote.disconnect()
                        CoachPersistDebug.log("peer_left — after remote.disconnect", joinField: "", peerJoined: false)
                    }
                }
                #endif
            }

            dopCoachRelayLog("RemoteService.replaceTransport + connect()")
            await MainActor.run {
                TrainingPartnerConnectionCoordinator.shared.recordCoachRelayJoinCode(code)
                remoteService.replaceTransport(transport)
                remoteService.connect()
                coachRelayJoinBanner = nil
                coachRelayJoinBusy = false
            }
        } catch {
            dopCoachRelayLog("join HTTP: failure \(error.localizedDescription)")
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

    /// Concise DEBUG relay QA line (coach). No-op in non-DEBUG builds via `#if` at call sites.
    private func dopCoachRelayLog(_ message: String) {
        print("[RelayWS-DEBUG][DOP Coach] \(message)")
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
        Task { await startDOPCoachRelayJoin() }
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
                        dopCoachRelayLog("send passTriggered (volume) repIndex=\(repIndex)")
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

    private func directionButton(repIndex: Int, gate: Gate) -> some View {
        let name: String
        switch gate {
        case .up: name = "arrow.up"
        case .down: name = "arrow.down"
        case .left: name = "arrow.left"
        case .right: name = "arrow.right"
        }
        return CoachRemoteFeedbackTap(kind: .direction, clipCornerRadius: 12) {
            logDecision(repIndex: repIndex, gate: gate)
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

    private func logDecision(repIndex: Int, gate: Gate) {
        guard case .logging(let ri) = state, ri == repIndex else { return }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            dopCoachRelayLog("send exitLogged repIndex=\(repIndex) gate=\(gate)")
        }
        #endif
        remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: Date())
        advanceToNextRep(after: repIndex)
    }

    private func logIncorrect(repIndex: Int) {
        guard case .logging(let ri) = state, ri == repIndex else { return }
        #if DEBUG
        if Self.partnerTransportMode == .relayWebSocket {
            dopCoachRelayLog("send incorrectDecision repIndex=\(repIndex)")
        }
        #endif
        remoteService.sendIncorrectDecision(repIndex: repIndex, timestamp: Date())
        advanceToNextRep(after: repIndex)
    }

    private func advanceToNextRep(after repIndex: Int) {
        currentRepIndex = repIndex + 1
        state = currentRepIndex >= totalReps ? .blockComplete : .ready
    }

    private func resetLocalUIForDisconnect(source: String) {
        switch state {
        case .ready: return
        case .logging, .blockComplete: break
        }
#if DEBUG
        print("[DOP Coach] disconnect reset -> state=.ready [\(source)]")
#endif
        state = .ready
        volumeTriggerEnabled = true
    }

    /// Clears join code + relay banners when the session ends or the relay drops so a new display session gets a fresh field.
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

    /// After the display disconnects or ends the session, return to the Coach Remote activity hub (or dismiss if this screen was pushed via `NavigationLink`).
    private func popToCoachRemoteHubAfterDisplayDisconnect() {
        guard !didNavigateBackToCoachHubAfterDisplayDisconnect else { return }
        didNavigateBackToCoachHubAfterDisplayDisconnect = true
        if router.path.last == .dribbleOrPassCoachRemote {
            router.popLast()
        } else {
            dismiss()
        }
    }
}
