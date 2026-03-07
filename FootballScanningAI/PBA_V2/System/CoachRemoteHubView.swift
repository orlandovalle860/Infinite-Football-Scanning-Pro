//
//  CoachRemoteHubView.swift
//  FootballScanningAI
//
//  PBA V2 — Coach remote hub: choose which activity the player is on, then open that activity’s remote.
//

import SwiftUI

struct CoachRemoteHubView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach Remote")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text(hasCompletedInitialTest
                         ? "Which activity is the player on? Tap the same one as the Display."
                         : "Start with the 2-Minute Test. Other activities unlock after the test is completed once.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 4)

                if hasCompletedInitialTest {
                    // All four in a 2x2 grid so nothing is “below the fold” or feels secondary
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        CoachRemoteGridTile(
                            title: "Dribble or Pass",
                            subtitle: "12 reps",
                            icon: "arrow.triangle.branch",
                            destination: AnyView(DribbleOrPassCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager))
                        )
                        CoachRemoteGridTile(
                            title: "Playing Away From Pressure",
                            subtitle: "12 reps",
                            icon: "exclamationmark.triangle.fill",
                            destination: AnyView(AwayFromPressureCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager))
                        )
                        CoachRemoteGridTile(
                            title: "One-Touch Passing",
                            subtitle: "12 reps",
                            icon: "hand.tap.fill",
                            destination: AnyView(OneTouchPassingCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager))
                        )
                        CoachRemoteGridTile(
                            title: "2-Minute Test",
                            subtitle: "10 reps",
                            icon: "star.circle.fill",
                            destination: AnyView(TwoMinuteCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager))
                        )
                    }
                } else {
                    NavigationLink(destination: TwoMinuteCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)) {
                        CoachRemoteHubRow(title: "2-Minute Test", subtitle: "10 reps • Star in one gate", icon: "star.circle.fill")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
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
        .navigationTitle("Coach Remote")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

private struct CoachRemoteHubRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.yellow)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
}

private struct CoachRemoteGridTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let destination: AnyView

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.yellow)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 100)
            .background(Color.white.opacity(0.1))
            .cornerRadius(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
