//
//  SessionSummaryMetricsView.swift
//  FootballScanningAI
//
//  PBA V2 — Premium session summary layout (metrics, coaching, next focus).
//

import SwiftUI

// MARK: - Early decision streak (rep tail + persisted session streak; display-only)

enum EarlyDecisionStreak {
    /// Consecutive early (fast) reps at the **end** of the block (matches per-rep increment / reset).
    static func endingEarlyRepCount(from repIsEarlyInOrder: [Bool]) -> Int {
        var streak = 0
        for isEarly in repIsEarlyInOrder.reversed() {
            if isEarly { streak += 1 } else { break }
        }
        return streak
    }

    /// Longest run of consecutive early reps in order (personal-best candidate vs ending streak).
    static func maxConsecutiveEarlyDuringBlock(from repIsEarlyInOrder: [Bool]) -> Int {
        var cur = 0
        var maxVal = 0
        for isEarly in repIsEarlyInOrder {
            if isEarly {
                cur += 1
                maxVal = max(maxVal, cur)
            } else {
                cur = 0
            }
        }
        return maxVal
    }
}

/// Persisted per-player best consecutive early-rep streak (UserDefaults key prefix `bestEarlyStreak`).
enum BestEarlyStreakStore {
    private static func key(for playerId: UUID) -> String {
        "bestEarlyStreak.\(playerId.uuidString)"
    }

    static func current(for playerId: UUID) -> Int {
        UserDefaults.standard.integer(forKey: key(for: playerId))
    }

    /// Updates stored best when `streak` exceeds it; returns the persisted best value.
    @discardableResult
    static func recordIfNewBest(_ streak: Int, playerId: UUID) -> Int {
        let prev = current(for: playerId)
        let new = max(prev, streak)
        if new > prev {
            UserDefaults.standard.set(new, forKey: key(for: playerId))
        }
        return new
    }
}

enum EarlySessionStreakStore {
    /// Per-player storage; product name `earlySessionStreak` (see spec) with UUID suffix for multi-profile safety.
    private static func key(for playerId: UUID) -> String {
        "earlySessionStreak.\(playerId.uuidString)"
    }

    static func current(for playerId: UUID) -> Int {
        UserDefaults.standard.integer(forKey: key(for: playerId))
    }

    /// Session qualifies when ≥90% correct and ≥60% early (fast) reps.
    static func qualifies(_ session: SessionResult) -> Bool {
        let total = session.totalReps
        guard total > 0 else { return false }
        let correct = session.correctCount
        let early = session.speedCounts.fast
        return correct * 100 >= total * 90 && early * 100 >= total * 60
    }

    /// Call after each scored session save. Returns the new streak count.
    @discardableResult
    static func updateAfterSession(_ session: SessionResult) -> Int {
        let id = session.playerID
        let newValue = qualifies(session) ? current(for: id) + 1 : 0
        UserDefaults.standard.set(newValue, forKey: key(for: id))
        return newValue
    }
}

// MARK: - Score milestones (display only; does not affect scoring)

enum SessionScoreMilestone {
    static func nextLevelTarget(score: Int) -> Int? {
        if score < 70 { return 70 }
        if score < 85 { return 85 }
        if score < 95 { return 95 }
        if score < 100 { return 100 }
        return nil
    }

    static func levelLabel(for score: Int) -> String {
        if score < 70 { return "Reactive" }
        if score < 85 { return "Developing" }
        if score < 95 { return "Advancing" }
        return "Elite"
    }

    static func levelColor(for score: Int) -> Color {
        if score < 70 { return .red }
        if score < 85 { return .yellow }
        if score < 95 { return .blue }
        return .green
    }

    static func levelFocusCue(score: Int) -> String {
        if score < 70 {
            return "Focus: Understand where to go first"
        }
        if score < 85 {
            return "Focus: Find the right option earlier"
        }
        if score < 95 {
            return "Focus: Be earlier more consistently"
        }
        return "Focus: Maintain early decisions"
    }

    /// Foreground for the numeric score: perfect run uses bright green; otherwise band color.
    static func scoreNumberForeground(score: Int) -> Color {
        score == 100 ? .green : levelColor(for: score)
    }
}

extension View {
    /// Subtle emphasis when `score == 100` (display only).
    @ViewBuilder
    func perfectScoreHighlight(score: Int) -> some View {
        if score == 100 {
            self.brightness(0.1)
                .shadow(color: Color.green.opacity(0.4), radius: 10)
        } else {
            self
        }
    }
}

