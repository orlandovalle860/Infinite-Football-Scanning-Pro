//
//  IPadPlayerDisplayConnectedStandbyView.swift
//  FootballScanningAI
//
//  Player iPad when coach link is live: display-only — waiting for coach to start a session.
//  Disconnect returns to Home so Solo / re-pair is always reachable without force-quit.
//

import SwiftUI

struct IPadPlayerDisplayConnectedStandbyView: View {
    /// Mirrors ``CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive()`` so the confirmation animation tracks relay / coach socket state, not Multipeer or arbitrary re-renders.
    var coachLinkActive: Bool

    /// UI-only: brief “Connected” beat before showing the waiting subtitle (see `.task(id:)`).
    @State private var showWaitingSubtitle = false
    @State private var showDisconnectConfirmation = false

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger

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

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                Text("Connected")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if showWaitingSubtitle {
                    Text("Waiting for coach to start session…")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: 0)

                Button {
                    showDisconnectConfirmation = true
                } label: {
                    Text("Disconnect")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Disconnect")
                .accessibilityHint("Ends the coach connection and returns to Home")
                .padding(.bottom, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .alert("Disconnect from Coach?", isPresented: $showDisconnectConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                disconnectFromCoachAndReturnHome()
            }
        } message: {
            Text("This will end the current connection and return you to the VisionPlay Home screen.")
        }
        .task(id: coachLinkActive) {
            guard coachLinkActive else {
                showWaitingSubtitle = false
                return
            }
            showWaitingSubtitle = false
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, coachLinkActive else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                showWaitingSubtitle = true
            }
        }
    }

    private func disconnectFromCoachAndReturnHome() {
        TrainingPartnerConnectionCoordinator.shared.disconnectPlayerDisplayFromCoach(
            reason: "iPadConnectedStandby.disconnect"
        )
        HomeNavigationAction.goHome(router: router, popToRootTrigger: popToRootTrigger)
    }
}
