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
    @ObservedObject private var partnerCoordinator = TrainingPartnerConnectionCoordinator.shared
    @AppStorage(AppRole.storageKey) private var appRoleRaw: String = AppRole.player.rawValue
    @AppStorage("coachRemoteLastUsedActivityV1") private var lastUsedActivityKey: String = ""
    @AppStorage(VisionPlayGuideWelcomeStore.hasSeenKey) private var hasSeenGuideWelcome = false
    @State private var partnerSessionActive = false
    @State private var showDisconnectCoachConfirm = false
    @State private var activityTapBlockedMessage: String?
    @State private var showGuideWelcome = false
    @State private var guidePresentation: VisionPlayGuidePresentation?

    private var coachLinkReadyForActivities: Bool {
        CoachRemoteHubLaunchPolicy.canOpenActivitySelection
    }

    private struct CoachRemoteActivityItem: Identifiable, Equatable {
        let id: String
        let activityKind: ActivityKind?
        let title: String
        let icon: String
        let route: AppRoute
    }

    private static let activityItems: [CoachRemoteActivityItem] = [
        CoachRemoteActivityItem(
            id: "dribble_or_pass",
            activityKind: .dribbleOrPass,
            title: ActivityKind.dribbleOrPass.displayName,
            icon: "arrow.triangle.branch",
            route: .dribbleOrPassCoachRemote
        ),
        CoachRemoteActivityItem(
            id: "away_from_pressure",
            activityKind: .awayFromPressure,
            title: ActivityKind.awayFromPressure.displayName,
            icon: "exclamationmark.triangle.fill",
            route: .awayFromPressureCoachRemote
        ),
        CoachRemoteActivityItem(
            id: "one_touch_passing",
            activityKind: .oneTouchPassing,
            title: ActivityKind.oneTouchPassing.displayName,
            icon: "hand.tap.fill",
            route: .oneTouchPassingCoachRemote
        ),
        CoachRemoteActivityItem(
            id: "two_minute_test",
            activityKind: .twoMinuteTest,
            title: ActivityKind.twoMinuteTest.displayName,
            icon: "figure.run",
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
            // Temporary Partner flow (pushed from Home while still AppRole.player): clear Done path home.
            if AppRole.resolved(from: appRoleRaw) == .player {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        exitTemporaryCoachRemoteToHome()
                    }
                    .foregroundColor(.white.opacity(0.9))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Switch to Player Mode") {
                        let old = appRoleRaw
                        appRoleRaw = AppRole.player.rawValue
                        router.popToRoot(endingPartnerSession: true)
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
        .sheet(isPresented: $showGuideWelcome) {
            VisionPlayGuideWelcomeSheet(
                onViewGuide: {
                    hasSeenGuideWelcome = true
                    showGuideWelcome = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guidePresentation = .page(.welcome)
                    }
                },
                onSkip: {
                    hasSeenGuideWelcome = true
                    showGuideWelcome = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $guidePresentation) { presentation in
            VisionPlayGuideView(initialPage: presentation.initialPage)
        }
        .onAppear {
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
            Task {
                await partnerCoordinator.attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(reason: "coach_hub_onAppear")
            }
            openCoachRemoteForLiveTimedSessionIfNeeded()
            presentGuideWelcomeIfNeeded()
        }
        .onChange(of: coachRelayRemoteService.connectionState) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
            openCoachRemoteForLiveTimedSessionIfNeeded()
        }
        .onChange(of: connectionManager.connectedPeerName) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
        }
        .onChange(of: relayDisplaySession.isCoachPaired) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
        }
        .onChange(of: partnerCoordinator.isDisplayRepEngineReady) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
            openCoachRemoteForLiveTimedSessionIfNeeded()
        }
        .onChange(of: partnerCoordinator.currentTimedSessionActivityId) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
            Task { await partnerCoordinator.attemptCoachRelayAutoReconnectFromStoredJoinCodeIfNeeded(reason: "timedSessionActive") }
            openCoachRemoteForLiveTimedSessionIfNeeded()
        }
        .onChange(of: partnerCoordinator.coachRelayDisplayPeerPresent) { _, _ in
            partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
            openCoachRemoteForLiveTimedSessionIfNeeded()
        }
        .alert("Not connected yet", isPresented: Binding(
            get: { activityTapBlockedMessage != nil },
            set: { if !$0 { activityTapBlockedMessage = nil } }
        )) {
            Button("OK", role: .cancel) { activityTapBlockedMessage = nil }
        } message: {
            Text(activityTapBlockedMessage ?? "Enter the join code and wait for the display to connect.")
        }
        .alert("Disconnect Coach?", isPresented: $showDisconnectCoachConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                TrainingPartnerConnectionCoordinator.shared.endPartnerTrainingSession(reason: "coachRemoteHubEndTrainingSession")
                partnerSessionActive = false
                // Temporary Partner entry: leave the coach stack and return to Player Home.
                if AppRole.resolved(from: appRoleRaw) == .player {
                    router.popToRoot(endingPartnerSession: false)
                }
            }
        } message: {
            Text("You'll need to enter a new join code to start another session.")
        }
    }

    /// Leave a Home-pushed Coach Remote flow without permanently changing AppRole.
    /// Done exits the coach stack only — pairing stays until Disconnect.
    private func exitTemporaryCoachRemoteToHome() {
        partnerSessionActive = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
        router.popToRoot(endingPartnerSession: false)
    }

    private func presentGuideWelcomeIfNeeded() {
        // Temporary Partner push from Home already had a chance to show the welcome on Home.
        guard AppRole.resolved(from: appRoleRaw) == .coachRemote else { return }
        guard !hasSeenGuideWelcome else { return }
        guard !showGuideWelcome else { return }
        showGuideWelcome = true
    }

    /// Display started / resumed a timed partner session (e.g. Train Again) — open the matching coach remote from the hub.
    private func openCoachRemoteForLiveTimedSessionIfNeeded() {
        guard partnerCoordinator.isPartnerTrainingSessionActive else { return }
        guard CoachRemoteHubLaunchPolicy.canOpenActivitySelection else { return }
        guard isOnCoachHubSurface else { return }
        guard let activityId = partnerCoordinator.currentTimedSessionActivityId,
              let activity = ActivityKind.fromSessionActivityId(activityId) else { return }
        guard partnerCoordinator.isDisplayRepEngineReady else { return }
        let route = CoachRemoteHubLaunchPolicy.coachRemoteRoute(for: activity)
        guard router.path.last != route else { return }
        router.push(route)
    }

    /// Coach-role root hub (`path` empty) or hub pushed from player Home (`path` ends with `.coachRemote`).
    private var isOnCoachHubSurface: Bool {
        router.path.isEmpty || router.path.last == .coachRemote
    }

    private func openCoachActivity(_ item: CoachRemoteActivityItem) {
        guard CoachRemoteHubLaunchPolicy.canOpenActivitySelection else {
            #if DEBUG
            print("[CoachHub] activity tile blocked — coach link not live")
            #endif
            activityTapBlockedMessage = "Enter the join code and wait until the display shows as connected, then try again."
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        lastUsedActivityKey = item.id
        if let activity = item.activityKind {
            partnerCoordinator.beginCoachHubActivityLaunch(activity: activity)
        } else {
            partnerCoordinator.restoreCoachTimedSessionMirrorIfNeeded()
        }
        if router.path.last == item.route {
            // Already on this remote (e.g. failed pop after end) — force a fresh push cycle.
            router.popLast()
        }
        router.push(item.route)
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
                            icon: recommendedActivity.icon,
                            isLastUsed: lastUsedActivityKey == recommendedActivity.id,
                            route: recommendedActivity.route,
                            isProminent: true,
                            onTap: { openCoachActivity(recommendedActivity) }
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
                                    icon: activity.icon,
                                    isLastUsed: lastUsedActivityKey == activity.id,
                                    route: activity.route,
                                    onTap: { openCoachActivity(activity) }
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

private struct CoachRemoteGridTile: View {
    let title: String
    let icon: String
    let isLastUsed: Bool
    let route: AppRoute
    var isProminent: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: isProminent ? 14 : 12) {
                Image(systemName: icon)
                    .font(isProminent ? .title : .title2)
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
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: isProminent ? 120 : 96)
            .padding(14)
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
