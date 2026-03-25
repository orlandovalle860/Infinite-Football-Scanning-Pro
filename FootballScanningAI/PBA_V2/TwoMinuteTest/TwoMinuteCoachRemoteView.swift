//
//  TwoMinuteCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Coach remote: Connect, NEXT REP, PASS (button + volume trigger), arrow log.
//

import SwiftUI
import AVFoundation
import MultipeerConnectivity

enum TwoMinuteCoachState: Equatable {
    case ready
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
    private static let partnerTransportMode = PartnerTransportPolicy.transportMode(for: .twoMinute)

    @StateObject private var remoteService = RemoteService(transport: TwoMinuteSessionTransport.makeInitial(for: TwoMinuteCoachRemoteView.partnerTransportMode))
    @State private var state: TwoMinuteCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var volumeTriggerEnabled = true
    @State private var showVolumeEdgeWarning = false
    @State private var coachRelayJoinCodeInput = ""
    @State private var coachRelayJoinError: String?
    @State private var coachRelayJoinBusy = false
    /// Visible status for relay DEBUG (keyboard was hiding the small error under the button).
    @State private var coachRelayJoinBanner: String?
    @FocusState private var relayJoinCodeFieldFocused: Bool
    /// DEBUG: set when `control.peer_joined` raw frame is seen (display on relay).
    @State private var coachRelayDisplayPeerJoined = false

