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

struct SessionSummaryView: View {
    let session: SessionResult
    let playerName: String
    /// When true, show "New Personal Best" badge (set when this session just beat the previous best).
    var isNewPersonalBest: Bool = false
    /// New personal bests from this block (decision speed, pressure escape, forward intent). When non-empty, show celebration banner.
    var newPersonalBests: [NewPersonalBest] = []
    /// XP earned from this completed session.
    var xpEarned: Int = 0
    /// Newly unlocked badges from this completed session.
    var newlyUnlockedBadges: [PlayerBadge] = []
    /// When set (e.g. from block summary), "Back to Home" calls this to pop to Progress instead of one level.
    var onBackToHome: (() -> Void)? = nil
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var shareReportItems: [Any] = []
    @State private var navigateToTrainAnother = false
    @State private var navigateToProgress = false
    @State private var decisionScoreScale: CGFloat = 0.8
    @State private var animatedXPEarned: Int = 0
    @State private var showBadgeUnlockAnimation = false

    private var activityName: String { activityDisplayName(session.activityType) }
    private var coachInsightText: String { CoachInsightGenerator.coachInsight(for: session) }
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
    private var accuracyTierLabel: String {
        if accuracyPercentValue >= 90 { return "Elite" }
        if accuracyPercentValue >= 75 { return "Good" }
        return "Needs Work"
    }
    private var decisionSpeedTierLabel: String {
        let t = session.avgDecisionTime ?? 9
        if t < 0.85 { return "Elite" }
        if t < 1.10 { return "Fast" }
        if t <= 1.35 { return "Average" }
        return "Slow"
    }
    private var decisionSpeedTierScore: Int {
        let t = session.avgDecisionTime ?? 9
        if t < 0.85 { return 3 }      // Elite
        if t < 1.10 { return 2 }      // Fast
        if t <= 1.35 { return 1 }     // Average
        return 0                      // Slow
    }
    private var avgDecisionTimeSeconds: Double {
        session.avgDecisionTime ?? 0
    }
    private var decisionSpeedZone: String {
        let t = avgDecisionTimeSeconds
        if t < 0.90 { return "Early" }
        if t <= 1.10 { return "On Time" }
        if t <= 1.20 { return "Slightly Late" }
        return "Too Late"
    }
    private var decisionSpeedHeadline: String {
        switch decisionSpeedZone {
        case "Early": return "Early Decisions"
        case "On Time": return "On-Time Decisions"
        case "Slightly Late": return "Slightly Late Decisions"
        default: return "Too Late"
        }
    }
    private var decisionSpeedZoneEmoji: String {
        switch decisionSpeedZone {
        case "Early": return "🟢"
        case "On Time": return "🔵"
        case "Slightly Late": return "🟠"
        default: return "🔴"
        }
    }
    private var decisionSpeedCoachingMessage: String {
        switch decisionSpeedZone {
        case "Early": return "Excellent — you're deciding early."
        case "On Time": return "Good timing — push toward earlier decisions."
        case "Slightly Late": return "You're reading it well, but committing slightly late."
        default: return "You're waiting too long — decide earlier."
        }
    }
    private var decisionSpeedNextTarget: String {
        switch decisionSpeedZone {
        case "Too Late": return "Next Target: Slightly Late (< 1.20s)"
        case "Slightly Late": return "Next Target: On Time (< 1.10s)"
        case "On Time": return "Next Target: Early (< 0.90s)"
        default: return "Next Target: Keep Early consistency"
        }
    }
    /// Maps avg decision time to a left-to-right marker:
    /// left=Too Late, right=Early.
    private var decisionSpeedZoneProgress: Double {
        let minSec = 0.75
        let maxSec = 1.35
        let normalized = (avgDecisionTimeSeconds - minSec) / (maxSec - minSec)
        return max(0.0, min(1.0, 1.0 - normalized))
    }
    private var forwardThinkingStats: (choices: Int, opportunities: Int, percent: Int, tier: String)? {
        guard let opp = session.forwardOpportunityCount, opp > 0,
              let choice = session.forwardChoiceCount else { return nil }
        let pct = Int(round(Double(choice) / Double(opp) * 100.0))
        let tier: String
        if pct >= 70 { tier = "Elite" }
        else if pct >= 50 { tier = "Positive" }
        else { tier = "Safe" }
        return (choice, opp, pct, tier)
    }
    private var forwardThinkingTierScore: Int? {
        guard let f = forwardThinkingStats else { return nil }
        if f.percent >= 70 { return 3 }      // Elite
        if f.percent >= 50 { return 2 }      // Positive
        return 1                             // Safe
    }
    private var accuracyTierScore: Int {
        if accuracyPercentValue >= 90 { return 3 }   // Elite
        if accuracyPercentValue >= 75 { return 2 }   // Good
        return 1                                     // Needs Work
    }
    private var keyInsight: (focus: String, strength: String?) {
        var metrics: [(name: String, score: Int)] = [
            ("Decision Speed", decisionSpeedTierScore),
            ("Accuracy", accuracyTierScore)
        ]
        if let forwardScore = forwardThinkingTierScore {
            metrics.append(("Forward Thinking", forwardScore))
        }
        let sorted = metrics.sorted { $0.score < $1.score }
        let weakest = sorted.first?.name ?? "Decision Speed"
        let strongest = sorted.last?.name
        let strength = (weakest == strongest) ? nil : strongest
        return (focus: weakest, strength: strength)
    }
    private var keyInsightLine: String {
        let insight = keyInsight
        let focusScore = [
            "Decision Speed": decisionSpeedTierScore,
            "Accuracy": accuracyTierScore,
            "Forward Thinking": forwardThinkingTierScore ?? 2
        ][insight.focus] ?? 2
        if focusScore <= 1 {
            return "Focus Next: \(insight.focus)"
        }
        if let strength = insight.strength {
            return "Strength: \(strength)"
        }
        return "Focus Next: \(insight.focus)"
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

    /// Display-only Decision Speed Score (0–100) derived from session correctness and avg reaction time. No backend change.
    private var displayDecisionSpeedScore: Int? {
        guard session.totalReps > 0 else { return nil }
        let ms = Int((session.avgDecisionTime ?? 1.0) * 1000)
        let reactionTimesMs = [Int](repeating: ms, count: session.totalReps)
        let correct = (0..<session.correctCount).map { _ in true } + (0..<(session.totalReps - session.correctCount)).map { _ in false }
        switch session.activityType {
        case .dribbleOrPass:
            return DecisionSpeedScore.dribbleOrPassSessionScore(reactionTimesMs: reactionTimesMs, correct: correct)
        case .oneTouchPassing:
            return DecisionSpeedScore.oneTouchSessionScore(reactionTimesMs: reactionTimesMs, correct: correct)
        case .awayFromPressure, .twoMinuteTest:
            return DecisionSpeedScore.sessionScore(reactionTimesMs: reactionTimesMs, correct: correct)
        }
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

    var body: some View {
        if !profiles.contains(where: { $0.id == session.playerID }) {
            deletedPlayerPlaceholder
        } else {
            sessionSummaryContent
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
    }

    private var sessionSummaryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                decisionSpeedHeroSection
                coreMetricsSection
                keyInsightCard
                xpFeedbackCard

                buttonsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
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
            runFeedbackAnimations()
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareReportItems)
        }
        .navigationDestination(isPresented: $navigateToTrainAnother) {
            trainAnotherDestination
        }
        .navigationDestination(isPresented: $navigateToProgress) {
            PBAProgressView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    /// 1. Decision Speed Score as main visual: large score, then "New Personal Best" / percentile, then Next Target.
    private var decisionSpeedHeroSection: some View {
        VStack(spacing: 12) {
            Text("\(playerName) • \(activityName)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)

            Text(decisionSpeedHeadline)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Text("\(decisionSpeedZoneEmoji) \(decisionSpeedZone) (\(avgReactionTimeSecondsDisplay))")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avg Decision Time")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                    Text(avgReactionTimeSecondsDisplay)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                    Text("\(accuracyPercentValue)%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            decisionSpeedZoneBar

            Text(decisionSpeedCoachingMessage)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Text(decisionSpeedNextTarget)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow.opacity(0.95))

            if let score = displayDecisionSpeedScore {
                Text("\(score)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .scaleEffect(decisionScoreScale)
                Text("Decision Speed Score")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))

                if !newPersonalBests.isEmpty {
                    newPersonalBestBanner
                } else if isNewPersonalBest {
                    Text("New Personal Best")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.yellow)
                }
                if !newlyUnlockedBadges.isEmpty {
                    badgesUnlockedBanner
                }

            } else {
                Text("—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Text("Decision Speed Score")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                if !newPersonalBests.isEmpty { newPersonalBestBanner }
                if !newlyUnlockedBadges.isEmpty { badgesUnlockedBanner }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var decisionSpeedZoneBar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let markerX = CGFloat(decisionSpeedZoneProgress) * width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.9),
                                Color.orange.opacity(0.9),
                                Color.blue.opacity(0.9),
                                Color.green.opacity(0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                    .offset(x: max(0, min(width - 14, markerX - 7)))
            }
        }
        .frame(height: 14)
        .padding(.horizontal, 6)
        .overlay(
            HStack {
                Text("Too Late")
                Spacer()
                Text("Late")
                Spacer()
                Text("On Time")
                Spacer()
                Text("Early")
            }
            .font(.caption2.weight(.medium))
            .foregroundColor(.white.opacity(0.75))
            .offset(y: 14),
            alignment: .bottom
        )
        .padding(.bottom, 14)
    }

    /// 2) Core Metrics: Decision Accuracy, Forward Thinking, Decision Speed.
    private var coreMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Core Metrics")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            statSection(
                label: "Decision Accuracy",
                value: "\(accuracyDisplayText) • \(accuracyTierLabel)",
                improvement: nil
            )
            if let f = forwardThinkingStats {
                statSection(
                    label: "Forward Thinking",
                    value: "\(f.choices)/\(f.opportunities) (\(f.percent)%) • \(f.tier)",
                    improvement: nil
                )
            } else {
                statSection(
                    label: "Forward Thinking",
                    value: "No forward opportunities this session",
                    improvement: nil
                )
            }
            statSection(
                label: "Decision Speed",
                value: "\(avgReactionTimeSecondsDisplay) • \(decisionSpeedTierLabel)",
                improvement: nil
            )
        }
    }

    private func reactionTimeImprovement(previous: SessionRecord?) -> String? {
        guard let curr = session.avgDecisionTime, let prevSec = previous?.avgLatency else { return nil }
        let diff = prevSec - curr
        if diff > 0.01 { return "↓ \(String(format: "%.2f", diff))s faster" }
        if diff < -0.01 { return "↑ \(String(format: "%.2f", -diff))s slower" }
        return nil
    }

    private func correctDecisionsImprovement(previous: SessionRecord?) -> String? {
        guard let prev = previous else { return nil }
        let diff = session.correctCount - prev.correct
        if diff > 0 { return "+\(diff) since last session" }
        if diff < 0 { return "\(diff) since last session" }
        return nil
    }

    private func statSection(label: String, value: String, improvement: String?) -> some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.75))
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                if let improvement = improvement, !improvement.isEmpty {
                    Text(improvement)
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.95))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var correctCard: some View {
        card {
            VStack(spacing: 8) {
                Text("\(session.correctCount) / \(session.totalReps)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Correct Decisions")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Pressure Escapes: reps where the player successfully escaped (correct direction + exited that gate). AFP only.
    private var pressureEscapesCard: some View {
        card {
            VStack(spacing: 8) {
                Text("\(session.correctCount) / \(session.totalReps)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Pressure Escapes")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var personalBestCard: some View {
        card {
            VStack(spacing: 8) {
                Text("Personal Best")
                    .font(.headline)
                    .foregroundColor(.white)
                if let best = personalBest {
                    Text("\(best.bestCorrect) / \(best.bestTotal)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                } else {
                    Text("First session recorded")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var decisionSpeedCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Decision Speed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let avg = session.avgDecisionTime {
                    Text(String(format: "%.2fs", avg))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    if let band = DecisionSpeedBand.band(forSeconds: avg) {
                        Text(band.label)
                            .font(.caption.weight(.medium))
                            .foregroundColor(band.color)
                        Text(band.explanation)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                HStack(spacing: 12) {
                    pill("Fast", value: session.speedCounts.fast)
                    pill("Medium", value: session.speedCounts.medium)
                    pill("Slow", value: session.speedCounts.slow)
                }
                Text("Goal: more Fast, fewer Slow")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func pill(_ label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12))
        .cornerRadius(20)
    }

    private var biasCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                if let bias = session.biasDirection {
                    Text("Bias: favors \(biasLabel(bias))")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text("Scan the whole field before receiving.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text("Good: using the whole field.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }

    /// Coach Feedback: highlighted card so it stands apart from stats.
    private var coachInsightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach Feedback")
                .font(.headline.weight(.semibold))
                .foregroundColor(.yellow)
            Text(coachInsightText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1.5)
        )
        .cornerRadius(14)
    }

    private var keyInsightCard: some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text("Key Insight")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow)
            Text(keyInsightLine)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.95))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
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
                navigateToTrainAnother = true
            } label: {
                Text("Train Again")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
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

    private var shareText: String {
        var lines: [String] = [
            "\(playerName) — Session Summary",
            activityName,
            "Correct: \(session.correctCount)/\(session.totalReps)",
            "Speed: Fast \(session.speedCounts.fast) / Med \(session.speedCounts.medium) / Slow \(session.speedCounts.slow)",
            "Bias: \(session.biasDirection != nil ? biasLabel(session.biasDirection) : "none")",
            "Coach Insight: \(coachInsightText)"
        ]
        if let avg = session.avgDecisionTime {
            lines.insert("Avg decision time: \(String(format: "%.2f", avg))s", at: 4)
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var trainAnotherDestination: some View {
        switch session.activityType {
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
        decisionScoreScale = 0.8
        withAnimation(.easeOut(duration: 0.22)) {
            decisionScoreScale = 1.0
        }

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

#Preview {
    NavigationStack {
        SessionSummaryView(
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
