//
//  AwayFromPressureRoleSelectionView.swift
//  FootballScanningAI
//
//  PBA V2 — Playing Away From Pressure V1: choose Display or Coach remote.
//

import SwiftUI

struct AwayFromPressureRoleSelectionView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            Text("Playing Away From Pressure")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text("Use this device as:")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal)

            Text("Choose one. The other device should choose the other role.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(spacing: 16) {
                NavigationLink(destination: TrainingModeSelectionView(activityTitle: "Playing Away From Pressure") { mode in
                    AwayFromPressureSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                }
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "tv")
                            Text("Display")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        Text("This device shows the grid and danger zone. Place it behind the player.")
                            .font(.footnote)
                            .foregroundColor(.black.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    .background(Color.yellow)
                    .cornerRadius(18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 28)

                NavigationLink(destination: AwayFromPressureCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "hand.raised")
                            Text("Coach remote")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        Text("This device starts each rep and logs exit direction. Tap Connect to Display first.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 28)
            }

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
    }
}