    private let totalReps = 10

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
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { }
            VStack(spacing: 24) {
                switch state {
                case .ready: readyView
                case .logging(let repIndex): loggingView(repIndex: repIndex)
                case .complete: completeView
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(volumeTriggerOverlay)
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived)) { notification in
            guard let msg = notification.object as? TwoMinuteMessage else { return }
            if case .sessionEnded = msg {
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
        }
        .onDisappear {
            if Self.partnerTransportMode == .multipeer {
                connectionManager.stopBrowsing()
            }
            remoteService.disconnect()
            if Self.partnerTransportMode == .relayWebSocket {
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
            guard Self.partnerTransportMode == .relayWebSocket else { return }
            guard oldState == .connected, newState == .disconnected else { return }
            clearCoachRelayJoinForm()
            resetLocalUIForDisconnect(source: "relayRemoteService=disconnected")
            popToCoachRemoteHubAfterDisplayDisconnect()
        }
        .onChange(of: state) { _, newState in
            if case .complete = newState {
                UserDefaults.standard.set(true, forKey: "hasCompletedInitialTest")
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Coach — 2-Minute (10 reps)")
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

            // A. PASS — timing input (primary)
            VStack(alignment: .leading, spacing: 12) {
                Text(CoachRemoteCopy.passTimingInstruction)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                if showVolumeEdgeWarning {
                    Text(CoachRemoteVolumeTriggerConfig.edgeWarningMessage)
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.95))
                }
                CoachRemoteFeedbackTap(kind: .pass, clipCornerRadius: 16) {
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

            // B. Player decision — direction (secondary)
            VStack(alignment: .leading, spacing: 12) {
                Text(CoachRemoteCopy.playerDecisionQuestion)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.88))
                directionPad
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var directionPad: some View {
        VStack(spacing: 10) {
            CoachRemoteFeedbackTap(kind: .direction, clipCornerRadius: 12) {
                logExit(.up)
            } label: {
                arrowLabel("arrow.up")
            }
            HStack(spacing: 10) {
                CoachRemoteFeedbackTap(kind: .direction, clipCornerRadius: 12) {
                    logExit(.left)
                } label: {
                    arrowLabel("arrow.left")
                }
                CoachRemoteIncorrectPadButton(action: logIncorrect)
                CoachRemoteFeedbackTap(kind: .direction, clipCornerRadius: 12) {
                    logExit(.right)
                } label: {
                    arrowLabel("arrow.right")
                }
            }
            CoachRemoteFeedbackTap(kind: .direction, clipCornerRadius: 12) {
                logExit(.down)
            } label: {
                arrowLabel("arrow.down")
            }
        }
        .frame(height: 200)
    }

    private func arrowLabel(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.12))
            .cornerRadius(12)
            .contentShape(Rectangle())
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
                            print("[RelayWS-DEBUG][Coach] Join session (button or auto-submit)")
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
    private func startCoachRelayJoin() async {
        let code = coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[RelayWS-DEBUG][Coach] startCoachRelayJoin() entered joinCode=\(code)")
        guard !code.isEmpty else {
            print("[RelayWS-DEBUG][Coach] startCoachRelayJoin() early exit: empty join code")
            return
        }
        await MainActor.run {
            coachRelayJoinBusy = true
            coachRelayJoinError = nil
            coachRelayJoinBanner = PartnerRelayJoinCodeConfig.joiningStatusBannerText
            coachRelayDisplayPeerJoined = false
        }
        do {
            print("[RelayWS-DEBUG][Coach] before HTTP POST /v1/sessions/join joinCode=\(code)")
            let joined = try await WebSocketSessionAPI.joinSession(joinCode: code)
            print("[RelayWS-DEBUG][Coach] after HTTP join success sessionId=\(joined.sessionId)")
            print("[RelayWS-DEBUG][Coach] coachToken present, wsUrl(base)=\(joined.wsUrl) expiresAt=\(joined.expiresAt ?? "nil")")

            let wsURL = try joined.webSocketURLForCoach()
            print("[RelayWS-DEBUG][Coach] WebSocket URL (with query)=\(wsURL.absoluteString)")

            let config = WebSocketSessionConfig(url: wsURL, sessionId: joined.sessionId, authToken: joined.coachToken)
            let transport = WebSocketRemoteTransport(config: config)
            let displayPeerJoinedBinding = $coachRelayDisplayPeerJoined
            let remote = remoteService
            transport.onRawTextReceived = { text in
                #if DEBUG
                print("[RelayWS-DEBUG][Coach] received raw: \(text)")
                if text.contains("peer_joined") {
                    print("[RelayWS-DEBUG][Coach] (control.peer_joined in raw frame)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = true
                    }
                }
                if text.lowercased().contains("peer_left") {
                    print("[RelayWS-DEBUG][Coach] peer_left — disconnecting coach relay (display gone)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = false
                        remote.disconnect()
                    }
                }
                #endif
            }

            print("[RelayWS-DEBUG][Coach] replaceTransport + connect via RemoteService")
            await MainActor.run {
                remoteService.replaceTransport(transport)
                remoteService.connect()
                coachRelayJoinBanner = nil
                coachRelayJoinBusy = false
            }
        } catch {
            print("[RelayWS-DEBUG][Coach] after HTTP join failure (or post-join error): \(error)")
            await MainActor.run {
                coachRelayJoinBusy = false
                if let api = error as? WebSocketSessionAPIError {
                    switch api {
                    case .httpError(let code, let body):
                        let friendly: String
                        if code == 409, body?.contains("COACH_SLOT_TAKEN") == true {
                            friendly = "That join code was already used (coach slot taken). On the iPad, start a new 2-minute session for a new code, or restart the relay server."
                        } else {
                            friendly = "Join failed (\(code)): \(body ?? "")"
                        }
                        coachRelayJoinError = friendly
                        coachRelayJoinBanner = friendly
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
                print("[RelayWS-DEBUG][Coach] join/connect failed (UI error set): \(error)")
            }
        }
    }
    #endif

    private var volumeTriggerOverlay: some View {
        CoachRemoteVolumeTriggerView(
            connected: coachSessionConnected,
            enabled: volumeTriggerEnabled,
            repIndex: { if case .logging(let r) = state { return r }; return nil },
            onTrigger: {
                if case .logging(let repIndex) = state {
                    remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
                }
            },
            onVolumeEdgeWarningChange: { showVolumeEdgeWarning = $0 }
        )
        .id("vol-\(currentRepIndex)-\(state)")
        .allowsHitTesting(false)
        .frame(width: 1, height: 1)
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
            NavigationLink(destination: CoachRemoteHubView(settingsViewModel: settingsViewModel, profileManager: profileManager)) {
                Text("Open Coach Remote")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
    }

    private func logExit(_ gate: Gate) {
        if case .logging(let repIndex) = state {
            remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: Date())
            currentRepIndex = repIndex + 1
            state = currentRepIndex >= totalReps ? .complete : .ready
        }
    }

    private func logIncorrect() {
        if case .logging(let repIndex) = state {
            remoteService.sendIncorrectDecision(repIndex: repIndex, timestamp: Date())
            currentRepIndex = repIndex + 1
            state = currentRepIndex >= totalReps ? .complete : .ready
        }
    }

    private func resetLocalUIForDisconnect(source: String) {
        guard state != .ready else { return }
#if DEBUG
        print("[2MT Coach] disconnect reset -> state=.ready [\(source)]")
#endif
        state = .ready
        volumeTriggerEnabled = true
    }

    /// Clears join code + relay banners when the relay drops or the session ends so a new display session gets a fresh field.
    private func clearCoachRelayJoinForm() {
        coachRelayJoinCodeInput = ""
        coachRelayJoinError = nil
        coachRelayJoinBanner = nil
        coachRelayJoinBusy = false
        relayJoinCodeFieldFocused = false
        coachRelayDisplayPeerJoined = false
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
