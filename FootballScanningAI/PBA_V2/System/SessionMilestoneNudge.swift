//
//  SessionMilestoneNudge.swift
//  FootballScanningAI
//
//  Lightweight in-session "Almost There" nudges (between reps only).
//

import SwiftUI

enum SessionMilestoneNudgeEvaluator {
    static func nextNudge(
        score: Int,
        earlyCount: Int,
        completedReps: Int,
        targetReps: Int,
        sessionStreakCount: Int
    ) -> String? {
        guard completedReps > 0 else { return nil }

        if let badgeNudge = badgeProgressNudge(earlyCount: earlyCount, completedReps: completedReps) {
            return badgeNudge
        }

        if let scoreNudge = scoreThresholdNudge(score: score) {
            return scoreNudge
        }

        if let streakNudge = streakMilestoneNudge(
            completedReps: completedReps,
            targetReps: targetReps,
            sessionStreakCount: sessionStreakCount
        ) {
            return streakNudge
        }

        return nil
    }

    private static func badgeProgressNudge(earlyCount: Int, completedReps: Int) -> String? {
        let thresholds: [Double] = [0.30, 0.40, 0.50, 0.60]
        let earlyPct = Double(earlyCount) / Double(max(1, completedReps))
        guard let nextIndex = thresholds.firstIndex(where: { earlyPct < $0 }) else { return nil }
        let target = Int(ceil(thresholds[nextIndex] * Double(completedReps)))
        guard target > 0, earlyCount == (target - 1) else { return nil }
        return "⚡ 1 more early decision for Level \(roman(nextIndex + 1))"
    }

    private static func scoreThresholdNudge(score: Int) -> String? {
        let thresholds = [70, 85, 90]
        guard let next = thresholds.first(where: { score < $0 }) else { return nil }
        guard score >= (next - 2) else { return nil }
        return "🏆 1 more early decision to reach \(next)"
    }

    private static func streakMilestoneNudge(completedReps: Int, targetReps: Int, sessionStreakCount: Int) -> String? {
        guard completedReps >= max(1, targetReps - 1) else { return nil }
        let milestones = [3, 5, 10, 20]
        guard let next = milestones.first(where: { $0 > sessionStreakCount }) else { return nil }
        guard (sessionStreakCount + 1) == next else { return nil }
        return "🔥 Finish this session to reach \(next) streak"
    }

    private static func roman(_ value: Int) -> String {
        switch value {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        default: return "I"
        }
    }

    static func endOfSessionPrompt(
        score: Int,
        earlyCount: Int,
        completedReps: Int,
        targetReps: Int,
        sessionStreakCount: Int
    ) -> SessionAlmostTherePrompt? {
        if let badge = badgeProgressPrompt(earlyCount: earlyCount, completedReps: completedReps) {
            return badge
        }
        if let scorePrompt = scoreThresholdPrompt(score: score) {
            return scorePrompt
        }
        if let streakPrompt = streakPrompt(sessionStreakCount: sessionStreakCount) {
            return streakPrompt
        }
        _ = targetReps // kept for call-site symmetry / future extension
        return nil
    }

    private static func badgeProgressPrompt(earlyCount: Int, completedReps: Int) -> SessionAlmostTherePrompt? {
        let thresholds: [Double] = [0.30, 0.40, 0.50, 0.60]
        let earlyPct = Double(earlyCount) / Double(max(1, completedReps))
        guard let nextIndex = thresholds.firstIndex(where: { earlyPct < $0 }) else { return nil }
        let target = Int(ceil(thresholds[nextIndex] * Double(completedReps)))
        guard target > 0, earlyCount == (target - 1) else { return nil }
        return SessionAlmostTherePrompt(
            milestoneName: "Early Thinker Level \(roman(nextIndex + 1))",
            mainMessage: "You were 1 early decision away",
            supportText: "Next time, commit just a bit earlier",
            progress: 0.9
        )
    }

    private static func scoreThresholdPrompt(score: Int) -> SessionAlmostTherePrompt? {
        let thresholds = [70, 85, 90]
        guard let next = thresholds.first(where: { score < $0 }) else { return nil }
        guard score >= (next - 2) else { return nil }
        return SessionAlmostTherePrompt(
            milestoneName: "Score \(next)",
            mainMessage: "You were within reach of \(next)",
            supportText: "Next time, commit just a bit earlier",
            progress: 0.9
        )
    }

    private static func streakPrompt(sessionStreakCount: Int) -> SessionAlmostTherePrompt? {
        let milestones = [3, 5, 10, 20]
        guard let next = milestones.first(where: { $0 > sessionStreakCount }) else { return nil }
        guard (next - sessionStreakCount) == 1 else { return nil }
        return SessionAlmostTherePrompt(
            milestoneName: "\(next) Session Streak",
            mainMessage: "One more session unlocks your streak milestone",
            supportText: "Next time, commit just a bit earlier",
            progress: 0.9
        )
    }
}

struct SessionAlmostTherePrompt: Equatable {
    let milestoneName: String
    let mainMessage: String
    let supportText: String
    let progress: Double
}

struct SessionMilestoneNudgeBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
            .allowsHitTesting(false)
    }
}
