//
//  PBACurriculumView.swift
//  FootballScanningAI
//
//  PBA V2 — SCREEN 9 CURRICULUM VIEW. Perception Training Path: 3 activities. Back → HomeDashboardView.
//

import SwiftUI

struct PBACurriculumView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var navigateToRole = false
    @State private var selectedActivityForRole: ActivityKind = .awayFromPressure

    private var selectedPlayerId: UUID? { playerStore.selectedPlayerId }

    /// Activity the player is currently recommended to train (for progress indicator).
    private var recommendedNext: ActivityKind {
        if !progressStore.isReady(activity: .awayFromPressure, playerId: selectedPlayerId) {
            return .awayFromPressure
        }
        if !progressStore.isReady(activity: .dribbleOrPass, playerId: selectedPlayerId) {
            return .dribbleOrPass
        }
        return .oneTouchPassing
    }

    private let pathLineColor = Color.white.opacity(0.35)
    private let pathLineWidth: CGFloat = 2
    private let iconColumnWidth: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Perception Training Path")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                pathStep(
                    activityName: "Playing Away From Pressure",
                    coachingDescription: "Read danger and escape.",
                    activity: .awayFromPressure,
                    showLineBelow: true,
                    onTrain: { selectedActivityForRole = .awayFromPressure; navigateToRole = true }
                )
                pathStep(
                    activityName: "Dribble or Pass",
                    coachingDescription: "Choose action under pressure.",
                    activity: .dribbleOrPass,
                    showLineBelow: true,
                    onTrain: { selectedActivityForRole = .dribbleOrPass; navigateToRole = true }
                )
                pathStep(
                    activityName: "One-Touch Passing",
                    coachingDescription: "Decide before the ball arrives.",
                    activity: .oneTouchPassing,
                    showLineBelow: false,
                    onTrain: { selectedActivityForRole = .oneTouchPassing; navigateToRole = true }
                )

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
        .navigationTitle("Path")
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
        .navigationDestination(isPresented: $navigateToRole) {
            roleDestination(for: selectedActivityForRole)
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
    }

    /// One rung of the ladder: progression icon (✓ ● ○) + line on the left, activity card on the right.
    private func pathStep(activityName: String, coachingDescription: String, activity: ActivityKind, showLineBelow: Bool, onTrain: @escaping () -> Void) -> some View {
        let unlocked = progressStore.isUnlocked(activity: activity, playerId: selectedPlayerId)
        let summary = progressStore.lastBlockSummary(activity: activity, playerId: selectedPlayerId)
        let hasCompletedBlock = progressStore.last(activity, playerId: selectedPlayerId) != nil
        let isCurrent = (recommendedNext == activity)

        @ViewBuilder
        func progressIconView() -> some View {
            if hasCompletedBlock {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isCurrent {
                Image(systemName: "circle.fill")
                    .foregroundColor(.yellow)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
        }

        let cardContent = VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activityName)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(coachingDescription)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                if let s = summary {
                    Text(s)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            if unlocked {
                Button(action: onTrain) {
                    Text("Train")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.yellow)
                        .cornerRadius(10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        .background(Color.white.opacity(unlocked ? 0.12 : 0.06))
        .cornerRadius(16)

        return HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                progressIconView()
                    .font(.title2)
                if showLineBelow {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(pathLineColor)
                            .frame(width: pathLineWidth, height: 24)
                        Spacer(minLength: 0)
                    }
                    .frame(width: iconColumnWidth)
                    .padding(.top, 4)
                }
            }
            .frame(width: iconColumnWidth)
            .padding(.top, 2)

            cardContent
        }
        .padding(.horizontal, 24)
        .padding(.bottom, showLineBelow ? 0 : 8)
    }

    @ViewBuilder
    private func roleDestination(for activity: ActivityKind) -> some View {
        switch activity {
        case .twoMinuteTest:
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .awayFromPressure:
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .dribbleOrPass:
            DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .oneTouchPassing:
            OneTouchPassingRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }
}
