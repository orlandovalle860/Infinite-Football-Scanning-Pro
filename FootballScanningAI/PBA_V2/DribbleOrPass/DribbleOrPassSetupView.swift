//
//  DribbleOrPassSetupView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Difficulty presets only (no sliders).
//

import SwiftUI
import Combine

struct DribbleOrPassSetupView: View {
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

    private var config: DribbleOrPassConfig {
        DribbleOrPassConfig.defaultConfig(for: adaptivePlan.recommendedDifficulty, loopLevel: loopLevel, levelModifiers: profileManager.pendingLevelDifficulty)
    }

    private var adaptivePlan: ActivityAdaptivePlan {
        makeActivityAdaptivePlan(from: profileManager.recentTrainSessions(limit: 3))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Dribble or Pass")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("• Stand about 12 yards from your partner or wall.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Text("• Keep the ball moving with one action per rep.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
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
                .padding(.horizontal, 24)
                .padding(.top, 4)

                Button {
                    profileManager.pendingLevelDifficulty = adaptivePlan.modifiers
                    navigateToSession = true
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
                .padding(.top, 16)

                Spacer(minLength: 40)
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
        .navigationTitle("Dribble or Pass")
        .navigationBarTitleDisplayMode(.inline)
        .pbaHomeToolbar(router: router)
        .onAppear {
            print("[SetupScreen DOP] onAppear, router path count = \(router.pathCount)")
            profileManager.pendingLevelDifficulty = adaptivePlan.modifiers
        }
        .navigationDestination(isPresented: $navigateToSession) {
            DribbleOrPassDisplaySessionView(config: config, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
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
