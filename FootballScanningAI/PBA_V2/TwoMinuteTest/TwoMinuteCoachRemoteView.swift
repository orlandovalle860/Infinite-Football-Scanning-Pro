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
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    /// DEBUG: relay WebSocket; Release: Multipeer — one mode per Two Minute partner session.
    private static let initialTwoMinuteTransportMode: SessionTransportMode = {
        #if DEBUG
        return .relayWebSocket
        #else
        return .multipeer
        #endif
    }()

    @StateObject private var remoteService = RemoteService(transport: TwoMinuteSessionTransport.makeInitial(for: TwoMinuteCoachRemoteView.initialTwoMinuteTransportMode))
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
        switch Self.initialTwoMinuteTransportMode {
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
                state = .ready
                volumeTriggerEnabled = true
            }
        }
        .onDisappear {
            if Self.initialTwoMinuteTransportMode == .multipeer {
                connectionManager.stopBrowsing()
            }
            remoteService.disconnect()
            #if DEBUG
            coachRelayDisplayPeerJoined = false
            #endif
        }
        .onChange(of: connectionManager.connectedPeerName) { _, newName in
            guard Self.initialTwoMinuteTransportMode == .multipeer else { return }
            if newName == nil {
                resetLocalUIForDisconnect(source: "connectedPeerName=nil")
            }
        }
        .onChange(of: connectionManager.connectionState) { _, newState in
            guard Self.initialTwoMinuteTransportMode == .multipeer else { return }
            if newState == .disconnected {
                resetLocalUIForDisconnect(source: "connectionState=disconnected")
            }
        }
        .onChange(of: remoteService.connectionState) { _, newState in
            guard Self.initialTwoMinuteTransportMode == .relayWebSocket else { return }
            if newState == .disconnected {
                resetLocalUIForDisconnect(source: "relayRemoteService=disconnected")
            }
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
        VStack(spacing: 24) {
            if !coachSessionConnected {
                connectionSection
            } else {
                Spacer(minLength: 40)
                if Self.initialTwoMinuteTransportMode == .multipeer, let name = connectionManager.connectedPeerName {
                    Text("Connected to \(name)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else if Self.initialTwoMinuteTransportMode == .relayWebSocket {
                    Text("Connected (relay)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                Text("Tap NEXT REP to start the next rep on the Display.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    if Self.initialTwoMinuteTransportMode == .multipeer {
                        connectionManager.lastError = nil
                    }
                    remoteService.sendNextRep(repIndex: currentRepIndex)
                    state = .logging(repIndex: currentRepIndex)
                } label: {
                    Text("NEXT REP")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(Color.yellow)
                        .cornerRadius(18)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 32)

                Text("Rep \(currentRepIndex + 1) of \(totalReps)")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }
        }
    }

    private func loggingView(repIndex: Int) -> some View {
        VStack(spacing: 16) {
            Text("Rep \(repIndex + 1) of \(totalReps)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
            Text("When the Display beeps, tap PASS or press volume at strike.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            if showVolumeEdgeWarning {
                Text(CoachRemoteVolumeTriggerConfig.edgeWarningMessage)
                    .font(.caption)
                    .foregroundColor(.orange.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            Button {
                remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
            } label: {
                Text("PASS")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.yellow)
                    .cornerRadius(16)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)

            Text("Tap the direction the player chose, or ✕ if incorrect.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))

            directionPad

            Text("Volume buttons also trigger PASS (use the PASS button if volume is stuck at the top or bottom).")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var directionPad: some View {
        VStack(spacing: 10) {
            Button { logExit(.up) } label: { arrowLabel("arrow.up") }
                .buttonStyle(PlainButtonStyle())
            HStack(spacing: 10) {
                Button { logExit(.left) } label: { arrowLabel("arrow.left") }
                    .buttonStyle(PlainButtonStyle())
                Button { logIncorrect() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.red.opacity(0.7))
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                Button { logExit(.right) } label: { arrowLabel("arrow.right") }
                    .buttonStyle(PlainButtonStyle())
            }
            Button { logExit(.down) } label: { arrowLabel("arrow.down") }
                .buttonStyle(PlainButtonStyle())
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
        ScrollView {
            VStack(spacing: 20) {
                Text("Rep \(currentRepIndex + 1) of \(totalReps)")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))

                if Self.initialTwoMinuteTransportMode == .multipeer {
                    Text("Connect to the device showing the grid (Display). Keep both devices nearby and allow Local Network if prompted.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
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
                }

                #if DEBUG
                if Self.initialTwoMinuteTransportMode == .relayWebSocket {
                    coachRelayPartnerSection
                }
                #endif

                Color.clear.frame(height: 24)
            }
        }
        .padding(.top, 60)
    }

    #if DEBUG
    /// Relay partner path: join code → `RemoteService` with `WebSocketRemoteTransport` (production-facing DEBUG).
    private var coachRelayPartnerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.25))
            Text("Relay WebSocket (DEBUG)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.cyan.opacity(0.95))
            Text("Enter join code from the iPad display session, then connect.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
            TextField("Join code", text: $coachRelayJoinCodeInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .focused($relayJoinCodeFieldFocused)
                .submitLabel(.go)
                .onSubmit {
                    Task { await startCoachRelayJoin() }
                }
            Button {
                relayJoinCodeFieldFocused = false
                print("[RelayWS-DEBUG][Coach] button tap: Join relay & connect WS")
                Task { await startCoachRelayJoin() }
            } label: {
                Group {
                    if coachRelayJoinBusy {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Join relay & connect WS")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.cyan.opacity(0.85))
                .foregroundColor(.black)
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(
                coachRelayJoinBusy
                    || coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            if let banner = coachRelayJoinBanner, !banner.isEmpty {
                Text(banner)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(coachRelayBannerTextColor(banner))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
            }
            if remoteService.connectionState == .connected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green.opacity(0.95))
                    Text("Relay connected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green.opacity(0.95))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if coachRelayDisplayPeerJoined {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.green.opacity(0.9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Joined display successfully")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green.opacity(0.95))
                        Text("control.peer_joined received")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.green.opacity(0.12))
                .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func coachRelayBannerTextColor(_ banner: String) -> Color {
        if banner.contains("connected") {
            return Color.green.opacity(0.95)
        }
        if banner.contains("Joining") || banner.contains("Connecting") {
            return Color.white.opacity(0.9)
        }
        return Color.orange
    }

    private func startCoachRelayJoin() async {
        relayJoinCodeFieldFocused = false
        let code = coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[RelayWS-DEBUG][Coach] startCoachRelayJoin() entered joinCode=\(code)")
        guard !code.isEmpty else {
            print("[RelayWS-DEBUG][Coach] startCoachRelayJoin() early exit: empty join code")
            return
        }
        await MainActor.run {
            coachRelayJoinBusy = true
            coachRelayJoinError = nil
            coachRelayJoinBanner = "Joining relay…"
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
            transport.onRawTextReceived = { text in
                #if DEBUG
                print("[RelayWS-DEBUG][Coach] received raw: \(text)")
                if text.contains("peer_joined") {
                    print("[RelayWS-DEBUG][Coach] (control.peer_joined in raw frame)")
                    Task { @MainActor in
                        displayPeerJoinedBinding.wrappedValue = true
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
            Text("Results are on the iPad.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Text("Choose the next activity (e.g. Playing Away From Pressure) below.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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
}
