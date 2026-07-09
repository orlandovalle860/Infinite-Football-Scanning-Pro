//
//  AwayFromPressureSetupView.swift
//  FootballScanningAI
//
//  PBA V2 — Difficulty + partner/wall; Begin -> Get Ready -> Display session.
//

import SwiftUI

struct AwayFromPressureSetupView: View {
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @State private var showInstructions = false
    @State private var navigateToSession = false

    private var loopLevel: Int { 1 }

    private var adaptivePlan: ActivityAdaptivePlan {
        makeActivityAdaptivePlan(from: profileManager.recentTrainSessions(limit: 3))
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

            ResponsiveScrollScreen {
                VStack(spacing: 18) {
                    Text("Playing Away From Pressure")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Put the iPad behind the player.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                        Text("• Player stays inside the square.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                        if mode == .partner {
                            Text("• Coach stands about 12 yards in front with the ball.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Level: \(adaptivePlan.level.rawValue)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("Focus: \(adaptivePlan.focusCue)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.78))
                        Text("Constraints: \(adaptivePlan.constraintsSummary)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.66))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        profileManager.pendingLevelDifficulty = adaptivePlan.modifiers
                        navigateToSession = true
                    } label: {
                        Text("Begin")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .padding(.horizontal, 20)
                            .background(Color.yellow)
                            .cornerRadius(18)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .pbaHomeToolbar(router: router)
        .onAppear {
            print("[SetupScreen AFP] onAppear, router path count = \(router.pathCount)")
            profileManager.pendingLevelDifficulty = adaptivePlan.modifiers
        }
        .navigationDestination(isPresented: $navigateToSession) {
            AwayFromPressureDisplaySessionView(
                config: AwayFromPressureConfig.config(for: adaptivePlan.recommendedDifficulty, loopLevel: loopLevel, levelModifiers: profileManager.pendingLevelDifficulty),
                mode: mode,
                settingsViewModel: settingsViewModel,
                profileManager: profileManager
            )
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
                .onAppear {
                    profileManager.pendingLevelDifficulty = nil
                }
        }
    }
}
