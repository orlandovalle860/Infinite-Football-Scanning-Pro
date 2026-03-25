//
//  OneTouchPassingGetReadyView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Countdown then navigate to Display session.
//

import SwiftUI

struct OneTouchPassingGetReadyView: View {
    let config: OneTouchPassingConfig
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
    @State private var countdownTimer: Timer?

    private var activity: ActivityKind { .oneTouchPassing }

    private var getReadySubtitle: String {
        switch mode {
        case .partner:
            return "Tap Begin for directions, then Start Block. On Display, partner setup runs first; the block countdown starts after the coach connects."
        case .solo, .wall:
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
                router.popToRoot()
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
            OneTouchPassingDisplaySessionView(config: config, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdown = 3
        var remaining = 3
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            remaining -= 1
            DispatchQueue.main.async { countdown = remaining }
            if remaining <= 0 {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    navigateToSession = true
                }
            }
        }
        countdownTimer = t
        RunLoop.main.add(t, forMode: .common)
    }
}
