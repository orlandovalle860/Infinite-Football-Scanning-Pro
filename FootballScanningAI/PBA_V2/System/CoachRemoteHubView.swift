//
//  CoachRemoteHubView.swift
//  FootballScanningAI
//
//  PBA V2 — Coach remote hub: choose which activity the player is on, then open that activity’s remote.
//

import SwiftUI
import UIKit

struct CoachRemoteHubView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var connectionManager: ConnectionManager
    @ObservedObject private var coachRelayRemoteService = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService
    @ObservedObject private var relayDisplaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
    @AppStorage(AppRole.storageKey) private var appRoleRaw: String = AppRole.player.rawValue
    @AppStorage("coachRemoteLastUsedActivityV1") private var lastUsedActivityKey: String = ""
    @State private var partnerSessionActive = false
    @State private var showDisconnectCoachConfirm = false

    private var coachLinkReadyForActivities: Bool {
        CoachRemoteSessionStartGate.coachDeviceIsPresent()
    }

    private struct CoachRemoteActivityItem: Identifiable, Equatable {
        let id: String
        let activityKind: ActivityKind?
        let title: String
        let subtitle: String
        let icon: String
        let route: AppRoute
    }

    private static let activityItems: [CoachRemoteActivityItem] = [
        CoachRemoteActivityItem(
            id: "dribble_or_pass",
            activityKind: .dribbleOrPass,
            title: "Dribble or Pass",
            subtitle: "12 reps",
            icon: "arrow.triangle.branch",
            route: .dribbleOrPassCoachRemote
        ),
        CoachRemoteActivityItem(
            id: "away_from_pressure",
            activityKind: .awayFromPressure,
            title: "Playing Away From Pressure",
            subtitle: "12 reps",
            icon: "exclamationmark.triangle.fill",
            route: .awayFromPressureCoachRemote
        ),
        CoachRemoteActivityItem(
            id: "one_touch_passing",
            activityKind: .oneTouchPassing,
            title: "One-Touch Passing",
            subtitle: "12 reps",
            icon: "hand.tap.fill",
            route: .oneTouchPassingCoachRemote
        ),
        CoachRemoteActivityItem(
            id: "two_minute_test",
            activityKind: .twoMinuteTest,
            title: ActivityKind.twoMinuteTest.displayName,
            subtitle: "10 reps",
            icon: "soccerball",
            route: .twoMinuteCoachRemote
        )
    ]

    private var recommendedActivity: CoachRemoteActivityItem {
        if let last = ActivityKind(rawValue: lastUsedActivityKey),
           let match = Self.activityItems.first(where: { $0.activityKind == last }) {
            return match
        }
        return Self.activityItems[0]
    }

    private var otherActivities: [CoachRemoteActivityItem] {
        Self.activityItems.filter { $0.id != recommendedActivity.id }
    }

    var body: some View {
        Group {
            if coachLinkReadyForActivities {
                activitySelectionStack
            } else {
                CoachRemoteHubRelayPairingView()
                    .environmentObject(router)
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
        .onChange(of: coachRelayRemoteService.connectionState) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
        }
        .onChange(of: connectionManager.connectedPeerName) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
        }
        .onChange(of: relayDisplaySession.isCoachPaired) { _, _ in
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

    private var activitySelectionStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Session")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Tap the activity to start the session")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recommended Next")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)

                        CoachRemoteGridTile(
                            title: recommendedActivity.title,
                            subtitle: recommendedActivity.subtitle,
                            icon: recommendedActivity.icon,
                            isLastUsed: lastUsedActivityKey == recommendedActivity.id,
                            route: recommendedActivity.route,
                            isProminent: true,
                            onTap: { lastUsedActivityKey = recommendedActivity.id },
                            router: router
                        )
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Other Activities")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(otherActivities) { activity in
                                CoachRemoteGridTile(
                                    title: activity.title,
                                    subtitle: activity.subtitle,
                                    icon: activity.icon,
                                    isLastUsed: lastUsedActivityKey == activity.id,
                                    route: activity.route,
                                    onTap: { lastUsedActivityKey = activity.id },
                                    router: router
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    if coachLinkReadyForActivities, partnerSessionActive {
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
            }
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
    let isLastUsed: Bool
    let route: AppRoute
    var isProminent: Bool = false
    let onTap: () -> Void
    @ObservedObject var router: AppRouter

    var body: some View {
        Button {
            guard CoachRemoteSessionStartGate.coachDeviceIsPresent() else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
            router.push(route)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.yellow)
                if isLastUsed {
                    Text("Last Used")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.95))
                        .cornerRadius(8)
                }
                Text(title)
                    .font(isProminent ? .headline.weight(.bold) : .subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(isProminent ? .caption.weight(.semibold) : .caption2)
                    .foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: isProminent ? 132 : 100)
            .background(Color.white.opacity(0.1))
            .cornerRadius(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(CoachRemoteTileButtonStyle())
    }
}

private struct CoachRemoteTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
