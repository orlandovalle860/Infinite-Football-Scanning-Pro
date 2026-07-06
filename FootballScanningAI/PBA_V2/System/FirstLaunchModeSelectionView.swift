//
//  FirstLaunchModeSelectionView.swift
//  FootballScanningAI
//
//  One-time Solo vs Coach Remote (partner) choice. Skipped for returning installs (see ``PBASessionFlowPolicy/migrateTrainingModeOnboardingIfNeeded()``).
//

import SwiftUI

struct FirstLaunchModeSelectionView: View {
    var onComplete: () -> Void
    @AppStorage(AppStorageKeys.hasLaunchedBefore) private var hasLaunchedBefore = false
    /// Skips marketing ``IntroOnboardingView`` so the user lands on Home immediately after choosing a mode.
    @AppStorage(hasSeenIntroKey) private var hasSeenIntro = false
    @State private var selectedMode: TrainingMode?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("How do you want to train?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                Text("You can change this anytime on Home.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(.horizontal, 24)

            VStack(spacing: 14) {
                Button {
                    selectedMode = .solo
                    PBASessionFlowPolicy.persistTrainingMode(.solo)
                    hasLaunchedBefore = true
                    hasSeenIntro = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onComplete()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Train on your own")
                            .font(.headline)
                        Text("Solo wall or self-guided training")
                            .font(.footnote)
                            .foregroundColor(.black.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(16)
                    .scaleEffect(selectedMode == .solo ? 0.96 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: selectedMode)
                }
                .buttonStyle(.plain)
                .disabled(selectedMode != nil)
                .accessibilityLabel("Train on your own, solo mode")

                Button {
                    selectedMode = .partner
                    PBASessionFlowPolicy.persistTrainingMode(.partner)
                    hasLaunchedBefore = true
                    hasSeenIntro = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onComplete()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Train with a Coach")
                            .font(.headline)
                        Text("Use a second device to run sessions")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .scaleEffect(selectedMode == .partner ? 0.96 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: selectedMode)
                }
                .buttonStyle(.plain)
                .disabled(selectedMode != nil)
                .accessibilityLabel("Train with a coach, partner mode")
            }
            .padding(.horizontal, 22)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.08, green: 0.08, blue: 0.14)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
    }
}
