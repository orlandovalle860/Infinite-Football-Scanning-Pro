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
    @EnvironmentObject private var router: AppRouter
    @AppStorage(AppRole.storageKey) private var appRoleRaw: String = AppRole.player.rawValue
    @State private var partnerSessionActive = false
    @State private var showDisconnectCoachConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach Remote")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Text("Which activity is the player on? Tap the same one as the Display.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 4)

                // Coach Remote: all activities available; navigation uses router so path-based stack works.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    CoachRemoteGridTile(
                        title: "Dribble or Pass",
                        subtitle: "12 reps",
                        icon: "arrow.triangle.branch",
                        route: .dribbleOrPassCoachRemote,
                        router: router
                    )
                    CoachRemoteGridTile(
                        title: "Playing Away From Pressure",
                        subtitle: "12 reps",
                        icon: "exclamationmark.triangle.fill",
                        route: .awayFromPressureCoachRemote,
                        router: router
                    )
                    CoachRemoteGridTile(
                        title: "One-Touch Passing",
                        subtitle: "12 reps",
                        icon: "hand.tap.fill",
                        route: .oneTouchPassingCoachRemote,
                        router: router
                    )
                    CoachRemoteGridTile(
                        title: "2-Minute Test",
                        subtitle: "10 reps",
                        icon: "soccerball",
                        route: .twoMinuteCoachRemote,
                        router: router
                    )
                }
            }
            .padding(20)

            if partnerSessionActive {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ends coach/display connection")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.horizontal, 4)
                    Button {
                        showDisconnectCoachConfirm = true
                    } label: {
                        Text("Disconnect Coach")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.orange.opacity(0.95))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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
        .navigationTitle("Coach Remote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Switch to Player Mode") {
                        let old = appRoleRaw
                        appRoleRaw = AppRole.player.rawValue
                        router.popToRoot()
                        AppRoleDebug.log("role_change reason=switch_to_player old=\(old) new=\(AppRole.player.rawValue) routing=player_flow")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white.opacity(0.9))
                }
                .accessibilityLabel("Device role options")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
        }
        .alert("Disconnect Coach?", isPresented: $showDisconnectCoachConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                TrainingPartnerConnectionCoordinator.shared.endPartnerTrainingSession(reason: "coachRemoteHubEndTrainingSession")
                partnerSessionActive = false
            }
        } message: {
            Text("You'll need to enter a new join code to start another session.")
        }
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
    let route: AppRoute
    @ObservedObject var router: AppRouter

    var body: some View {
        Button {
            router.push(route)
        } label: {
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
