//
//  PlayerDashboardView.swift
//  FootballScanningAI
//
//  PBA V2 — Player development summary: snapshot, progress graphs, training recommendation.
//

import SwiftUI

/// Trend status for dashboard: derived from recent vs older session metrics.
enum DevelopmentStatus: String {
    case improving = "Improving"
    case stable = "Stable"
    case declining = "Declining"
}

struct PlayerDashboardView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var navigateToFullProgress = false
    @State private var navigateToTrain = false
    @State private var navigateToReportCard = false
    @State private var navigateToDevelopmentSnapshot = false
    @State private var metricInfoToShow: (title: String, message: String)?

    private var activeProfile: UserProfile? { profileManager.currentProfile }
    private var playerId: UUID? { activeProfile?.id }
    private var last5: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: playerId) }
    private var recentSessions: [SessionResult] { profileManager.recentTrainSessions(limit: 5) }
    private var speedCounts: (fast: Int, medium: Int, slow: Int) { UserProfileManager.speedCounts(from: recentSessions) }
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    private var lastAFPSessionResult: SessionResult? {
        profileManager.recentTrainSessions(limit: 20).first { $0.activityType == .awayFromPressure }
    }
    private var trainingRecommendation: TrainingRecommendationResult {
        TrainingRecommendation.recommend(progressStore: progressStore, playerId: playerId, last5: last5, hasCompletedInitialTest: hasCompletedInitialTest, lastAFPSessionResult: lastAFPSessionResult, decisionConsistency: decisionConsistencyCurrent)
    }

    private var chartSessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
    }

    // Snapshot metrics (current)
    private var scanEfficiencyCurrent: Int? {
        guard let s = chartSessions.last else { return nil }
        return Int(round(ScanEfficiency.score(from: s)))
    }

    /// Decision window in seconds for headline display (latest session, else best historical window).
    private var decisionWindowSeconds: Double? {
        chartSessions.last(where: { $0.avgDecisionWindowSeconds != nil })?.avgDecisionWindowSeconds
            ?? chartSessions.compactMap(\.avgDecisionWindowSeconds).max()
    }

    /// Band remains score-based so scoring logic is unchanged.
    private var decisionSpeedBandForHeadline: DecisionSpeedBand? {
        if let last = chartSessions.last(where: { $0.avgDecisionWindowSeconds != nil }) {
            return DecisionSpeedBand.band(forSession: last)
        }
        return nil
    }

    private var decisionSpeedLabel: String {
        let (f, m, s) = speedCounts
        let total = f + m + s
        guard total > 0 else { return "—" }
        if f >= m && f >= s { return "Fast" }
        if s >= f && s >= m { return "Slow" }
        return "Medium"
    }

    private var firstTouchCommitmentCurrent: Int? {
        guard let s = chartSessions.last, let match = s.firstTouchMatchCount, s.totalReps > 0 else { return nil }
        return Int(round(Double(match) / Double(s.totalReps) * 100.0))
    }

    private var forwardIntentCurrent: Int? {
        guard let s = chartSessions.last, let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
        return Int(round(Double(choice) / Double(opp) * 100.0))
    }

    /// Decision Before Contact: % of reps where decisionTime < threshold and early action matched correct direction (from most recent session with data).
    private var decisionBeforeContactCurrent: Int? {
        guard let s = chartSessions.last, let count = s.preReceiveDecisionCount, s.totalReps > 0 else { return nil }
        return Int(round(Double(count) / Double(s.totalReps) * 100.0))
    }

    /// Improving / Stable / Declining from Scan Efficiency trend (recent vs older sessions).
    private var developmentStatus: DevelopmentStatus {
        let sessions = chartSessions
        guard sessions.count >= 2 else { return .stable }
        let scores = sessions.map { ScanEfficiency.score(from: $0) }
        let half = scores.count / 2
        let recent = Array(scores.suffix(half))
        let older = Array(scores.prefix(scores.count - half))
        guard !recent.isEmpty, !older.isEmpty else { return .stable }
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        let diff = recentAvg - olderAvg
        if diff >= 3 { return .improving }
        if diff <= -3 { return .declining }
        return .stable
    }

    // Chart data
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

    private var decisionSpeedPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let t = s.avgDecisionWindowSeconds else { return nil }
            return ChartDataPoint(sessionIndex: index + 1, value: t)
        }
    }

    private var firstTouchCommitmentPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let match = s.firstTouchMatchCount, s.totalReps > 0 else { return nil }
            let pct = Double(match) / Double(s.totalReps) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }

    private var forwardIntentPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            let pct = Double(choice) / Double(opp) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }
    private var latestActivity: ActivityKind? { chartSessions.last?.activityType }
    private var primaryTrendPoints: [ChartDataPoint] {
        switch latestActivity {
        case .awayFromPressure, .dribbleOrPass:
            return decisionScorePoints
        case .oneTouchPassing:
            return decisionSpeedPoints
        case .twoMinuteTest:
            return decisionScorePoints
        case .none:
            return []
        }
    }
    private var primaryTrendTitle: String {
        switch latestActivity {
        case .awayFromPressure: return "Correct Escape Trend"
        case .dribbleOrPass: return "Correct Decision Trend"
        case .oneTouchPassing: return "Decision Window Trend"
        case .twoMinuteTest: return "2-Minute Balanced Trend"
        case .none: return "Primary Trend"
        }
    }
    private var primaryTrendValueLabel: String {
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
        case .awayFromPressure, .dribbleOrPass, .twoMinuteTest: return "Decision Window (Secondary)"
        case .oneTouchPassing: return "Correct Decisions (Secondary)"
        case .none: return "Secondary Trend"
        }
    }
    private var secondaryTrendPoints: [ChartDataPoint] {
        switch latestActivity {
        case .oneTouchPassing:
            return decisionScorePoints
        default:
            return decisionSpeedPoints
        }
    }
    private var secondaryTrendValueLabel: String {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                playerSnapshotCard
                progressGraphsSection
                trainingRecommendationCard
                actionsSection
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
        .navigationDestination(isPresented: $navigateToFullProgress) {
            PlayerProgressView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToTrain) {
            trainDestination
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
            Text("Player Dashboard")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private var playerSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Player Snapshot")
                .font(.headline)
                .foregroundColor(.white)
            if chartSessions.isEmpty {
                Text("Complete training sessions to see your snapshot.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                decisionSpeedHeadline
                snapshotRow("Scan Efficiency", value: scanEfficiencyCurrent.map { "\($0)" } ?? "—", suffix: nil)
                snapshotRow("Forward Thinking", value: forwardIntentCurrent.map { "\($0)%" } ?? "—", suffix: nil)
                snapshotRowWithInfo("Status", value: developmentStatus.rawValue, valueColor: statusColor(developmentStatus))
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

    private var decisionSpeedHeadline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Decision Window")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            if let sec = decisionWindowSeconds {
                Text(DecisionTimingModel.summaryText(windowSeconds: sec))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let band = decisionSpeedBandForHeadline {
                    Text(band.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(band.color)
                }
            } else {
                Text(decisionSpeedLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            if let consistency = decisionConsistencyCurrent {
                Text("Consistency")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.75))
                Text(consistency.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .padding(.vertical, 4)
    }

    /// Decision Consistency: within-session stability of decision speed (from latest session with data).
    private var decisionConsistencyCurrent: DecisionConsistencyLabel? {
        DecisionConsistencyLabel.from(session: chartSessions.last(where: { $0.avgDecisionTime != nil || $0.decisionTimeStdDev != nil }))
    }

    private func snapshotRow(_ label: String, value: String, suffix: String?) -> some View {
        snapshotRowWithInfo(label, value: value, valueColor: .white, suffix: suffix)
    }

    private func snapshotRowWithInfo(_ label: String, value: String, valueColor: Color = .white, suffix: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            if let msg = MetricExplanations.message(for: label) {
                Button {
                    metricInfoToShow = (title: label, message: msg)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(valueColor)
            if let s = suffix {
                Text(s)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func statusColor(_ status: DevelopmentStatus) -> Color {
        switch status {
        case .improving: return .green
        case .stable: return .white.opacity(0.9)
        case .declining: return .orange
        }
    }

    private var progressGraphsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress Over Time")
                .font(.headline)
                .foregroundColor(.white)
            if chartSessions.count < 2 {
                Text("Complete at least 2 training sessions to see progress graphs.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 12)
            } else {
                ProgressLineChartView(title: primaryTrendTitle, points: primaryTrendPoints, valueLabel: primaryTrendValueLabel, yAxisRange: primaryTrendAxis)
                ProgressLineChartView(title: secondaryTrendTitle, points: secondaryTrendPoints, valueLabel: secondaryTrendValueLabel, yAxisRange: secondaryTrendAxis, emptyStateMessage: "Complete at least 2 sessions to see your trend.")
                ProgressLineChartView(title: "Forward Thinking", points: forwardIntentPoints, valueLabel: "%", yAxisRange: (0, 100), emptyStateMessage: "Complete at least 2 Dribble or Pass or One-Touch Passing sessions (with forward opportunities) to see your trend.")
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

    private var trainingRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Training Recommendation")
                .font(.headline)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Train:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(RecommendationEngine.activityTitle(trainingRecommendation.activity))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.yellow)
                }
                if !trainingRecommendation.coachTip.isEmpty {
                    Text("Reason:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Text(trainingRecommendation.coachTip)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Focus:")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text(trainingRecommendation.focusLine)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var actionsSection: some View {
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
                navigateToFullProgress = true
            } label: {
                Text("See Full Progress")
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
        }
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
}

#Preview {
    NavigationStack {
        PlayerDashboardView(profileManager: UserProfileManager(), settingsViewModel: SettingsViewModel())
            .environmentObject(ProgressStore())
            .environmentObject(PlayerStore())
            .environmentObject(PopToRootTrigger())
            .environmentObject(AppRouter())
    }
}
