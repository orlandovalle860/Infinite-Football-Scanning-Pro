//
//  OneTouchPassingSetupView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Difficulty presets only (no sliders).
//

import SwiftUI

struct OneTouchPassingSetupView: View {
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @State private var difficulty: TestDifficulty = .beginner

    private var config: OneTouchPassingConfig {
        OneTouchPassingConfig.defaultConfig(for: difficulty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Set up")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                Text("Difficulty")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                Picker("", selection: $difficulty) {
                    Text("Beginner").tag(TestDifficulty.beginner)
                    Text("Intermediate").tag(TestDifficulty.standard)
                    Text("Advanced").tag(TestDifficulty.advanced)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                NavigationLink(destination: OneTouchPassingGetReadyView(config: config, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
                ) {
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
        .navigationTitle("One-Touch Passing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}
