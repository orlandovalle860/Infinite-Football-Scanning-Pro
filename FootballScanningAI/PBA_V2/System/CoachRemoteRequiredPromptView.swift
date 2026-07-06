import SwiftUI

/// Fullscreen ready state on player iPad when pairing is needed: join code, aligned with iPhone as control center. Dismisses when the coach link is live.
struct CoachRemoteRequiredPromptView: View {
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController
    @EnvironmentObject private var router: AppRouter
    @AppStorage(hasSeenIntroKey) private var hasSeenIntro = false
    @ObservedObject private var relayDisplaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
    @ObservedObject private var coachRelayRemoteService = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService

    private var displayedJoinCode: String? {
        let trimmed = relayDisplaySession.joinCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Relay-only coach link on the display (no Multipeer). Dismisses when the phone pairs or coach relay socket is live.
    private var coachLinkActive: Bool {
        CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive()
    }

    var body: some View {
        Group {
            if !PBASessionFlowPolicy.lastSelectedTrainingMode().needsCoachRemoteJoinCodeFlow {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        coachRemoteRequiredPrompt.dismiss()
                    }
            } else {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.yellow)
                Text("This iPad is ready.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Start your session on your phone to begin.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                if let code = displayedJoinCode {
                    VStack(spacing: 10) {
                        Text("Join code")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(code)
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.yellow.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                                    )
                            )
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                if !coachLinkActive {
                    Text("Enter the join code on your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .frame(maxWidth: 520)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            tryDismissWhenCoachLinkedOnPlayerPad()
            tryAutoEnterSessionIfNeeded()
        }
        .onChange(of: relayDisplaySession.isCoachPaired) { _, _ in
            tryDismissWhenCoachLinkedOnPlayerPad()
            tryAutoEnterSessionIfNeeded()
        }
        .onChange(of: coachRelayRemoteService.connectionState) { _, _ in
            tryDismissWhenCoachLinkedOnPlayerPad()
            tryAutoEnterSessionIfNeeded()
        }
        .onChange(of: coachRemoteRequiredPrompt.pendingSessionRoute) { _, _ in
            tryDismissWhenCoachLinkedOnPlayerPad()
            tryAutoEnterSessionIfNeeded()
        }
            }
        }
    }

    /// Player iPad: auto-dismiss join prompt when the coach link comes live (sessions are not auto-pushed from this device).
    private func tryDismissWhenCoachLinkedOnPlayerPad() {
        guard coachRemoteRequiredPrompt.isPresented else { return }
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard coachLinkActive else { return }
        // Join sheet is often presented over tablet intro; advance past intro so root becomes passive standby, not “Start Training”.
        hasSeenIntro = true
        coachRemoteRequiredPrompt.dismiss()
    }

    private func tryAutoEnterSessionIfNeeded() {
        if CoachRemoteSessionStartGate.isPadPlayerRole() { return }
        guard coachRemoteRequiredPrompt.isPresented,
              coachRemoteRequiredPrompt.pendingSessionRoute != nil,
              coachLinkActive else { return }
        coachRemoteRequiredPrompt.performAutoEnterPendingSession(router: router)
    }
}