/// One-time subtle scale when `score == 100` (results UI; not used for static share snapshots).
struct SessionScoreAnimatedNumber: View {
    let score: Int
    let font: Font
    var useBoldModifier: Bool = false

    @State private var animatePerfect = false

    var body: some View {
        let base = Text("\(score)")
            .font(font)
            .foregroundColor(SessionScoreMilestone.scoreNumberForeground(score: score))
            .perfectScoreHighlight(score: score)

        Group {
            if useBoldModifier {
                base.bold()
            } else {
                base
            }
        }
        .scaleEffect(score == 100 ? (animatePerfect ? 1.08 : 1.0) : 1.0)
        .animation(.easeOut(duration: 0.3), value: animatePerfect)
        .onAppear {
            guard score == 100 else { return }
            DispatchQueue.main.async {
                animatePerfect = true
            }
        }
    }

    /// Phone summary: large title + bold.
    static func phone(score: Int) -> SessionScoreAnimatedNumber {
        SessionScoreAnimatedNumber(score: score, font: .largeTitle, useBoldModifier: true)
    }

    /// Partner iPad: large numeric score.
    static func ipad(score: Int) -> SessionScoreAnimatedNumber {
        SessionScoreAnimatedNumber(score: score, font: .system(size: 72, weight: .bold), useBoldModifier: false)
    }
}

/// Next threshold, points gap, and early-rep hook (uses existing timing counts only).
struct SessionNextLevelProgressBlock: View {
    let score: Int
    let totalReps: Int
    let earlyCount: Int

    var body: some View {
        Group {
            if let nextTarget = SessionScoreMilestone.nextLevelTarget(score: score) {
                let pointsNeeded = nextTarget - score
                let repsNeeded = max(0, totalReps - earlyCount)
                VStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text("Next level: \(nextTarget) (\(SessionScoreMilestone.levelLabel(for: nextTarget)))")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.92))
                        Text("\(pointsNeeded) points away")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if repsNeeded > 0 {
                        Text("\(repsNeeded) more early reps to reach \(nextTarget)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.62))
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

struct SessionSummaryView: View {
    let score: Int
    let visual: FeedbackVisual
    let tags: [FeedbackTag]
    let accuracy: Double
    let avgDecisionTime: Double
    let decisionWindow: Double
    let level: String
    let shortFeedback: String
    let message: String
    let nextFocus: String
    let tempoGuidance: String
    let progressionSuggestion: String?
    var totalReps: Int = 0
    var earlyCount: Int = 0
    var onTimeCount: Int = 0
    var lateCount: Int = 0
    /// 1.0 default; parent briefly uses ~1.04 when crossing a score band vs prior session.
    var levelUpScale: CGFloat = 1.0

    private var timingBreakdown: TimingScoreBreakdown {
        TimingScoreSystem.makeBreakdown(
            early: earlyCount,
            onTime: onTimeCount,
            late: lateCount,
            averageDecisionOffset: decisionWindow
        )
    }

    private var repsTotalForProgress: Int {
        if totalReps > 0 { return totalReps }
        return earlyCount + onTimeCount + lateCount
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Score:")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                    SessionScoreAnimatedNumber.phone(score: score)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Level:")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white.opacity(0.92))
                    Text(level)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(SessionScoreMilestone.scoreNumberForeground(score: score))
                }
                SessionNextLevelProgressBlock(
                    score: score,
                    totalReps: repsTotalForProgress,
                    earlyCount: earlyCount
                )
            }
            .scaleEffect(levelUpScale)

            summaryDivider

            Text(message)
                .font(.body.weight(.semibold))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            summaryDivider

            VStack(spacing: 10) {
                MetricRow(label: "Accuracy", value: "\(Int(accuracy * 100))%")
                MetricRow(label: "Avg Time", value: String(format: "%.1fs", avgDecisionTime))
            }

            summaryDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("Timing")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                MetricRow(label: "Early", value: "\(timingBreakdown.earlyCount)")
                MetricRow(label: "On Time", value: "\(timingBreakdown.onTimeCount)")
                MetricRow(label: "Late", value: "\(timingBreakdown.lateCount)")
            }

            VStack(spacing: 8) {
                Text("Focus")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                Text(nextFocus)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
    }

    private var summaryDivider: some View {
        Divider()
            .background(Color.white.opacity(0.18))
    }
}
