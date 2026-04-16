//
//  PlayerImprovementProgressView.swift
//  FootballScanningAI
//
//  PBA V2 — Progress screen: decision speed over time, key metrics (average speed, total decisions, sessions this week, personal best).
//

import SwiftUI

struct PlayerImprovementProgressView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var navigateToDashboard = false

    private var activeProfile: UserProfile? { profileManager.currentProfile }
    private var playerId: UUID? { activeProfile?.id }
    private var playerIdentity: PlayerIdentity? {
        guard let activeProfile else { return nil }
        return PlayerIdentityEngine.confirmedIdentity(
            from: activeProfile.sessionResults,
            previousIdentity: PlayerIdentityEngine.loadLastIdentity(playerId: activeProfile.id)
        )
            ?? PlayerIdentityEngine.loadLastIdentity(playerId: activeProfile.id)
    }
    private var trendingIdentity: PlayerIdentity? {
        guard let activeProfile else { return nil }
        return PlayerIdentityEngine.trendingTowardIdentity(from: activeProfile.sessionResults, currentIdentity: playerIdentity)
    }

    /// Sessions sorted by date (oldest first) for charts and metrics.
    private var chartSessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
    }

    /// Average decision window (seconds before arrival) per session — for line chart.
    private var decisionSpeedPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let t = s.avgDecisionWindowSeconds else { return nil }
            return ChartDataPoint(sessionIndex: index + 1, value: t)
        }
    }

    /// Average decision window across all sessions that have the metric (seconds).
    private var averageDecisionWindowSeconds: Double? {
        let times = chartSessions.compactMap(\.avgDecisionWindowSeconds)
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    /// Total decisions (reps) completed across all sessions.
    private var totalDecisionsCompleted: Int {
        chartSessions.reduce(0) { $0 + $1.totalReps }
    }

    /// Sessions completed in the current calendar week.
    private var sessionsThisWeek: Int {
        profileManager.sessionsCompletedThisWeek()
    }

    /// Personal best (largest positive) average decision window in seconds.
    private var personalBestDecisionWindowSeconds: Double? {
        chartSessions.compactMap(\.avgDecisionWindowSeconds).max()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background only ignores safe area — scroll content stays below nav bar.
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
                VStack(alignment: .leading, spacing: 24) {
                    scrollHeader
                    metricsGrid
                    decisionSpeedChartSection
                    viewFullDashboardLink
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .toolbar {
            // Title + identity live in the bar center so they never sit under Back / Home.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Progress")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                    if let playerIdentity {
                        Text(playerIdentity.emojiTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.yellow)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
                .accessibilityLabel("Home")
            }
        }
        .navigationDestination(isPresented: $navigateToDashboard) {
            PlayerProgressView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    /// Body copy only — title and identity line are in the navigation bar (`.principal`) so toolbar never covers them.
    private var scrollHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let playerIdentity {
                Text(playerIdentity.shortDescription)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if let trendingIdentity {
                    Text("Emerging strength: \(trendingIdentity.title)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.62))
                }
            }
            Text("See how your decision window improves over time.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your metrics")
                .font(.headline)
                .foregroundColor(.white)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Average Decision Window", value: averageDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")
                metricCard(title: "Personal Best", value: personalBestDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")
                metricCard(title: "Total Decisions Completed", value: "\(totalDecisionsCompleted)")
                metricCard(title: "Sessions This Week", value: "\(sessionsThisWeek)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    private var decisionSpeedChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Decision window over time")
                .font(.headline)
                .foregroundColor(.white)
            if decisionSpeedPoints.count < 2 {
                Text("Complete at least 2 sessions with timing data to see your trend.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressLineChartView(
                    title: "Decision Window",
                    points: decisionSpeedPoints,
                    valueLabel: "s",
                    yAxisRange: nil,
                    emptyStateMessage: "Complete at least 2 sessions to see your trend."
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var viewFullDashboardLink: some View {
        Button {
            navigateToDashboard = true
        } label: {
            HStack(spacing: 8) {
                Text("View full dashboard")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
