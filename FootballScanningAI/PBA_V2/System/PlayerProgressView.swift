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
    @State private var showWeeklyReport = false
    @State private var metricInfoToShow: (title: String, message: String)?
    @State private var showLevelUp = false
    @State private var levelUpReachedName: String = ""

    private var activeProfile: UserProfile? { profileManager.currentProfile }
    private var playerId: UUID? { activeProfile?.id }
    private var last5: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: playerId) }
    private var decisionScore: Int { DashboardDecisionScore.score(from: last5) }
    private var consistencyLabel: ConsistencyLabel { DashboardConsistency.label(from: last5) }
    private var status: PlayerStatus { DashboardDecisionScore.status(score: decisionScore, consistencyLabel: consistencyLabel) }
    private var currentPlayerTypeLabel: String { playerTypeLabel(status: status) }
    private var recentSessions: [SessionResult] { profileManager.recentTrainSessions(limit: 5) }
    private var speedCounts: (fast: Int, medium: Int, slow: Int) { UserProfileManager.speedCounts(from: recentSessions) }
    private var sessionStreak: Int { activeProfile?.sessionStreakCount ?? 0 }
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

    private var adaptiveTrainingState: AdaptiveTrainingState? {
        activeProfile?.adaptiveTrainingState
    }

    private var activityAdaptiveSnapshot: ActivityAdaptiveSnapshot {
        makeActivityAdaptiveSnapshot(from: profileManager.recentTrainSessions(limit: 3))
    }

    /// Sessions sorted by date (oldest first) for improvement charts.
    private var chartSessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
    }

    private var allSessionPerformances: [SessionPerformance] {
        activeProfile?.sessionResults.map(\.sessionPerformance) ?? []
    }

    private var progressionForWeekly: PlayerProgression {
        generateProgression(sessions: allSessionPerformances)
    }

    private var weeklyReportModel: WeeklyReport {
        return generateWeeklyReport(
            sessions: activeProfile?.sessionResults ?? [],
            playerName: activeProfile?.name ?? "Player",
            adaptiveState: activeProfile?.adaptiveTrainingState,
            unlockedBadges: activeProfile?.unlockedBadges ?? [],
            latestUnlockedBadge: activeProfile?.lastUnlockedBadge
        )
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

    /// Average decision window (seconds before arrival) per session — only sessions that have timing data.
    private var decisionSpeedPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let t = s.avgDecisionWindowSeconds else { return nil }
            return ChartDataPoint(sessionIndex: index + 1, value: t)
        }
    }

    /// Decision–action alignment % per session (legacy `firstTouchMatchCount` in model).
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
    private var latestActivity: ActivityKind? { chartSessions.last?.activityType }
    private var primaryTrendTitle: String {
        switch latestActivity {
        case .awayFromPressure: return "Correct First-Decision Trend"
        case .dribbleOrPass: return "Correct Decision Trend"
        case .oneTouchPassing: return "Decision Window Trend"
        case .twoMinuteTest: return "2-Minute Balanced Trend"
        case .none: return "Primary Trend"
        }
    }
    private var primaryTrendPoints: [ChartDataPoint] {
        switch latestActivity {
        case .oneTouchPassing:
            return decisionSpeedPoints
        default:
            return correctPercentPoints
        }
    }
    private var primaryTrendLabel: String {
        switch latestActivity {
        case .oneTouchPassing: return "s"
        default: return "%"
        }
    }
    private var primaryTrendAxis: (Double, Double)? {
        switch latestActivity {
        case .oneTouchPassing: return nil
        default: return (0, 100)
        }
    }
    private var secondaryTrendTitle: String {
        switch latestActivity {
        case .oneTouchPassing: return "Correct Decisions (Secondary)"
        default: return "Decision Window (Secondary)"
        }
    }
    private var secondaryTrendPoints: [ChartDataPoint] {
        switch latestActivity {
        case .oneTouchPassing:
            return correctPercentPoints
        default:
            return decisionSpeedPoints
        }
    }
    private var secondaryTrendLabel: String {
        switch latestActivity {
        case .oneTouchPassing: return "%"
        default: return "s"
        }
    }
    private var secondaryTrendAxis: (Double, Double)? {
        switch latestActivity {
        case .oneTouchPassing: return (0, 100)
        default: return nil
        }
    }

    // MARK: - Derived analytics (trustworthy v1 metrics only: Accuracy, Decision Speed, Forward Thinking)

    /// Forward Thinking: % of forward opportunities where player chose forward. Only sessions with data.
    private var forwardIntentPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            let pct = Double(choice) / Double(opp) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }

    /// Accuracy % from most recent session.
    private var accuracyCurrent: Int? {
        guard let s = chartSessions.last, s.totalReps > 0 else { return nil }
        return Int(round(Double(s.correctCount) / Double(s.totalReps) * 100.0))
    }

    /// Current Forward Thinking % from most recent session that has the metric.
    private var forwardIntentCurrent: Int? {
        guard let s = chartSessions.last, let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
        return Int(round(Double(choice) / Double(opp) * 100.0))
    }

    private var trendSessions: [SessionResult] {
        Array(chartSessions.suffix(10))
    }

    private var scoreTrendValues: [Double] {
        trendSessions.map { s in
            if let score = s.decisionTotalScore, s.totalReps > 0 {
                return (score / 60.0) * 100.0
            }
            guard s.totalReps > 0 else { return 0 }
            return Double(s.correctCount) / Double(s.totalReps) * 100.0
        }
    }

    private var earlyDecisionPercentTrendValues: [Double] {
        trendSessions.map { s in
            let total = s.speedCounts.fast + s.speedCounts.medium + s.speedCounts.slow
            guard total > 0 else { return 0 }
            return (Double(s.speedCounts.fast) / Double(total)) * 100.0
        }
    }

    private var averageTimingTrendValues: [Double] {
        trendSessions.map { $0.avgDecisionWindowSeconds ?? 0 }
    }

    private var lateCountTrendValues: [Double] {
        trendSessions.map { Double($0.speedCounts.slow) }
    }

    private var progressTrendInsight: String {
        guard let earlyFirst = earlyDecisionPercentTrendValues.first,
              let earlyLast = earlyDecisionPercentTrendValues.last,
              let lateFirst = lateCountTrendValues.first,
              let lateLast = lateCountTrendValues.last else {
            return "Complete more sessions to unlock trend insights."
        }
        if (earlyLast - earlyFirst) >= 3 {
            return "You’re deciding earlier each session"
        }
        if (lateFirst - lateLast) >= 1 {
            return "Your consistency is improving"
        }
        return "You’re plateauing — push for earlier decisions"
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
                progressOverTimeSection
                derivedAnalyticsSection
                adaptiveRecommendationCard
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
            detectAdaptiveLevelUpIfNeeded()
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
        .alert("Level Up!", isPresented: $showLevelUp) {
            Button("Nice", role: .cancel) {}
        } message: {
            Text("You reached \(levelUpReachedName)\n\(activityAdaptiveSnapshot.plan.focusCue)")
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
        .sheet(isPresented: $showWeeklyReport) {
            WeeklyReportView(report: weeklyReportModel)
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
                Text("🔥 \(sessionStreak) Session Streak")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                if sessionStreak == 0 {
                    Text("Complete a session to start your streak.")
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
                ProgressLineChartView(title: primaryTrendTitle, points: primaryTrendPoints, valueLabel: primaryTrendLabel, yAxisRange: primaryTrendAxis)
                ProgressLineChartView(title: secondaryTrendTitle, points: secondaryTrendPoints, valueLabel: secondaryTrendLabel, yAxisRange: secondaryTrendAxis, emptyStateMessage: "Complete at least 2 sessions to see your trend.")
                ProgressLineChartView(title: "Decision Score", points: decisionScorePoints, valueLabel: "%", yAxisRange: (0, 100))
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

    private var progressOverTimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Progress Over Time")
                .font(.headline)
                .foregroundColor(.white)
            if trendSessions.count < 2 {
                Text("Complete at least 2 sessions to see trends.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                trendStrip(
                    title: "Score Trend (\(trendSessions.count) sessions)",
                    values: scoreTrendValues
                ) { "\(Int($0.rounded()))" }
                trendStrip(
                    title: "Early Decision % Trend",
                    values: earlyDecisionPercentTrendValues
                ) { "\(Int($0.rounded()))%" }
                trendStrip(
                    title: "Average Timing Trend",
                    values: averageTimingTrendValues
                ) { String(format: "%.2fs", $0) }
                trendStrip(
                    title: "Late Count Trend",
                    values: lateCountTrendValues
                ) { "\(Int($0.rounded()))" }

                Text(progressTrendInsight)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
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

    private func trendStrip(title: String, values: [Double], formatter: @escaping (Double) -> String) -> some View {
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let span = max(0.0001, maxValue - minValue)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    let normalized = (value - minValue) / span
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.cyan.opacity(0.9))
                            .frame(width: 12, height: 10 + (normalized * 22))
                        Text(formatter(value))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.72))
                    }
                    .frame(maxHeight: 42, alignment: .bottom)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    private var derivedAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Core Analytics")
                .font(.headline)
                .foregroundColor(.white)
            analyticsMetricCard(
                title: "Accuracy",
                definition: "Percentage of correct decisions.",
                currentPercent: accuracyCurrent,
                points: correctPercentPoints,
                emptyStateMessage: "Complete at least 2 sessions to see your trend."
            )
            analyticsMetricCard(
                title: "Forward Thinking",
                definition: "How often you choose the forward option when it is available.",
                currentPercent: forwardIntentCurrent,
                points: forwardIntentPoints,
                emptyStateMessage: "Complete at least 2 Dribble or Pass or One-Touch Passing sessions (with forward opportunities) to see your trend."
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

    private var adaptiveRecommendationCard: some View {
        sectionCard(title: "Adaptive Recommendation") {
            let snapshot = activityAdaptiveSnapshot
            VStack(alignment: .leading, spacing: 8) {
                Text("Level: \(snapshot.plan.level.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text("Badge: \(snapshot.plan.level.mappedBadgeName)")
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.95))
                Text("Focus: \(snapshot.plan.focusCue)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let next = snapshot.nextLevel {
                    let progressPct = Int((snapshot.progressToNextLevel * 100).rounded())
                    Text("Progress to \(next.rawValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                    ProgressView(value: snapshot.progressToNextLevel)
                        .tint(.yellow)
                    Text("\(progressPct)%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                    if snapshot.isNearNextLevel {
                        Text("You’re close to \(next.rawValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.yellow.opacity(0.95))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detectAdaptiveLevelUpIfNeeded() {
        guard let playerId = activeProfile?.id else { return }
        let currentLevel = activityAdaptiveSnapshot.plan.level
        let key = "adaptiveVisibleLevelV1.\(playerId.uuidString)"
        let previousRaw = UserDefaults.standard.string(forKey: key)
        if let previousRaw,
           let previousLevel = ActivityAdaptiveLevel(rawValue: previousRaw),
           currentLevel.rank > previousLevel.rank {
            levelUpReachedName = currentLevel.rawValue
            showLevelUp = true
        }
        UserDefaults.standard.set(currentLevel.rawValue, forKey: key)
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
                showWeeklyReport = true
            } label: {
                Text("Weekly report")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToReportCard = true
            } label: {
                Text("Player Development")
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
