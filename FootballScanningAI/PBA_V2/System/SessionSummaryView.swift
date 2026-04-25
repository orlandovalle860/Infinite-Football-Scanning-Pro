//
//  SessionSummaryView.swift
//  FootballScanningAI
//
//  PBA V2 — SCREEN 11 SESSION SUMMARY. Train Another → same activity. Back to Home → HomeDashboardView. Share Report → sheet.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private func activityDisplayName(_ kind: ActivityKind) -> String {
    switch kind {
    case .twoMinuteTest: return "2-Minute Test"
    case .awayFromPressure: return "Playing Away From Pressure"
    case .dribbleOrPass: return "Dribble or Pass"
    case .oneTouchPassing: return "One-Touch Passing"
    }
}

private func biasLabel(_ gate: Gate?) -> String {
    guard let g = gate else { return "none" }
    switch g {
    case .up: return "Up"
    case .down: return "Down"
    case .left: return "Left"
    case .right: return "Right"
    }
}

// MARK: - iPad results display (color — dominant timing + decision quality only)

private enum DecisionTimingCategory {
    case early
    case onTime
    case late
}

private func timingColor(_ category: DecisionTimingCategory) -> Color {
    switch category {
    case .early: return .green
    case .onTime: return .yellow
    case .late: return .red
    }
}

private func decisionTimingCategory(from bucket: SpeedBucket) -> DecisionTimingCategory {
    switch bucket {
    case .fast: return .early
    case .medium: return .onTime
    case .slow: return .late
    }
}

private func qualityColor(correct: Int, total: Int) -> Color {
    guard total > 0 else { return Color.white.opacity(0.88) }
    let ratio = Double(correct) / Double(total)
    if ratio == 1.0 { return .green }
    if ratio >= 0.8 { return .yellow }
    return .red
}

struct SessionSummaryScreenView: View {
    let session: SessionResult
    let playerName: String
    /// When true, show "New Personal Best" badge (set when this session just beat the previous best).
    var isNewPersonalBest: Bool = false
    /// New personal bests from this block (decision speed, away-from-pressure accuracy, forward intent). When non-empty, show celebration banner.
    var newPersonalBests: [NewPersonalBest] = []
    /// XP earned from this completed session.
    var xpEarned: Int = 0
    /// Newly unlocked badges from this completed session.
    var newlyUnlockedBadges: [PlayerBadge] = []
    /// When set (e.g. from block summary), "Back to Home" calls this to pop to Progress instead of one level.
    var onBackToHome: (() -> Void)? = nil
    /// When set (e.g. display session hands off), "Run It Back" restarts the drill without role/setup routing. If nil, falls back to `dismiss()`.
    var onRunItBack: (() -> Void)? = nil
    /// Ending consecutive early reps this block; set from live block summary only (nil from Progress/history).
    var earlyRepEndingStreak: Int? = nil
    /// Persisted all-time best early-rep streak for this player after this block (nil from Progress/history).
    var earlyRepBestStreak: Int? = nil
    /// Multi-session early streak after this save; set only when presenting from a completed block (nil from Progress/history).
    var earlySessionStreakDisplay: Int? = nil
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var shareSheetPayload: BlockShareSheetPayload?
    @State private var showPlayerReport = false
    @State private var navigateToRoleSelection = false
    @State private var roleSelectionTarget: ActivityKind = .awayFromPressure
    @State private var navigateToProgress = false
    @State private var animatedXPEarned: Int = 0
    @State private var showBadgeUnlockAnimation = false
    @State private var almostTherePrompt: SessionAlmostTherePrompt?
    @State private var showAlmostTherePrompt = false

    /// iPad results screen: entrance fade + slide (partner display summary only).
    @State private var ipadResultsAnimateIn = false
    /// Staggered reveal for score → quality → timing (subtle delays, no bounce).
    @State private var ipadResultsRevealScore = false
    @State private var ipadResultsRevealQuality = false
    @State private var ipadResultsRevealTiming = false
    /// Subtle scale when this session’s score crosses a performance band vs the prior block (1.0 → ~1.04 → 1.0).
    @State private var levelUpScale: CGFloat = 1.0

    typealias DecisionSummaryTuple = (
        total: Int,
        correct: Int,
        accuracy: Double,
        avgTime: Double,
        fastCount: Int,
        mediumCount: Int,
        slowCount: Int
    )

