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
    @State private var difficulty: TestDifficulty = TestDifficulty.loadFromUserDefaults()
    @State private var showInstructions = false
    @State private var navigateToSession = false

    private var loopLevel: Int {
        GuidedCurriculumEngine.currentProgress(playerId: playerStore.selectedPlayerId).loop
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            Text("Set up")
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
                    Text("• Coach stands 5–7 yards in front with the ball.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.top, 4)

            Text("Difficulty")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 12)
            Picker("Difficulty", selection: $difficulty) {
                Text("Beginner").tag(TestDifficulty.beginner)
                Text("Standard").tag(TestDifficulty.standard)
                Text("Advanced").tag(TestDifficulty.advanced)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 28)
            .onChange(of: difficulty) { _, newValue in
                newValue.saveToUserDefaults()
            }

            Spacer(minLength: 8)

            Button {
                if ActivityInstructionContent.shouldShowInstructions(for: .awayFromPressure) {
                    showInstructions = true
                } else {
                    navigateToSession = true
                }
            } label: {
                Text("Continue")
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
        }
        .navigationDestination(isPresented: $showInstructions) {
            ActivityInstructionView(activity: .awayFromPressure, trainingMode: mode) {
                showInstructions = false
                navigateToSession = true
            }
        }
        .navigationDestination(isPresented: $navigateToSession) {
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: difficulty, loopLevel: loopLevel), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }
}
