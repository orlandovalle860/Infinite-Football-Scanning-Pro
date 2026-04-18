//
//  PlayerDashboardView.swift
//  FootballScanningAI
//
//  PBA V2 — Player development summary: snapshot, progress graphs, training recommendation.
//

import SwiftUI
import UIKit

/// Trend status for dashboard: derived from recent vs older session metrics.
enum DevelopmentStatus: String {
    case improving = "Improving"
    case stable = "Stable"
    case declining = "Declining"
}

private enum DashboardAudienceRole: String {
    case coach
    case parentPlayer = "parent_player"
}

private struct ParentRecommendedNextPlan {
    let weakness: String
    let message: String
    let activity: ActivityKind
    let activityName: String
    let focus: String
}

struct PlayerDashboardView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController
    @Environment(\.dismiss) private var dismiss

    @State private var navigateToFullProgress = false
    @State private var navigateToTrain = false
    @State private var navigateToReportCard = false
    @State private var navigateToDevelopmentSnapshot = false
    @State private var metricInfoToShow: (title: String, message: String)?
    @AppStorage("dashboardAudienceRoleV1") private var dashboardAudienceRoleRaw: String = ""

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

    private var dashboardRole: DashboardAudienceRole? {
        DashboardAudienceRole(rawValue: dashboardAudienceRoleRaw)
    }

    private var effectiveDashboardRole: DashboardAudienceRole {
        dashboardRole ?? .parentPlayer
    }

    private var parentRecommendedNext: ParentRecommendedNextPlan {
        let recent = profileManager.recentTrainSessions(limit: 3)
        guard !recent.isEmpty else {
            return ParentRecommendedNextPlan(
                weakness: "none",
                message: "Build your baseline to get personalized guidance.",
                activity: .twoMinuteTest,
                activityName: "2-Minute Test",
                focus: "Establish your baseline"
            )
        }

        let sessionsForDecision: [SessionResult]
        if recent.count >= 3 {
            sessionsForDecision = recent
        } else if let latest = recent.first {
            sessionsForDecision = [latest]
        } else {
            sessionsForDecision = []
        }

        let aggregates = parentRecommendationAggregates(from: sessionsForDecision)
        let latePercentage = aggregates.latePercentage
        let accuracy = aggregates.accuracy
        let score = aggregates.score
        _ = timingBand(for: latePercentage)
        _ = accuracyBand(for: accuracy)
        _ = scoreBand(for: score)

        if latePercentage > 0.40 {
            return ParentRecommendedNextPlan(
                weakness: "timing",
                message: "You’re deciding too late relative to the ball",
                activity: .oneTouchPassing,
                activityName: "One-Touch Passing",
                focus: "Decide earlier before the ball arrives"
            )
        }

        if accuracy < 0.70 {
            return ParentRecommendedNextPlan(
                weakness: "accuracy",
                message: "You’re choosing the wrong option too often",
                activity: .awayFromPressure,
                activityName: "Playing Away from Pressure",
                focus: "Choose the correct direction consistently"
            )
        }
        return ParentRecommendedNextPlan(
            weakness: "none",
            message: "You’re ahead of the play — keep pushing your speed",
            activity: .dribbleOrPass,
            activityName: "Dribble or Pass",
            focus: "Increase speed under pressure"
        )
    }

    private var parentAverageTimingLabel: String {
        let values = chartSessions.compactMap(\.avgDecisionWindowSeconds)
        guard !values.isEmpty else { return "—" }
        let avg = values.reduce(0, +) / Double(values.count)
        if avg >= 0 {
            return String(format: "Early by %.2fs", avg)
        }
        return String(format: "Late by %.2fs", abs(avg))
    }

    private var parentSimpleTrend: String {
        let scores = decisionScorePoints.map(\.value)
        guard scores.count >= 2 else { return "Build trend: complete more sessions." }
        let trend = calculateTrend(values: scores)
        switch trend {
        case .up: return "Progress trend: Improving"
        case .down: return "Progress trend: Declining"
        case .stable: return "Progress trend: Stable"
        }
    }

    private var parentLevelLabel: String {
        activeProfile?.adaptiveTrainingState.currentLevel.rawValue ?? "Reactive"
    }

    private var parentScoreLabel: String {
        guard let latest = decisionScorePoints.last?.value else { return "—" }
        return "\(Int(latest.rounded()))"
    }

    private var sessionStreakLabel: String {
        let streak = activeProfile?.sessionStreakCount ?? 0
        return "🔥 \(streak) Session Streak"
    }

    private var parentScoreBandLabel: String {
        guard let latest = decisionScorePoints.last?.value else { return "Getting Started" }
        let score = Int(latest.rounded())
        switch score {
        case 90...100: return "Elite Timing"
        case 75...89: return "Strong Timing"
        case 60...74: return "Developing Timing"
        default: return "Building Timing"
        }
    }

    private var parentLastThreeScoresText: String {
        let values = decisionScorePoints.map { Int($0.value.rounded()) }
        let last3 = Array(values.suffix(3))
        guard !last3.isEmpty else { return "—" }
        return last3.map(String.init).joined(separator: " → ")
    }

    private var parentImprovementLabel: String {
        let values = decisionScorePoints.map(\.value)
        guard values.count >= 2 else { return "Keep building with each session" }
        let trend = calculateTrend(values: values)
        switch trend {
        case .up: return "Improving each session"
        case .down: return "Keep pushing for earlier decisions"
        case .stable: return "Staying steady"
        }
    }

    private var parentTimingProgressText: String {
        let windows = chartSessions.compactMap(\.avgDecisionWindowSeconds)
        let last = Array(windows.suffix(3))
        guard !last.isEmpty else { return "—" }
        return last.map(parentTimingPhrase).joined(separator: " → ")
    }

    private var parentInsightSentence: String {
        let scoreValues = decisionScorePoints.map(\.value)
        let timingValues = chartSessions.compactMap(\.avgDecisionWindowSeconds)
        guard scoreValues.count >= 2, timingValues.count >= 2 else {
            return "Great start — keep training for earlier decisions."
        }
        let scoreTrend = calculateTrend(values: scoreValues)
        let timingTrend = calculateTrend(values: timingValues)
        if scoreTrend == .up && timingTrend == .up {
            return "Great progress — decisions are happening earlier each session."
        }
        if scoreTrend == .down || timingTrend == .down {
            return "Progress dipped slightly — focus on deciding earlier."
        }
        return "Steady progress — keep aiming for earlier decisions."
    }

    private var parentNextFocusText: String {
        "Decide before the ball reaches halfway"
    }

    private var parentSayCueText: String {
        "Say: \"Know your move before the ball gets to you\""
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
        return UniversalBlockSummaryHeadline.headlineLabel(fast: f, medium: m, slow: s)
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
        case .awayFromPressure: return "Correct First-Decision Trend"
        case .dribbleOrPass: return "Correct Decision Trend"
        case .oneTouchPassing: return "Decision Timing Trend"
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
        case .awayFromPressure, .dribbleOrPass, .twoMinuteTest: return "Decision Timing (Secondary)"
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

    // MARK: - Chart targets (aligned with Home quick snapshot: 80% on 0–100 accuracy-style charts; no line for timing seconds or ambiguous 2‑min score blend)

    private var primaryReferenceY: Double? {
        switch latestActivity {
        case .awayFromPressure, .dribbleOrPass: return 80
        case .oneTouchPassing, .twoMinuteTest, .none: return nil
        }
    }

    private var primaryTargetLabelText: String? {
        guard primaryReferenceY != nil else { return nil }
        switch latestActivity {
        case .awayFromPressure: return "Target: 80% correct first decisions"
        case .dribbleOrPass: return "Target: 80% correct decisions"
        default: return nil
        }
    }

    /// One friendly line above each Player Dashboard chart (no formulas).
    private var primaryChartDescription: String? {
        guard primaryTrendPoints.count >= 2, let a = latestActivity else { return nil }
        switch a {
        case .awayFromPressure:
            return ChartMetricDescriptions.correctFirstDecisionTrend
        case .dribbleOrPass:
            return ChartMetricDescriptions.correctDecisionTrend
        case .oneTouchPassing:
            return ChartMetricDescriptions.decisionTiming
        case .twoMinuteTest:
            return ChartMetricDescriptions.balancedScanTrend
        }
    }

    private var secondaryChartDescription: String? {
        guard secondaryTrendPoints.count >= 2, let a = latestActivity else { return nil }
        switch a {
        case .awayFromPressure, .dribbleOrPass, .twoMinuteTest:
            return ChartMetricDescriptions.decisionTiming
        case .oneTouchPassing:
            return ChartMetricDescriptions.correctDecisionTrend
        }
    }

    private var forwardThinkingChartDescription: String? {
        guard forwardIntentPoints.count >= 2 else { return nil }
        return ChartMetricDescriptions.forwardThinking
    }

    private var secondaryReferenceY: Double? {
        switch latestActivity {
        case .oneTouchPassing: return 80
        default: return nil
        }
    }

    private var secondaryTargetLabelText: String? {
        guard secondaryReferenceY != nil else { return nil }
        if latestActivity == .oneTouchPassing {
            return "Target: 80% correct decisions"
        }
        return nil
    }

    private let forwardThinkingReferenceY: Double = 80
    private let forwardThinkingTargetLabel = "Target: 80% forward choices"

    private func logDashboardGraphClarityDebug() {
        guard chartSessions.count >= 2 else { return }
        if let p = primaryChartDescription {
            print("[GraphClarityRefine-Debug] graphType=player_dashboard_primary explanation=\"\(p)\"")
        }
        if let s = secondaryChartDescription {
            print("[GraphClarityRefine-Debug] graphType=player_dashboard_secondary explanation=\"\(s)\"")
        }
        if let f = forwardThinkingChartDescription {
            print("[GraphClarityRefine-Debug] graphType=player_dashboard_forward_thinking explanation=\"\(f)\"")
        }
    }

    private var teamLeadersSection: some View {
        Group {
            if profileManager.profiles.count >= 2 {
                TeamLeadersThisWeekView(
                    stats: makeTeamStats(
                        profiles: profileManager.profiles,
                        currentPlayerId: activeProfile?.id
                    )
                )
            }
        }
    }

    private var coachChallengeSection: some View {
        Group {
            if profileManager.profiles.count >= 2 {
                TeamChallengeCoachDashboardView(
                    data: makeCoachChallengeDashboardData(profiles: profileManager.profiles)
                )
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if CoachRemoteSessionStartGate.isPadPlayerRole() {
                    if effectiveDashboardRole == .coach {
                        coachChallengeSection
                        teamLeadersSection
                    }
                    playerSnapshotCard
                    progressGraphsSection
                    trainingRecommendationCard
                    ipadPlayerDashboardLinksSection
                } else if effectiveDashboardRole == .coach {
                    coachChallengeSection
                    teamLeadersSection
                    playerSnapshotCard
                    progressGraphsSection
                    trainingRecommendationCard
                    actionsSection
                } else {
                    parentPlayerDashboardSection
                }
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
            syncPlayerHomeGlobalOverlayVisibility()
        }
        .onChange(of: navigateToFullProgress) { _, _ in syncPlayerHomeGlobalOverlayVisibility() }
        .onChange(of: navigateToTrain) { _, _ in syncPlayerHomeGlobalOverlayVisibility() }
        .onChange(of: navigateToReportCard) { _, _ in syncPlayerHomeGlobalOverlayVisibility() }
        .onChange(of: navigateToDevelopmentSnapshot) { _, _ in syncPlayerHomeGlobalOverlayVisibility() }
        .onChange(of: popToRootTrigger.request) { _, requested in
            guard requested else { return }
            navigateToFullProgress = false
            navigateToTrain = false
            navigateToReportCard = false
            navigateToDevelopmentSnapshot = false
            popToRootTrigger.isPlayerHomeLocalNavigationActive = false
            popToRootTrigger.request = false
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

    private func syncPlayerHomeGlobalOverlayVisibility() {
        let active = navigateToFullProgress || navigateToTrain || navigateToReportCard || navigateToDevelopmentSnapshot
        if popToRootTrigger.isPlayerHomeLocalNavigationActive != active {
            popToRootTrigger.isPlayerHomeLocalNavigationActive = active
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headerTitleText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if effectiveDashboardRole == .coach, !CoachRemoteSessionStartGate.isPadPlayerRole() {
                Text("Coach Dashboard")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            } else if CoachRemoteSessionStartGate.isPadPlayerRole() {
                Text("Your progress")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    private var headerTitleText: String {
        if CoachRemoteSessionStartGate.isPadPlayerRole() {
            return activeProfile?.name ?? "Player"
        }
        return effectiveDashboardRole == .coach ? (activeProfile?.name ?? "Player") : "Train"
    }

    private var parentPlayerDashboardSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recommended Next")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(parentRecommendedNext.activityName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.yellow.opacity(0.95))
                Text(parentRecommendedNext.focus)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    router.pushRespectingCoachRemotePadGate(routeForActivity(parentRecommendedNext.activity), coachRemotePrompt: coachRemoteRequiredPrompt)
                } label: {
                    Text("Start Session")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
                .buttonStyle(ParentTapFeedbackButtonStyle())
                .padding(.top, 6)
            }
            .parentCardStyle(prominent: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Other Activities")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                parentActivityButton(title: "Dribble or Pass", activity: .dribbleOrPass)
                parentActivityButton(title: "Playing Away From Pressure", activity: .awayFromPressure)
                parentActivityButton(title: "2-Minute Test", activity: .twoMinuteTest)
            }
            .parentCardStyle()

            VStack(alignment: .leading, spacing: 6) {
                Text("This Week")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))
                HStack(spacing: 10) {
                    Text(parentScoreLabel)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                    Text(parentProgressLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.78))
                }
            }
            .parentCardStyle()
        }
    }

    private func parentActivityButton(title: String, activity: ActivityKind) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            router.pushRespectingCoachRemotePadGate(routeForActivity(activity), coachRemotePrompt: coachRemoteRequiredPrompt)
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(ParentTapFeedbackButtonStyle())
    }

    private var parentProgressLabel: String {
        guard let latest = decisionScorePoints.last?.value else { return "Getting Started" }
        let score = Int(latest.rounded())
        switch score {
        case 90...100: return "Elite Progress"
        case 75...89: return "Strong Progress"
        case 60...74: return "Developing Progress"
        default: return "Building Progress"
        }
    }

    private func routeForActivity(_ activity: ActivityKind) -> AppRoute {
        PBASessionFlowPolicy.routeForActivityLaunch(activity)
    }

    private func parentRecommendationAggregates(from sessions: [SessionResult]) -> (latePercentage: Double, accuracy: Double, score: Double) {
        guard !sessions.isEmpty else { return (0, 0, 0) }

        var lateValues: [Double] = []
        var accuracyValues: [Double] = []
        var scoreValues: [Double] = []

        for session in sessions {
            let timingTotal = session.speedCounts.fast + session.speedCounts.medium + session.speedCounts.slow
            if timingTotal > 0 {
                lateValues.append(Double(session.speedCounts.slow) / Double(timingTotal))
            } else {
                lateValues.append(0)
            }

            if session.totalReps > 0 {
                accuracyValues.append(Double(session.correctCount) / Double(session.totalReps))
            } else {
                accuracyValues.append(0)
            }

            if let decisionScore = session.decisionTotalScore {
                scoreValues.append((decisionScore / 60.0) * 100.0)
            } else if session.totalReps > 0 {
                scoreValues.append(Double(session.correctCount) / Double(session.totalReps) * 100.0)
            } else {
                scoreValues.append(0)
            }
        }

        let avgLate = lateValues.reduce(0, +) / Double(max(1, lateValues.count))
        let avgAccuracy = accuracyValues.reduce(0, +) / Double(max(1, accuracyValues.count))
        let avgScore = scoreValues.reduce(0, +) / Double(max(1, scoreValues.count))
        return (avgLate, avgAccuracy, avgScore)
    }

    private func timingBand(for latePercentage: Double) -> String {
        if latePercentage > 0.40 { return "timing_weakness" }
        if latePercentage >= 0.25 { return "timing_needs_improvement" }
        return "timing_good"
    }

    private func accuracyBand(for accuracy: Double) -> String {
        if accuracy < 0.70 { return "accuracy_weakness" }
        if accuracy <= 0.85 { return "accuracy_developing" }
        return "accuracy_strong"
    }

    private func scoreBand(for score: Double) -> String {
        if score < 70 { return "score_struggling" }
        if score <= 85 { return "score_solid" }
        return "score_strong"
    }

    private func parentTimingPhrase(_ value: Double) -> String {
        if value >= 0 {
            return String(format: "Early by %.2fs", value)
        }
        return String(format: "Late by %.2fs", abs(value))
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
            Text("Decision timing")
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
                VStack(alignment: .leading, spacing: 6) {
                    ProgressLineChartView(
                        title: primaryTrendTitle,
                        points: primaryTrendPoints,
                        valueLabel: primaryTrendValueLabel,
                        yAxisRange: primaryTrendAxis,
                        referenceLineY: primaryTrendPoints.count >= 2 ? primaryReferenceY : nil
                    )
                    if let desc = primaryChartDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    if primaryTrendPoints.count >= 2, let target = primaryTargetLabelText {
                        Text(target)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ProgressLineChartView(
                        title: secondaryTrendTitle,
                        points: secondaryTrendPoints,
                        valueLabel: secondaryTrendValueLabel,
                        yAxisRange: secondaryTrendAxis,
                        referenceLineY: secondaryTrendPoints.count >= 2 ? secondaryReferenceY : nil,
                        emptyStateMessage: "Complete at least 2 sessions to see your trend."
                    )
                    if let desc = secondaryChartDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    if secondaryTrendPoints.count >= 2, let target = secondaryTargetLabelText {
                        Text(target)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ProgressLineChartView(
                        title: "Forward Thinking",
                        points: forwardIntentPoints,
                        valueLabel: "%",
                        yAxisRange: (0, 100),
                        referenceLineY: forwardIntentPoints.count >= 2 ? forwardThinkingReferenceY : nil,
                        emptyStateMessage: "Complete at least 2 Dribble or Pass or One-Touch Passing sessions (with forward opportunities) to see your trend."
                    )
                    if let desc = forwardThinkingChartDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    if forwardIntentPoints.count >= 2 {
                        Text(forwardThinkingTargetLabel)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
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
        .onAppear { logDashboardGraphClarityDebug() }
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

            ipadPlayerDashboardLinksSection
        }
    }

    /// Progress / report destinations only (no session entry). Used on iPad player dashboard.
    private var ipadPlayerDashboardLinksSection: some View {
        VStack(spacing: 12) {
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

private extension View {
    func parentCardStyle(prominent: Bool = false) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(prominent ? Color.white.opacity(0.09) : Color.white.opacity(0.04))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(prominent ? Color.yellow.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct ParentTapFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
