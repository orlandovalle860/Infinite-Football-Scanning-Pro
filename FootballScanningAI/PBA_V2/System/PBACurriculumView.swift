//
//  PBACurriculumView.swift
//  FootballScanningAI
//
//  PBA V2 — SCREEN 9 CURRICULUM VIEW. Perception Training Path: 3 activities.
//  Row-based layout: each row = ladder segment (dot + connectors) + activity card. No single long vertical line.
//

import SwiftUI

struct PBACurriculumView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var progressStore: ProgressStore
    @ObservedObject var playerStore: PlayerStore
    @ObservedObject var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(settingsViewModel: SettingsViewModel, profileManager: UserProfileManager, progressStore: ProgressStore, playerStore: PlayerStore, popToRootTrigger: PopToRootTrigger) {
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        self.progressStore = progressStore
        self.playerStore = playerStore
        self.popToRootTrigger = popToRootTrigger
        #if DEBUG
        print("[PBACurriculumView] init (router from environment)")
        #endif
    }

    private static let activities: [(title: String, subtitle: String, activity: ActivityKind)] = [
        ("Playing Away From Pressure", "Recognize pressure and escape quickly.", .awayFromPressure),
        ("Dribble or Pass", "Choose the correct attacking action.", .dribbleOrPass),
        ("One-Touch Passing", "Decide and execute instantly.", .oneTouchPassing)
    ]

    private let timelineIndicatorWidth: CGFloat = 48
    private let rowSpacing: CGFloat = 20
    private var cardMaxWidth: CGFloat { horizontalSizeClass == .regular ? 820 : 700 }
    private let cardMinHeight: CGFloat = 150
    private let trainButtonMinHeight: CGFloat = 56

    private enum StageState { case completed, current, locked }

    private func stageState(for index: Int) -> StageState {
        let activity = Self.activities[index].activity
        let playerId = playerStore.selectedPlayerId
        if !progressStore.isUnlocked(activity: activity, playerId: playerId) { return .locked }
        if progressStore.isReady(activity: activity, playerId: playerId) { return .completed }
        return .current
    }

    /// True when the player has completed at least one block in this activity (used for filled ● vs empty ○).
    private func hasCompletedBlock(activity: ActivityKind) -> Bool {
        progressStore.last(activity, playerId: playerStore.selectedPlayerId) != nil
    }

    /// Number of completed sessions (blocks) for this activity and player. Used to decide whether to show progress % or prompt.
    private func sessionCount(for activity: ActivityKind) -> Int {
        progressStore.sessions(for: activity, playerId: playerStore.selectedPlayerId).count
    }

    /// Training progress 0–100 based only on completed blocks (not performance). 2 blocks = 67%, 3+ = 100%. Only meaningful when sessionCount >= 2.
    private func trainingProgressPercent(for activity: ActivityKind) -> Int {
        let count = sessionCount(for: activity)
        guard count > 0 else { return 0 }
        return min(100, Int(Double(min(3, count)) / 3.0 * 100))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Perception Training Path")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                        Text("Activities build on each other. Complete each step to progress.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.leading, timelineIndicatorWidth + 20)

                    curriculumRow(index: 0, title: "Playing Away From Pressure", subtitle: Self.activities[0].subtitle, route: .awayFromPressureRoleSelection)
                    curriculumRow(index: 1, title: "Dribble or Pass", subtitle: Self.activities[1].subtitle, route: .dribbleOrPassRoleSelection)
                    curriculumRow(index: 2, title: "One-Touch Passing", subtitle: Self.activities[2].subtitle, route: .oneTouchPassingRoleSelection)
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
    }

    /// One row: timeline indicator (left) + activity card (right). Dot is vertically centered with the card.
    private func curriculumRow(index: Int, title: String, subtitle: String, route: AppRoute) -> some View {
        HStack(alignment: .center, spacing: 20) {
            timelineIndicator(index: index)
            activityCard(index: index, title: title, subtitle: subtitle, route: route)
        }
        .frame(maxWidth: cardMaxWidth, alignment: .leading)
    }

    private static let completedColor = Color.green
    private static let currentColor = Color.yellow
    private static let lockedColor = Color.gray.opacity(0.4)

    /// Fixed-width (48pt) timeline column. Flexible line above/below dot so dot sits at vertical center of card. Yellow bottom line animates downward when stage becomes completed.
    private func timelineIndicator(index: Int) -> some View {
        let lastIndex = Self.activities.count - 1
        let state = stageState(for: index)
        // Completed: connector above and below = yellow. Current: above = yellow, below = gray. Locked: both = gray.
        let topLineColor = index != 0 && (state == .completed || state == .current) ? Self.currentColor : Self.lockedColor
        let bottomLineIsYellow = index != lastIndex && state == .completed
        let bottomLineProgress: CGFloat = bottomLineIsYellow ? 1 : 0

        return VStack(spacing: 0) {
            if index != 0 {
                Rectangle()
                    .fill(topLineColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }

            stageCircle(index: index, state: state)

            if index != lastIndex {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Self.lockedColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                    Rectangle()
                        .fill(Self.currentColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: bottomLineProgress, anchor: .top)
                        .animation(.easeInOut(duration: 0.35), value: bottomLineProgress)
                }
            }
        }
        .frame(width: timelineIndicatorWidth)
        .frame(maxHeight: .infinity)
    }

    /// Progress indicator: filled ● when player has completed at least one block in this activity, empty ○ otherwise. Updates when a block is completed.
    private func stageCircle(index: Int, state: StageState) -> some View {
        let activity = Self.activities[index].activity
        let filled = hasCompletedBlock(activity: activity)
        let color: Color = state == .locked ? Self.lockedColor : (filled ? Self.completedColor : Self.currentColor)
        return Text(filled ? "●" : "○")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(color)
    }

    /// Card: dark rounded rect, stage label, title, subtitle, training progress (or prompt), large yellow Train button. Padding 22, corner radius 18.
    private func activityCard(index: Int, title: String, subtitle: String, route: AppRoute) -> some View {
        let activity = Self.activities[index].activity
        let count = sessionCount(for: activity)
        let showProgress = count >= 2
        let progressPercent = trainingProgressPercent(for: activity)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Stage \(index + 1)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 2)
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))

                Text("Training Progress")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Based on completed blocks, not performance.")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.85))
                    .padding(.top, 1)
                    .padding(.bottom, 6)

                if showProgress {
                    HStack(alignment: .center, spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.yellow)
                                    .frame(width: max(0, geo.size.width * CGFloat(progressPercent) / 100), height: 8)
                            }
                        }
                        .frame(height: 8)
                        Text("\(progressPercent)%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                } else {
                    Text("Complete 2 sessions to track performance")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 2)
                }
            }
            NavigationLink(value: route) {
                Text("Train")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: trainButtonMinHeight)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .cornerRadius(18)
    }
}
