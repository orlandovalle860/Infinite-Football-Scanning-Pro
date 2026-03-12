//
//  PlayerProgressView.swift
//  FootballScanningAI
//
//  PBA V2 — Parent/trainer-friendly report card: identity, speed, bests, streak, insight, recommended next.
//

import SwiftUI

/// Maps dashboard status to report-card "Player Type" label.
private func playerTypeLabel(status: PlayerStatus) -> String {
    switch status {
    case .beginner: return "Reactor"
    case .developing: return "Scanner"
    case .playmaker: return "Playmaker"
    case .elite: return "Game Reader"
    }
}

struct PlayerProgressView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var navigateToTrain = false
    @State private var navigateToPlayerReport = false
    @State private var navigateToReportCard = false
    @State private var navigateToDevelopmentSnapshot = false
    @State private var metricInfoToShow: (title: String, message: String)?

    private var activeProfile: UserProfile? { profileManager.currentProfile }
    private var playerId: UUID? { activeProfile?.id }
    private var last5: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: playerId) }
    private var decisionScore: Int { DashboardDecisionScore.score(from: last5) }
    private var consistencyLabel: ConsistencyLabel { DashboardConsistency.label(from: last5) }
    private var status: PlayerStatus { DashboardDecisionScore.status(score: decisionScore, consistencyLabel: consistencyLabel) }
    private var currentPlayerTypeLabel: String { playerTypeLabel(status: status) }
    private var recentSessions: [SessionResult] { profileManager.recentTrainSessions(limit: 5) }
    private var speedCounts: (fast: Int, medium: Int, slow: Int) { UserProfileManager.speedCounts(from: recentSessions) }
    private var streakDays: Int { profileManager.trainingStreakDays() }
    private var coachInsightText: String { profileManager.coachInsightForProgress(sessions: recentSessions) }
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    private var lastAFPSessionResult: SessionResult? {
        profileManager.recentTrainSessions(limit: 20).first { $0.activityType == .awayFromPressure }
    }
    private var decisionConsistencyForRecommendation: DecisionConsistencyLabel? {
        DecisionConsistencyLabel.from(session: profileManager.recentTrainSessions(limit: 1).first)
    }

    private var trainingRecommendation: TrainingRecommendationResult {
        TrainingRecommendation.recommend(progressStore: progressStore, playerId: playerId, last5: last5, hasCompletedInitialTest: hasCompletedInitialTest, lastAFPSessionResult: lastAFPSessionResult, decisionConsistency: decisionConsistencyForRecommendation)
    }

    /// Sessions sorted by date (oldest first) for improvement charts.
    private var chartSessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
    }

    /// Decision score per session: 0–100 (from correct % or normalized decisionTotalScore for DOP).
    private var decisionScorePoints: [ChartDataPoint] {
        chartSessions.enumerated().map { index, s in
            let value: Double
            if let score = s.decisionTotalScore, s.totalReps > 0 {
                value = (score / 60.0) * 100.0
            } else if s.totalReps > 0 {
                value = Double(s.correctCount) / Double(s.totalReps) * 100.0
            } else {
                value = 0
            }
            return ChartDataPoint(sessionIndex: index + 1, value: value)
        }
    }

    /// Average decision time (seconds) per session — only sessions that have the metric.
    private var decisionSpeedPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let t = s.avgDecisionTime else { return nil }
            return ChartDataPoint(sessionIndex: index + 1, value: t)
        }
    }

    /// First touch accuracy % per session — only sessions that track first touch.
    private var firstTouchAccuracyPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let match = s.firstTouchMatchCount, s.totalReps > 0 else { return nil }
            let pct = Double(match) / Double(s.totalReps) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }

    /// Correct decision percentage per session.
    private var correctPercentPoints: [ChartDataPoint] {
        chartSessions.enumerated().map { index, s in
            let value = s.totalReps > 0 ? Double(s.correctCount) / Double(s.totalReps) * 100.0 : 0
            return ChartDataPoint(sessionIndex: index + 1, value: value)
        }
    }

    // MARK: - Derived analytics (Early Decision Rate, First Touch Commitment, Forward Intent)

    /// Early Decision Rate: % of reps where decisionTime was Fast. Chart points per session.
    private var earlyDecisionRatePoints: [ChartDataPoint] {
        chartSessions.enumerated().map { index, s in
            let value = s.totalReps > 0 ? Double(s.speedCounts.fast) / Double(s.totalReps) * 100.0 : 0
            return ChartDataPoint(sessionIndex: index + 1, value: value)
        }
    }

    /// First Touch Commitment: % where first-touch direction matched exit. Same data as firstTouchAccuracy; label differs.
    private var firstTouchCommitmentPoints: [ChartDataPoint] { firstTouchAccuracyPoints }

    /// Forward Intent: % of forward opportunities where player chose forward. Only sessions with data.
    private var forwardIntentPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            let pct = Double(choice) / Double(opp) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }

    /// Current Early Decision Rate % from most recent session (or nil).
    private var earlyDecisionRateCurrent: Int? {
        guard let s = chartSessions.last, s.totalReps > 0 else { return nil }
        return Int(round(Double(s.speedCounts.fast) / Double(s.totalReps) * 100.0))
    }

    /// Current First Touch Commitment % from most recent session that has the metric.
    private var firstTouchCommitmentCurrent: Int? {
        guard let s = chartSessions.last, let match = s.firstTouchMatchCount, s.totalReps > 0 else { return nil }
        return Int(round(Double(match) / Double(s.totalReps) * 100.0))
    }

    /// Current Forward Intent % from most recent session that has the metric.
    private var forwardIntentCurrent: Int? {
        guard let s = chartSessions.last, let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
        return Int(round(Double(choice) / Double(opp) * 100.0))
    }

    // MARK: - Scan Efficiency (accuracy + first-touch + speed)

    /// Scan Efficiency per session: 0–100 combined score. Tracked over time.
    private var scanEfficiencyPoints: [ChartDataPoint] {
        chartSessions.enumerated().map { index, s in
            let value = ScanEfficiency.score(from: s)
            return ChartDataPoint(sessionIndex: index + 1, value: value)
        }
    }

    /// Current Scan Efficiency from most recent session.
    private var scanEfficiencyCurrent: Int? {
        guard let s = chartSessions.last else { return nil }
        return Int(round(ScanEfficiency.score(from: s)))
    }

    // MARK: - Pre-Receive Decision Rate (decisionTime < threshold AND firstTouch == correct)

    /// Pre-Receive Decision Rate % per session — only sessions that have the metric (AFP, DOP).
    private var preReceiveDecisionRatePoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let count = s.preReceiveDecisionCount, s.totalReps > 0 else { return nil }
            let pct = Double(count) / Double(s.totalReps) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }

    /// Current Pre-Receive Decision Rate % from most recent session that has the metric.
    private var preReceiveDecisionRateCurrent: Int? {
        guard let s = chartSessions.last, let count = s.preReceiveDecisionCount, s.totalReps > 0 else { return nil }
        return Int(round(Double(count) / Double(s.totalReps) * 100.0))
    }

    // MARK: - Pressure Escape Rate (AFP: % of reps where player successfully escaped)

    /// Pressure Escape Rate % per AFP session (successful escapes / total reps). Only Away From Pressure sessions.
    private var pressureEscapeRatePoints: [ChartDataPoint] {
        let afpSessions = chartSessions.filter { $0.activityType == .awayFromPressure }
        return afpSessions.enumerated().map { index, s in
            let value = s.totalReps > 0 ? Double(s.correctCount) / Double(s.totalReps) * 100.0 : 0
            return ChartDataPoint(sessionIndex: index + 1, value: value)
        }
    }

    /// Current Pressure Escape Rate % from most recent AFP session.
    private var pressureEscapeRateCurrent: Int? {
        guard let s = chartSessions.last(where: { $0.activityType == .awayFromPressure }), s.totalReps > 0 else { return nil }
        return Int(round(Double(s.correctCount) / Double(s.totalReps) * 100.0))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                playerIdentityCard
                decisionSpeedCard
                personalBestsCard
                trainingStreakCard
                coachInsightCard
                improvementOverTimeSection
                derivedAnalyticsSection
                recommendedNextCard
                buttonsSection
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
        .navigationDestination(isPresented: $navigateToTrain) {
            trainDestination
        }
        .alert(metricInfoToShow?.title ?? "", isPresented: Binding(
            get: { metricInfoToShow != nil },
            set: { if !$0 { metricInfoToShow = nil } }
        )) {
            Button("OK", role: .cancel) { metricInfoToShow = nil }
        } message: {
            if let msg = metricInfoToShow?.message {
                Text(msg)
            }
        }
        .navigationDestination(isPresented: $navigateToPlayerReport) {
            PlayerReportView(content: PlayerReportGenerator.report(
                progressStore: progressStore,
                playerId: playerId,
                last5: last5,
                lastAFPSessionResult: lastAFPSessionResult,
                decisionConsistency: decisionConsistencyForRecommendation
            ))
        }
        .navigationDestination(isPresented: $navigateToReportCard) {
            PlayerReportCardView(data: ReportCardGenerator.reportCard(
                chartSessions: chartSessions,
                last5: last5,
                trainingRecommendation: trainingRecommendation
            ))
        }
        .navigationDestination(isPresented: $navigateToDevelopmentSnapshot) {
            PlayerDevelopmentSnapshotView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activeProfile?.name ?? "Player")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Player Progress")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private var playerIdentityCard: some View {
        sectionCard(title: "Player Type") {
            VStack(alignment: .leading, spacing: 8) {
                Text(currentPlayerTypeLabel)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                Text("Perception Before Action")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var decisionSpeedCard: some View {
        sectionCard(title: "Decision Speed") {
            if recentSessions.isEmpty {
                Text("Run your first block to see your speed.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 16) {
                    speedPill("Fast", value: speedCounts.fast)
                    speedPill("Medium", value: speedCounts.medium)
                    speedPill("Slow", value: speedCounts.slow)
                }
            }
        }
    }

    private func speedPill(_ label: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    private var personalBestsCard: some View {
        sectionCard(title: "Personal Bests") {
            let bests = activeProfile?.personalBests ?? [:]
            VStack(alignment: .leading, spacing: 12) {
                bestRow("Playing Away From Pressure", best: bests[.awayFromPressure])
                bestRow("Dribble or Pass", best: bests[.dribbleOrPass])
                bestRow("One-Touch Passing", best: bests[.oneTouchPassing])
            }
        }
    }

    private func bestRow(_ title: String, best: ActivityBest?) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(best != nil ? "\(best!.bestCorrect) / \(best!.bestTotal)" : "—")
                .font(.subheadline.weight(.medium))
                .foregroundColor(best != nil ? .white : .white.opacity(0.5))
        }
    }

    private var trainingStreakCard: some View {
        sectionCard(title: "Training Streak") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(streakDays) days")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                if streakDays == 0 {
                    Text("Train today to start a streak.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var coachInsightCard: some View {
        sectionCard(title: "Coach Insight") {
            Text(coachInsightText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var improvementOverTimeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Improvement Over Time")
                .font(.headline)
                .foregroundColor(.white)
            if chartSessions.isEmpty {
                Text("Complete training sessions to see your progress here.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 12)
            } else {
                ProgressLineChartView(title: "Decision Score", points: decisionScorePoints, valueLabel: "%", yAxisRange: (0, 100))
                ProgressLineChartView(title: "Avg Decision Time", points: decisionSpeedPoints, valueLabel: "s", yAxisRange: nil, emptyStateMessage: "Complete at least 2 Dribble or Pass sessions to see your trend.")
                ProgressLineChartView(title: "First Touch Accuracy", points: firstTouchAccuracyPoints, valueLabel: "%", yAxisRange: (0, 100), emptyStateMessage: "Complete at least 2 Playing Away From Pressure sessions to see your trend.")
                ProgressLineChartView(title: "Correct Decisions", points: correctPercentPoints, valueLabel: "%", yAxisRange: (0, 100))
                ProgressLineChartView(title: "Scan Efficiency", points: scanEfficiencyPoints, valueLabel: "", yAxisRange: (0, 100))
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

    private var derivedAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Derived Analytics")
                .font(.headline)
                .foregroundColor(.white)
            analyticsMetricCard(
                title: "Scan Efficiency",
                definition: "Combines decision accuracy (50%), first-touch accuracy (30%), and decision speed (20%) into one score. Measures how efficiently you convert perception into action.",
                currentPercent: scanEfficiencyCurrent,
                points: scanEfficiencyPoints,
                emptyStateMessage: nil
            )
            analyticsMetricCard(
                title: "Early Decision Rate",
                definition: "Percentage of reps where decision time was Fast. Measures how often you decide before receiving the ball.",
                currentPercent: earlyDecisionRateCurrent,
                points: earlyDecisionRatePoints,
                emptyStateMessage: nil
            )
            analyticsMetricCard(
                title: "First Touch Commitment",
                definition: "Percentage of reps where your first-touch direction matched the exit direction. Measures whether you commit to your decision immediately.",
                currentPercent: firstTouchCommitmentCurrent,
                points: firstTouchCommitmentPoints,
                emptyStateMessage: "Complete at least 2 Playing Away From Pressure sessions to see your trend."
            )
            analyticsMetricCard(
                title: "Forward Intent",
                definition: "Percentage of opportunities where a forward option was available and you chose it. Measures tendency to play forward when possible.",
                currentPercent: forwardIntentCurrent,
                points: forwardIntentPoints,
                emptyStateMessage: "Complete at least 2 Dribble or Pass sessions to see your trend."
            )
            analyticsMetricCard(
                title: "Decision Before Contact",
                definition: "Percentage of reps where you had already decided the correct action before receiving the ball (decision time under \(String(format: "%.1f", TimingThresholds.earlyDecisionThresholdForPreReceive))s and first touch matched the correct direction).",
                currentPercent: preReceiveDecisionRateCurrent,
                points: preReceiveDecisionRatePoints,
                emptyStateMessage: nil
            )
            analyticsMetricCard(
                title: "Pressure Escape Rate",
                definition: "Percentage of reps where you successfully escaped pressure (correct direction chosen and exit through that gate). Playing Away From Pressure only.",
                currentPercent: pressureEscapeRateCurrent,
                points: pressureEscapeRatePoints,
                emptyStateMessage: "Complete at least 2 Playing Away From Pressure sessions to see your trend."
            )
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

    private func analyticsMetricCard(title: String, definition: String, currentPercent: Int?, points: [ChartDataPoint], emptyStateMessage: String? = nil) -> some View {
        let trendMessage = emptyStateMessage ?? "Complete at least 2 training sessions to see your trend."
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if MetricExplanations.message(for: title) != nil {
                    Button {
                        metricInfoToShow = (title: title, message: MetricExplanations.message(for: title) ?? "")
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            Text(definition)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currentPercent != nil ? "\(currentPercent!)%" : "—")
                    .font(.title2.weight(.bold))
                    .foregroundColor(currentPercent != nil ? .yellow : .white.opacity(0.5))
                Text("current")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            if points.count >= 2 {
                ProgressLineChartView(title: "", points: points, valueLabel: "%", yAxisRange: (0, 100), emptyStateMessage: emptyStateMessage)
                    .padding(.horizontal, -16)
                    .padding(.vertical, -8)
            } else if !points.isEmpty {
                Text(trendMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .cornerRadius(14)
    }

    private var recommendedNextCard: some View {
        sectionCard(title: "Recommended Next") {
            VStack(alignment: .leading, spacing: 8) {
                Text(RecommendationEngine.activityTitle(trainingRecommendation.activity))
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Focus: \(trainingRecommendation.focusLine)")
                    .font(.subheadline)
                    .foregroundColor(.yellow.opacity(0.95))
                Text("Coach Tip: \(trainingRecommendation.coachTip)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttonsSection: some View {
        VStack(spacing: 12) {
            Button {
                navigateToTrain = true
            } label: {
                Text("Train Now")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToPlayerReport = true
            } label: {
                Text("Player Report")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToReportCard = true
            } label: {
                Text("Report Card")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToDevelopmentSnapshot = true
            } label: {
                Text("Development Snapshot")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button { dismiss() } label: {
                Text("Back to Home")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var trainDestination: some View {
        switch trainingRecommendation.activity {
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

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            content()
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
}

#Preview {
    NavigationStack {
        PlayerProgressView(profileManager: UserProfileManager(), settingsViewModel: SettingsViewModel())
            .environmentObject(ProgressStore())
            .environmentObject(PlayerStore())
            .environmentObject(PopToRootTrigger())
            .environmentObject(AppRouter())
    }
}
