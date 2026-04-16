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

    private var loopLevel: Int {
        GuidedCurriculumEngine.currentProgress(playerId: playerStore.selectedPlayerId).loop
    }

    private var adaptivePlan: ActivityAdaptivePlan {
        makeActivityAdaptivePlan(from: profileManager.recentTrainSessions(limit: 3))
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            Text("Playing Away From Pressure")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(.horizontal, 28)

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
            .padding(.top, 4)

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
            .padding(.horizontal, 28)
            .padding(.top, 2)

            Spacer(minLength: 8)

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
            .padding(.horizontal, 28)

            Button("View Instructions") {
                showInstructions = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white.opacity(0.82))
            .buttonStyle(.plain)

            Spacer()
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
        .onAppear {
            print("[SetupScreen AFP] onAppear, router path count = \(router.pathCount)")
            profileManager.pendingLevelDifficulty = adaptivePlan.modifiers
        }
        .navigationDestination(isPresented: $showInstructions) {
            ActivityInstructionView(activity: .awayFromPressure, trainingMode: mode) {
                showInstructions = false
                navigateToSession = true
            }
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