    /// Recommendation from the last scored block that matched progression stage (same session only).
    private var coachNextRecommendation: StageSessionRecommendation? {
        guard let p = profileManager.currentProfile, p.id == session.playerID,
              let r = p.lastStageRecommendation, r.tiedSessionId == session.id else { return nil }
        return r
    }

    private var playerSessionFeedback: PlayerFeedback {
        PlayerFeedbackEngine.feedback(from: session)
    }

    private var playerRecommendation: PlayerRecommendation {
        let accuracy = session.totalReps > 0 ? Double(session.correctCount) / Double(session.totalReps) : 0
        let decisionWindow = session.avgDecisionWindowSeconds ?? 0
        return generateRecommendation(
            score: decisionScoreValue,
            accuracy: accuracy,
            decisionWindow: decisionWindow,
            recentScores: recentRecommendationScores,
            totalReps: session.totalReps
        )
    }

    private var levelFeedbackVisual: FeedbackVisual {
        switch playerRecommendation.level {
        case .elite:
            return FeedbackVisual(icon: "bolt.fill", color: .green, title: "Elite")
        case .advancing:
            return FeedbackVisual(icon: "arrow.up.circle.fill", color: .blue, title: "Advancing")
        case .developing:
            return FeedbackVisual(icon: "chart.line.uptrend.xyaxis.circle.fill", color: .orange, title: "Developing")
        case .reactive:
            return FeedbackVisual(icon: "exclamationmark.triangle.fill", color: .red, title: "Reactive")
        }
    }

    private var recentRecommendationScores: [Int] {
        let sessions = profileManager.profile(id: session.playerID)?.sessionResults ?? []
        return sessions.sorted(by: { (lhs: SessionResult, rhs: SessionResult) in
            lhs.date < rhs.date
        }).map { result in
            if let score = result.decisionTotalScore {
                return max(0, min(100, Int(score.rounded())))
            }
            return result.estimatedDecisionSpeedScore ?? 0
        }
    }

    /// Last five sessions for this player (oldest → newest), for progression UI.
    private var recentProgressionSessions: [SessionPerformance] {
        let pool = profileManager.profile(id: session.playerID)?.sessionResults ?? []
        return getRecentSessions(from: pool, limit: 5)
    }

    private var progressionScoreTrend: TrendDirection {
        calculateTrend(values: recentProgressionSessions.map { Double($0.score) })
    }

    private var progressionWindowTrend: TrendDirection {
        calculateTrend(values: recentProgressionSessions.map(\.avgDecisionWindow))
    }

    private var progressionAccuracyTrend: TrendDirection {
        calculateTrend(values: recentProgressionSessions.map(\.accuracy))
    }

    private var progressionInsight: String {
        generateInsight(
            scoreTrend: progressionScoreTrend,
            windowTrend: progressionWindowTrend,
            accuracyTrend: progressionAccuracyTrend
        )
    }

    /// All stored sessions as performance snapshots; `generateProgression` / `getAverages` use the last 5 by date.
    private var sessionPerformancesForLevel: [SessionPerformance] {
        profileManager.profile(id: session.playerID)?.sessionResults.map(\.sessionPerformance) ?? []
    }

    private var summaryPlayerProgression: PlayerProgression {
        generateProgression(sessions: sessionPerformancesForLevel)
    }

    private var levelTrainingRecommendation: LevelRecommendation {
        getLevelRecommendation(level: summaryPlayerProgression.currentLevel)
    }

    private var levelTrainingDifficulty: DifficultySettings {
        getDifficulty(for: summaryPlayerProgression.currentLevel)
    }

    private var sessionPlayerReport: PlayerReport {
        generatePlayerReport(
            playerName: playerName,
            progression: summaryPlayerProgression,
            score: decisionScoreValue,
            accuracy: coreSummary.accuracy,
            decisionWindow: session.avgDecisionWindowSeconds ?? 0,
            trendWindow: progressionWindowTrend,
            trendAccuracy: progressionAccuracyTrend,
            recommendation: levelTrainingRecommendation
        )
    }

    init(
        session: SessionResult,
        playerName: String,
        profileManager: UserProfileManager,
        settingsViewModel: SettingsViewModel
    ) {
        self.session = session
        self.playerName = playerName
        self.profileManager = profileManager
        self.settingsViewModel = settingsViewModel
    }

