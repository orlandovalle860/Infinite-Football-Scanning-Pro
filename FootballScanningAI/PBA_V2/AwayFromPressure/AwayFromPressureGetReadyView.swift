//
//  AwayFromPressureGetReadyView.swift
//  FootballScanningAI
//
//  PBA V2 — Countdown then navigate to Display session.
//

import SwiftUI

struct AwayFromPressureGetReadyView: View {
    let config: AwayFromPressureConfig
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showLeaveAlert = false
    @State private var countdown: Int? = nil
    @State private var showInstruction = false
    @State private var navigateToSession = false
    @State private var countdownScheduleToken = UUID()

    private var activity: ActivityKind { .awayFromPressure }

    private var getReadySubtitle: String {
        switch mode {
        case .partner:
            return "Tap Begin for directions, then Start Block. Coach stands about 12 yards away from the player. On Display, partner setup runs first; countdown starts after the coach connects."
        case .wall:
            return "Tap Begin for directions, then Start Block. Log from the phone: the Display shows a join code—enter it on the phone to pair with this iPad. Countdown starts after the phone connects."
        case .solo:
            return "Tap Begin for directions, then Start Block. You’ll get a short countdown, then your block begins."
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            if let n = countdown, n > 0 {
                Text("\(n)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            } else if countdown == 0 {
                Text("Go")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
                Spacer()
            } else {
                Text("Get ready")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(getReadySubtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Spacer(minLength: 40)
                Button {
                    if ActivityInstructionContent.shouldShowInstructions(for: activity) {
                        showInstruction = true
                    } else {
                        startCountdown()
                    }
                } label: {
                    Text("Begin")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.yellow)
                        .cornerRadius(18)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 28)
                Spacer()
            }
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .pbaHomeToolbar(router: router)
        .alert("Leave training?", isPresented: $showLeaveAlert) {
            Button("Stay", role: .cancel) {}
            Button("Leave", role: .destructive) {
                // Same as Home: preserve coach↔display relay so Pathway → next activity does not require a new join code.
                router.popToRoot(endingPartnerSession: false)
            }
        } message: {
            Text("Your current block will not be saved.")
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .navigationDestination(isPresented: $showInstruction) {
            ActivityInstructionView(activity: activity, trainingMode: mode) {
                showInstruction = false
                startCountdown()
            }
        }
        .navigationDestination(isPresented: $navigateToSession) {
            AwayFromPressureDisplaySessionView(config: config, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .onDisappear {
            countdownScheduleToken = UUID()
        }
    }

    private func startCountdown() {
        countdownScheduleToken = UUID()
        let token = countdownScheduleToken
        countdown = 3
        scheduleCountdownTick(remaining: 3, token: token)
    }

    private func scheduleCountdownTick(remaining: Int, token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard countdownScheduleToken == token else { return }
            let next = remaining - 1
            countdown = next
            if next <= 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard countdownScheduleToken == token else { return }
                    navigateToSession = true
                }
            } else {
                scheduleCountdownTick(remaining: next, token: token)
            }
        }
    }
}
