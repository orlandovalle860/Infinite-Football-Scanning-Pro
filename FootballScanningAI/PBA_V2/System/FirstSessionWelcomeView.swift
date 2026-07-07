//
//  FirstSessionWelcomeView.swift
//  FootballScanningAI
//
//  First launch: one CTA to start Meet the Ball immediately — no login, no activity picker.
//

import SwiftUI

struct FirstSessionWelcomeView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var headlineVisible = false
    @State private var buttonVisible = false
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Train your decision-making")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(headlineVisible ? 1 : 0)

            Spacer()

            Button {
                guard !isStarting else { return }
                isStarting = true
                FirstSessionOnboardingStore.prepareForImmediateFirstSession()
                AnalyticsManager.shared.track(.twoMinuteTestStarted, playerId: nil)
                router.replace(with: .twoMinuteTest(mode: .solo))
            } label: {
                Text("Start Training")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.yellow)
                    .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .opacity(buttonVisible ? 1 : 0)
            .disabled(isStarting)
            .accessibilityLabel("Start Training")

            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .onAppear {
            AnalyticsManager.shared.track(.introScreenViewed)
            withAnimation(.easeInOut(duration: 0.35)) {
                headlineVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    buttonVisible = true
                }
            }
        }
    }
}