    init(
        session: SessionResult,
        playerName: String,
        isNewPersonalBest: Bool = false,
        newPersonalBests: [NewPersonalBest] = [],
        xpEarned: Int = 0,
        newlyUnlockedBadges: [PlayerBadge] = [],
        onBackToHome: (() -> Void)? = nil,
        onRunItBack: (() -> Void)? = nil,
        earlyRepEndingStreak: Int? = nil,
        earlyRepBestStreak: Int? = nil,
        earlySessionStreakDisplay: Int? = nil,
        profileManager: UserProfileManager,
        settingsViewModel: SettingsViewModel
    ) {
        self.session = session
        self.playerName = playerName
        self.isNewPersonalBest = isNewPersonalBest
        self.newPersonalBests = newPersonalBests
        self.xpEarned = xpEarned
        self.newlyUnlockedBadges = newlyUnlockedBadges
        self.onBackToHome = onBackToHome
        self.onRunItBack = onRunItBack
        self.earlyRepEndingStreak = earlyRepEndingStreak
        self.earlyRepBestStreak = earlyRepBestStreak
        self.earlySessionStreakDisplay = earlySessionStreakDisplay
        self.profileManager = profileManager
        self.settingsViewModel = settingsViewModel
    }

    init(
        summary: DecisionSummaryTuple,
        activityType: ActivityKind = .oneTouchPassing,
        playerName: String = "Player",
        directionCounts: [Gate: Int] = [:],
        profileManager: UserProfileManager = UserProfileManager(),
        settingsViewModel: SettingsViewModel = SettingsViewModel()
    ) {
        self.session = SessionResult(
            playerID: profileManager.currentProfile?.id ?? UUID(),
            activityType: activityType,
            correctCount: summary.correct,
            totalReps: summary.total,
            speedCounts: SessionSpeedCounts(
                fast: summary.fastCount,
                medium: summary.mediumCount,
                slow: summary.slowCount
            ),
            avgDecisionTime: summary.avgTime,
            directionCounts: directionCounts
        )
        self.playerName = playerName
        self.profileManager = profileManager
        self.settingsViewModel = settingsViewModel
    }

