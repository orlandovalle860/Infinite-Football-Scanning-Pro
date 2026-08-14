//
//  CoachRemoteHubRelayPairingView.swift
//  FootballScanningAI
//
//  Coach Remote — join relay session before activity selection (display must be connected).
//

import SwiftUI

/// Relay join step for Coach Remote hub. Mirrors per-activity coach join logic without starting an activity.
struct CoachRemoteHubRelayPairingView: View {
    @EnvironmentObject private var router: AppRouter

    @ObservedObject private var coachRelayRemoteService = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService

    @State private var coachRelayJoinCodeInput = ""
    @State private var coachRelayJoinError: String?
    @State private var coachRelayJoinBusy = false
    @State private var coachRelayJoinBanner: String?
    @FocusState private var relayJoinCodeFieldFocused: Bool
    @State private var coachRelayDisplayPeerJoined = false
    @State private var didAttemptCoachRelayAutoReconnect = false

    private var remoteService: RemoteService {
        TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Join your display")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        PartnerLinkPassiveStatusLine(role: .coach)
                        Text("Enter the code from the iPad to connect. You'll choose the activity next.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)

                    PartnerRelayCoachJoinSection(
                        joinCodeInput: $coachRelayJoinCodeInput,
                        joinFieldFocused: $relayJoinCodeFieldFocused,
                        joinBusy: coachRelayJoinBusy,
                        joinBanner: coachRelayJoinBanner,
                        onJoin: {
                            Task { await startCoachRelayJoin() }
                        }
                    )
                    .padding(.top, 8)

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            PartnerRelayLifecycleBannerOverlay()
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .onAppear {
            didAttemptCoachRelayAutoReconnect = false
            TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
            attemptCoachRelayAutoReconnectIfNeeded()
        }
        .onChange(of: remoteService.connectionState) { oldState, newState in
            guard oldState == .connected, newState == .disconnected else { return }
            if TrainingPartnerConnectionCoordinator.shared.shouldPersistPartnerPairing {
                return
            }
            coachRelayDisplayPeerJoined = false
        }
    }

    private func startCoachRelayJoin() async {
        let code = coachRelayJoinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        await MainActor.run {
            coachRelayJoinBusy = true
            coachRelayJoinError = nil
            coachRelayJoinBanner = PartnerRelayJoinCodeConfig.joiningStatusBannerText
            coachRelayDisplayPeerJoined = false
        }
        do {
            let joined = try await WebSocketSessionAPI.joinSession(joinCode: code)
            await MainActor.run {
                TrainingPartnerConnectionCoordinator.shared.beginPartnerTrainingSessionIfNeeded()
                TrainingPartnerConnectionCoordinator.shared.installCoachRelayAfterHTTPJoin(
                    joinCode: code,
                    sessionId: joined.sessionId,
                    coachToken: joined.coachToken,
                    wsUrl: joined.wsUrl,
                    expiresAt: joined.expiresAt,
                    connect: true
                )
                coachRelayDisplayPeerJoined = TrainingPartnerConnectionCoordinator.shared.coachRelayDisplayPeerPresent
                coachRelayJoinBanner = nil
                coachRelayJoinBusy = false
            }
        } catch {
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
            }
        }
    }

    private func attemptCoachRelayAutoReconnectIfNeeded() {
        guard !didAttemptCoachRelayAutoReconnect else { return }
        let coord = TrainingPartnerConnectionCoordinator.shared
        guard !coord.isPartnerTransportLinkLive else { return }
        let hasMemoryCode = !(coord.lastCoachRelayJoinCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPersisted = PartnerCoachResumeStore.loadCredentialsForReconnect() != nil
        guard hasMemoryCode || hasPersisted else { return }
        didAttemptCoachRelayAutoReconnect = true
        if let code = coord.lastCoachRelayJoinCode, !code.isEmpty {
            coachRelayJoinCodeInput = code
        }
        Task {
            await TrainingPartnerConnectionCoordinator.shared.attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(
                reason: "hub_pairing_onAppear"
            )
        }
    }
}

/// Requires an active coach↔display link before showing a Coach Remote activity screen (join UI otherwise).
struct CoachRemoteActivityConnectionGate<Content: View>: View {
    @EnvironmentObject private var router: AppRouter
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if CoachRemoteSessionStartGate.coachDeviceIsPresent() {
                content()
            } else {
                CoachRemoteHubRelayPairingView()
                    .environmentObject(router)
            }
        }
    }
}
