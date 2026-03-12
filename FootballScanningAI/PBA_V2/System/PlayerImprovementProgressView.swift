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

    /// Sessions sorted by date (oldest first) for charts and metrics.
    private var chartSessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
    }

    /// Average decision time (seconds) per session — for line chart.
    private var decisionSpeedPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let t = s.avgDecisionTime else { return nil }
            return ChartDataPoint(sessionIndex: index + 1, value: t)
        }
    }

    /// Average decision speed across all sessions that have the metric (seconds).
    private var averageDecisionSpeedSeconds: Double? {
        let times = chartSessions.compactMap(\.avgDecisionTime)
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

    /// Personal best (fastest) average decision time in seconds.
    private var personalBestDecisionSpeedSeconds: Double? {
        profileManager.fastestDecisionSpeedSeconds()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricsGrid
                decisionSpeedChartSection
                viewFullDashboardLink
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
        )
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .navigationDestination(isPresented: $navigateToDashboard) {
            PlayerDashboardView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Progress")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("See how your decision speed improves over time.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your metrics")
                .font(.headline)
                .foregroundColor(.white)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Average Decision Speed", value: averageDecisionSpeedSeconds.map { String(format: "%.2fs", $0) } ?? "—")
                metricCard(title: "Personal Best", value: personalBestDecisionSpeedSeconds.map { String(format: "%.2fs", $0) } ?? "—")
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
            Text("Decision speed over time")
                .font(.headline)
                .foregroundColor(.white)
            if decisionSpeedPoints.count < 2 {
                Text("Complete at least 2 sessions with decision speed data to see your trend.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressLineChartView(
                    title: "Average Decision Speed",
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