    private var activityName: String { activityDisplayName(session.activityType) }
    private var avgReactionTimeSecondsDisplay: String {
        String(format: "%.2fs", session.avgDecisionTime ?? 0)
    }
    private var accuracyPercentValue: Int {
        guard session.totalReps > 0 else { return 0 }
        return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100.0))
    }
    private var accuracyDisplayText: String {
        "\(session.correctCount)/\(session.totalReps) (\(accuracyPercentValue)%)"
    }
    private var coreSummary: (
        total: Int,
        correct: Int,
        accuracy: Double,
        avgTime: Double,
        fastCount: Int,
        mediumCount: Int,
        slowCount: Int
    ) {
        (
            total: session.totalReps,
            correct: session.correctCount,
            accuracy: Double(accuracyPercentValue) / 100.0,
            avgTime: session.avgDecisionTime ?? 0,
            fastCount: session.speedCounts.fast,
            mediumCount: session.speedCounts.medium,
            slowCount: session.speedCounts.slow
        )
    }
    private var decisionScoreValue: Int {
        if let score = session.decisionTotalScore {
            return max(0, min(100, Int(score.rounded())))
        }
        return session.estimatedDecisionSpeedScore ?? 0
    }
    private var forwardThinkingStats: (choices: Int, opportunities: Int, percent: Int)? {
        guard let opp = session.forwardOpportunityCount, opp > 0,
              let choice = session.forwardChoiceCount else { return nil }
        let pct = Int(round(Double(choice) / Double(opp) * 100.0))
        return (choice, opp, pct)
    }
    private var primaryMetricLabel: String {
        switch session.activityType {
        case .awayFromPressure: return "Correct first decisions"
        case .dribbleOrPass: return "Decision correctness"
        case .oneTouchPassing: return "Decision window"
        case .twoMinuteTest: return "Balanced score"
        }
    }
    private var primaryMetricValue: String {
        switch session.activityType {
        case .awayFromPressure, .dribbleOrPass:
            return accuracyDisplayText
        case .oneTouchPassing:
            return session.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—"
        case .twoMinuteTest:
            let window = session.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—"
            return "\(accuracyPercentValue)% · \(window)"
        }
    }
    private var progressionMessage: String? {
        let progress = GuidedCurriculumEngine.currentProgress(playerId: session.playerID)
        let accuracy = Double(accuracyPercentValue)
        let avg = session.avgDecisionTime ?? 9
        let forwardPct = forwardThinkingStats?.percent
        switch progress.stage {
        case 1:
            if accuracy >= 65, avg <= 1.35 { return "You're close to Stage 2." }
        case 2:
            if accuracy >= 65, avg <= 1.20, (forwardPct ?? 0) >= 35 { return "You're close to Stage 3." }
        default:
            if accuracy >= 70, avg <= 1.05 { return "You're close to the next loop." }
        }
        return nil
    }

    /// Display-only Decision Speed Score (0–100); same formula as stored session score.
    private var displayDecisionSpeedScore: Int? { session.estimatedDecisionSpeedScore }

    /// Compact celebration above the narrative (badges + PB); avoids duplicating full banners inside hero.
    private var sessionCelebrationStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !newPersonalBests.isEmpty {
                newPersonalBestBanner
            } else if isNewPersonalBest {
                Text("New Personal Best")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(12)
            }
            if !newlyUnlockedBadges.isEmpty {
                badgesUnlockedBanner
            }
        }
    }

    private var shouldShowEarlyDecisionStreakLines: Bool {
        if (earlySessionStreakDisplay ?? 0) >= 2 { return true }
        let best = earlyRepBestStreak ?? 0
        if best > 0 { return true }
        return (earlyRepEndingStreak ?? 0) >= 3
    }

    private var earlyDecisionStreakLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let best = earlyRepBestStreak, best > 0 {
                EarlyRepStreakBestVsCurrentLines(rep: earlyRepEndingStreak ?? 0, best: best)
            } else if let rep = earlyRepEndingStreak, rep >= 3 {
                Text("Early streak: \(rep)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let sess = earlySessionStreakDisplay, sess >= 2 {
                Text("\(sess) sessions in a row with early decisions")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ipadEarlyDecisionStreakLines: some View {
        VStack(spacing: 6) {
            if let best = earlyRepBestStreak, best > 0 {
                EarlyRepStreakBestVsCurrentLines(rep: earlyRepEndingStreak ?? 0, best: best)
            } else if let rep = earlyRepEndingStreak, rep >= 3 {
                Text("Early streak: \(rep)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let sess = earlySessionStreakDisplay, sess >= 2 {
                Text("\(sess) sessions in a row with early decisions")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var newPersonalBestBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Personal Best!")
                .font(.headline.weight(.semibold))
                .foregroundColor(.yellow)
            ForEach(Array(newPersonalBests.enumerated()), id: \.offset) { _, best in
                VStack(alignment: .leading, spacing: 2) {
                    Text(best.title)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.95))
                    Text(best.improvementText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(12)
        .opacity(showBadgeUnlockAnimation ? 1 : 0)
        .scaleEffect(showBadgeUnlockAnimation ? 1.0 : 0.94)
    }

    private var badgesUnlockedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badge Unlocked!")
                .font(.headline.weight(.semibold))
                .foregroundColor(.yellow)
            ForEach(newlyUnlockedBadges, id: \.rawValue) { badge in
                Text("• \(badge.title)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var personalBest: ActivityBest? {
        profileManager.currentProfile?.personalBests[session.activityType]
            ?? profileManager.profiles.first(where: { $0.id == session.playerID })?.personalBests[session.activityType]
    }

    private var profiles: [UserProfile] { profileManager.profiles }

    /// Session before this one (same activity + player) for trend lines; nil if first session.
    private var previousSessionRecord: SessionRecord? {
        progressStore.previous(session.activityType, playerId: session.playerID)
    }

    /// Prior block’s decision score (0–100) for level-band animation; if unknown, matches current so no false “level up.”
    private var previousBlockScoreForLevelAnimation: Int {
        guard let prev = previousSessionRecord else { return decisionScoreValue }
        if let s = prev.decisionSpeedScore {
            return max(0, min(100, s))
        }
        return decisionScoreValue
    }

    private var didCrossPerformanceLevelBand: Bool {
        SessionScoreMilestone.levelLabel(for: decisionScoreValue) != SessionScoreMilestone.levelLabel(for: previousBlockScoreForLevelAnimation)
    }

    private func runLevelUpScaleIfNeeded() {
        guard didCrossPerformanceLevelBand else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            levelUpScale = 1.04
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.25)) {
                levelUpScale = 1.0
            }
        }
    }

    private var postSessionNarrative: PBAPostSessionNarrative {
        PBAPostSessionNarrativeBuilder.fromSessionResult(
            session,
            previousSession: previousSessionRecord,
            progressStore: progressStore
        )
    }

    /// Player iPad is display-only; Coach Remote owns all training control (see ``CoachRemoteSessionStartGate``).
    private var isPlayerIPadDisplayOnly: Bool {
        CoachRemoteSessionStartGate.isPadPlayerRole()
    }

    var body: some View {
        Group {
            if !profiles.contains(where: { $0.id == session.playerID }) {
                deletedPlayerPlaceholder
            } else if isPlayerIPadDisplayOnly {
                playerIPadDisplayOnlyContent
            } else {
                sessionSummaryContent
            }
        }
        .onAppear {
            runLevelUpScaleIfNeeded()
        }
        .sheet(item: $shareSheetPayload) { payload in
            ShareSheet(items: payload.items)
        }
    }

    private var deletedPlayerPlaceholder: some View {
        VStack(spacing: 16) {
            Text("Player no longer available.")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
    }

    /// Dominant decision-speed bucket (fast / medium / slow) for display copy.
    private var ipadDominantTimingBucket: SpeedBucket {
        let c = session.speedCounts
        return UniversalBlockSummaryHeadline.resolve(fast: c.fast, medium: c.medium, slow: c.slow).bucket
    }

    private func ipadTimingLabel(_ bucket: SpeedBucket) -> String {
        switch bucket {
        case .fast: return "Early"
        case .medium: return "On Time"
        case .slow: return "Late"
        }
    }

    /// iPad results: decision quality line (copy only; no scoring changes).
    private var ipadDecisionQualityLine: String {
        let correct = session.correctCount
        let total = session.totalReps
        if total > 0, correct == total {
            return "Perfect decisions (\(correct) / \(total))"
        }
        return "\(correct) / \(total) correct"
    }

    private func ipadActivityFeedback(activity: ActivityKind, timing: SpeedBucket) -> String {
        let pocket = UniversalBlockSummaryHeadline.pocketMomentInterpretationLine(
            fast: session.speedCounts.fast,
            medium: session.speedCounts.medium,
            slow: session.speedCounts.slow
        )
        switch activity {
        case .twoMinuteTest:
            return pocket
        case .awayFromPressure:
            return timing == .fast
                ? "Away from pressure: you’re clearing space early."
                : pocket
        case .dribbleOrPass:
            return timing == .fast
                ? "Dribble or pass: decisions are ahead of the defender."
                : pocket
        case .oneTouchPassing:
            return timing == .fast
                ? "One-touch: you’re set before the ball arrives."
                : pocket
        }
    }

    private var ipadSummaryDivider: some View {
        Divider()
            .background(Color.white.opacity(0.22))
    }

    /// Read-only results for partner display iPad: no actions, no navigation, no session start.
    private var playerIPadDisplayOnlyContent: some View {
        let dominant = ipadDominantTimingBucket
        let c = session.speedCounts
        return ScrollView {
            VStack(alignment: .center, spacing: 20) {
                Group {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activityName)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                        Text(playerName)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.72))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        SessionScoreAnimatedNumber.ipad(score: decisionScoreValue)
                        Text(playerRecommendation.level.rawValue)
                            .font(.headline)
                            .foregroundColor(SessionScoreMilestone.scoreNumberForeground(score: decisionScoreValue))
                        SessionNextLevelProgressBlock(
                            score: decisionScoreValue,
                            totalReps: session.totalReps,
                            earlyCount: session.speedCounts.fast
                        )
                    }
                    .scaleEffect(levelUpScale)
                    .frame(maxWidth: .infinity)

                    if shouldShowEarlyDecisionStreakLines {
                        ipadEarlyDecisionStreakLines
                    }
                }
                .opacity(ipadResultsRevealScore ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: ipadResultsRevealScore)

                Group {
                    ipadSummaryDivider

                    VStack(spacing: 8) {
                        Text("Decision Quality")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(ipadDecisionQualityLine)
                            .font(.title3)
                            .foregroundColor(qualityColor(correct: session.correctCount, total: session.totalReps))
                    }
                    .frame(maxWidth: .infinity)
                }
                .opacity(ipadResultsRevealQuality ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: ipadResultsRevealQuality)

                Group {
                    ipadSummaryDivider

                    VStack(spacing: 8) {
                        Text("Decision Timing")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(ipadTimingLabel(dominant))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(timingColor(decisionTimingCategory(from: dominant)))
                        HStack(spacing: 12) {
                            Text("Early: \(c.fast)")
                            Text("On Time: \(c.medium)")
                            Text("Late: \(c.slow)")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .opacity(ipadResultsRevealTiming ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: ipadResultsRevealTiming)

                Group {
                    ipadSummaryDivider

                    Text(ipadActivityFeedback(activity: session.activityType, timing: dominant))
                        .font(.body)
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(SessionScoreMilestone.levelFocusCue(score: decisionScoreValue))
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    Text("Use the coach remote to start the next block.")
                        .font(.body.weight(.medium))
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    HStack {
                        Spacer()
                        Button {
                            presentBlockShareSheet()
                        } label: {
                            Text("Share Result")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.88))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .opacity(ipadResultsRevealTiming ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: ipadResultsRevealTiming)
            }
            .padding(24)
            .opacity(ipadResultsAnimateIn ? 1 : 0)
            .offset(y: ipadResultsAnimateIn ? 0 : 10)
            .animation(.easeOut(duration: 0.4), value: ipadResultsAnimateIn)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            runIPadResultsEntranceAnimation()
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            runFeedbackAnimations()
        }
        .onDisappear {
            ipadResultsAnimateIn = false
            ipadResultsRevealScore = false
            ipadResultsRevealQuality = false
            ipadResultsRevealTiming = false
        }
    }

    /// Fade/slide the screen in, then lightly stagger score → quality → timing (under 0.5s total feel).
    private func runIPadResultsEntranceAnimation() {
        ipadResultsAnimateIn = true
        let stagger: TimeInterval = 0.07
        DispatchQueue.main.asyncAfter(deadline: .now() + stagger) {
            withAnimation(.easeOut(duration: 0.35)) {
                ipadResultsRevealScore = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + stagger * 2) {
            withAnimation(.easeOut(duration: 0.35)) {
                ipadResultsRevealQuality = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + stagger * 3) {
            withAnimation(.easeOut(duration: 0.35)) {
                ipadResultsRevealTiming = true
            }
        }
    }

    private var sessionSummaryContent: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    simpleSummarySection

                    buttonsSection
                }
                .padding(24)
            }
            if showAlmostTherePrompt, let prompt = almostTherePrompt {
                almostThereOverlay(prompt: prompt)
                    .zIndex(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            runFeedbackAnimations()
            evaluateAlmostTherePrompt()
        }
        .sheet(isPresented: $showPlayerReport) {
            SessionPlayerReportView(report: sessionPlayerReport)
        }
        .navigationDestination(isPresented: $navigateToRoleSelection) {
            roleSelectionDestination(for: roleSelectionTarget)
        }
        .navigationDestination(isPresented: $navigateToProgress) {
            PBAProgressView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private var simpleSummarySection: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Level: \(summaryPlayerProgression.currentLevel.rawValue)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                Text(summaryPlayerProgression.currentLevel.progressionSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended Next")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                Text(levelTrainingRecommendation.activity.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                Text("Focus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text(levelTrainingRecommendation.focus)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.06))
            .cornerRadius(14)

            if !newPersonalBests.isEmpty || isNewPersonalBest || !newlyUnlockedBadges.isEmpty {
                sessionCelebrationStrip
            }

            if shouldShowEarlyDecisionStreakLines {
                earlyDecisionStreakLines
            }

            SessionSummaryView(
                score: decisionScoreValue,
                visual: levelFeedbackVisual,
                tags: PlayerFeedbackEngine.feedbackTags(from: session),
                accuracy: coreSummary.accuracy,
                avgDecisionTime: session.avgDecisionTime ?? 0,
                decisionWindow: session.avgDecisionWindowSeconds ?? 0,
                level: playerRecommendation.level.rawValue,
                shortFeedback: playerRecommendation.shortFeedback,
                message: playerSessionFeedback.message,
                nextFocus: SessionScoreMilestone.levelFocusCue(score: decisionScoreValue),
                tempoGuidance: playerRecommendation.tempoGuidance,
                progressionSuggestion: playerRecommendation.progressionSuggestion,
                totalReps: session.totalReps,
                earlyCount: session.speedCounts.fast,
                onTimeCount: session.speedCounts.medium,
                lateCount: session.speedCounts.slow,
                levelUpScale: levelUpScale
            )

            if !recentProgressionSessions.isEmpty {
                ProgressionView(
                    sessions: recentProgressionSessions,
                    scoreTrend: progressionScoreTrend,
                    windowTrend: progressionWindowTrend,
                    accuracyTrend: progressionAccuracyTrend,
                    insight: progressionInsight
                )
            }

            if let next = coachNextRecommendation {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next session (coach)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text(next.message)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text("Focus: \(next.focusTag.rawValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.cyan.opacity(0.95))
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                        Text(next.activity)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white.opacity(0.08))
                .cornerRadius(14)
            }
        }
    }

    /// E. Your numbers — reference metrics after the debrief (no tier labels that fight the headline).
    private var yourNumbersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your numbers")
                .font(.title3.weight(.bold))
                .foregroundColor(.white.opacity(0.95))
            Text("\(playerName) · \(activityName)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
            Text("Reference only — your coach debrief is above.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 12) {
                yourNumbersRow(label: primaryMetricLabel, value: primaryMetricValue)
                if session.activityType != .oneTouchPassing {
                    yourNumbersRow(label: "Decision window", value: session.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")
                }
                if session.activityType != .awayFromPressure && session.activityType != .dribbleOrPass {
                    yourNumbersRow(label: "Correct decisions", value: accuracyDisplayText)
                }
                yourNumbersDecisionSpeedBlock
                if let score = displayDecisionSpeedScore {
                    yourNumbersRow(label: "Decision Speed Score", value: "\(score)")
                }
                if let f = forwardThinkingStats {
                    yourNumbersRow(label: "Forward choices", value: "\(f.choices) / \(f.opportunities) (\(f.percent)%)")
                }
                if let best = personalBest {
                    yourNumbersRow(label: "Your best (this activity)", value: "\(best.bestCorrect) / \(best.bestTotal)")
                }
            }

            if let delta = yourNumbersDeltaCaption {
                Text(delta)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private var yourNumbersDecisionSpeedBlock: some View {
        let c = session.speedCounts
        let bucket = UniversalBlockSummaryHeadline.resolve(fast: c.fast, medium: c.medium, slow: c.slow).bucket
        return HStack(alignment: .top, spacing: 12) {
            Text("Decision speed")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.78))
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(bucket.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                BlockSummarySpeedCountsSubline(
                    fast: c.fast,
                    medium: c.medium,
                    slow: c.slow,
                    foregroundColor: .white.opacity(0.55),
                    textAlignment: .trailing,
                    debugActivity: session.activityType
                )
            }
        }
    }

    private func yourNumbersRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.78))
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Short delta line for E (trend detail lives in the debrief stack).
    private var yourNumbersDeltaCaption: String? {
        guard let prev = previousSessionRecord else { return nil }
        var parts: [String] = []
        if let c = session.avgDecisionWindowSeconds, let p = prev.avgDecisionWindowSeconds {
            let diff = c - p
            if diff > 0.02 {
                parts.append(String(format: "Δ window: +%.2fs", diff))
            } else if diff < -0.02 {
                parts.append(String(format: "Δ window: %.2fs", diff))
            } else {
                parts.append("Δ window: flat")
            }
        }
        let dc = session.correctCount - prev.correct
        if dc > 0 {
            parts.append("Δ correct: +\(dc)")
        } else if dc < 0 {
            parts.append("Δ correct: \(dc)")
        } else {
            parts.append("Δ correct: same")
        }
        return parts.joined(separator: " · ")
    }

    /// 4) XP feedback + progression cue.
    private var xpFeedbackCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XP Feedback")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow)
            Text("+\(animatedXPEarned) XP this session")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.95))
            if let msg = progressionMessage {
                Text(msg)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    private var buttonsSection: some View {
        VStack(spacing: 12) {
            Button {
                startRecommended()
            } label: {
                Text("Start Recommended")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                runItBack()
            } label: {
                Text("Run It Back")
                    .font(.headline)
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow.opacity(0.18))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.yellow.opacity(0.55), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                showPlayerReport = true
            } label: {
                Text("View player report")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                presentBlockShareSheet()
            } label: {
                Text("Share Result")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                router.popToRoot()
            } label: {
                Text("Back to Home")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func almostThereOverlay(prompt: SessionAlmostTherePrompt) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("So close.")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.yellow)
                Text(prompt.milestoneName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text(prompt.mainMessage)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(prompt.supportText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                ProgressView(value: prompt.progress, total: 1)
                    .tint(.yellow)
                    .padding(.top, 2)
                Button {
                    runItBack()
                } label: {
                    Text("Run It Back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                Button {
                    showAlmostTherePrompt = false
                } label: {
                    Text("Done")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.88))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(Color.black.opacity(0.9))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    private func evaluateAlmostTherePrompt() {
        let completedReps = max(1, session.totalReps)
        let earlyCount = session.speedCounts.fast
        let score = decisionScoreValue
        let streak = profileManager.profile(id: session.playerID)?.sessionStreakCount ?? 0
        almostTherePrompt = SessionMilestoneNudgeEvaluator.endOfSessionPrompt(
            score: score,
            earlyCount: earlyCount,
            completedReps: completedReps,
            targetReps: completedReps,
            sessionStreakCount: streak
        )
        showAlmostTherePrompt = (almostTherePrompt != nil)
    }

    private func runItBack() {
        showAlmostTherePrompt = false
        profileManager.pendingLevelDifficulty = nil
        if let onRunItBack {
            onRunItBack()
        } else {
            dismiss()
        }
    }

    private func startRecommended() {
        showAlmostTherePrompt = false
        profileManager.pendingLevelDifficulty = levelTrainingDifficulty
        roleSelectionTarget = levelTrainingRecommendation.activity
        navigateToRoleSelection = true
    }

    private func presentBlockShareSheet() {
        shareSheetPayload = BlockShareSheetPayload(
            items: SessionBlockShare.activityItems(
                session: session,
                playerName: playerName,
                playerRecommendation: playerRecommendation
            )
        )
    }

    @ViewBuilder
    private func roleSelectionDestination(for activity: ActivityKind) -> some View {
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

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
    }

    private func runFeedbackAnimations() {
        animatedXPEarned = 0
        if xpEarned > 0 {
            Task { @MainActor in
                let steps = min(24, max(8, xpEarned / 8))
                for step in 1...steps {
                    let progress = Double(step) / Double(steps)
                    animatedXPEarned = Int((Double(xpEarned) * progress).rounded())
                    try? await Task.sleep(nanoseconds: 18_000_000)
                }
                animatedXPEarned = xpEarned
            }
        }

        showBadgeUnlockAnimation = false
        if !newlyUnlockedBadges.isEmpty {
            withAnimation(.easeOut(duration: 0.2).delay(0.06)) {
                showBadgeUnlockAnimation = true
            }
            triggerBadgeHaptic()
        }
    }

    private func triggerBadgeHaptic() {
#if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
#endif
    }
}

/// Best vs current early-rep streak (results only); subtle scale when ending streak matches all-time best.
private struct EarlyRepStreakBestVsCurrentLines: View {
    let rep: Int
    let best: Int
    @State private var pulseScale: CGFloat = 1.0

    private var isNewBestLine: Bool {
        rep == best && rep > 0
    }

    var body: some View {
        Group {
            if isNewBestLine {
                Text("Early streak: \(rep) (New Best)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.35)) { pulseScale = 1.04 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.25)) { pulseScale = 1.0 }
                        }
                    }
            } else {
                Text("Early streak: \(rep) (Best: \(best))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SessionSummaryScreenView(
            session: SessionResult(
                playerID: UUID(),
                activityType: .awayFromPressure,
                correctCount: 9,
                totalReps: 12,
                speedCounts: SessionSpeedCounts(fast: 4, medium: 5, slow: 3),
                avgDecisionTime: 1.4,
                biasDirection: .left,
                directionCounts: [.left: 5, .right: 3, .up: 2, .down: 2],
                difficulty: .standard
            ),
            playerName: "Orlando",
            profileManager: UserProfileManager(),
            settingsViewModel: SettingsViewModel()
        )
        .environmentObject(ProgressStore())
        .environmentObject(PlayerStore())
        .environmentObject(PopToRootTrigger())
        .environmentObject(AppRouter())
    }
}
