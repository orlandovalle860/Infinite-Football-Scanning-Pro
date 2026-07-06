//
//  IPadPlayerDisplayConnectedStandbyView.swift
//  FootballScanningAI
//
//  Player iPad when coach link is live: display-only — no training or role-switch UI.
//

import SwiftUI

struct IPadPlayerDisplayConnectedStandbyView: View {
    /// Mirrors ``CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive()`` so the confirmation animation tracks relay / coach socket state, not Multipeer or arbitrary re-renders.
    var coachLinkActive: Bool

    /// UI-only: brief “Connected” beat before showing the waiting subtitle (see `.task(id:)`).
    @State private var showWaitingSubtitle = false

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
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
}
