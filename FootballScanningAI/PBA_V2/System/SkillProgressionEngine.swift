//
//  SkillProgressionEngine.swift
//  FootballScanningAI
//
//  PBA V2 — Recommends next activity based on mastery (accuracy, reaction time, decision speed score).
//  Curriculum: Playing Away From Pressure → Dribble or Pass → One-Touch Passing → (Four Goal Game).
//

import Foundation

/// Mastery thresholds for one activity (from last session).
struct SkillProgressionConfig {
    static let minAccuracy: Double = 0.80
    static let maxAverageReactionTimeMs: Int = 750
    static let minDecisionSpeedScore: Int = 60
}

/// Result of the skill progression recommendation.
struct SkillProgressionRecommendation {
    /// Activity to do next (repeat current or advance to next).
    let recommendedActivity: ActivityKind
    /// "You're ready for X." or "Keep training X to improve ..."
    let message: String
    /// True when we recommend repeating the current activity (not mastered yet).
    let isRepeat: Bool
}

enum SkillProgressionEngine {
    /// Curriculum order for training activities (excluding 2-Minute Test).
    private static let curriculumOrder: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]

    /// Activity display name for messages.
    static func activityTitle(_ activity: ActivityKind) -> String {
        switch activity {
        case .twoMinuteTest: return "2-Minute Test"
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        }
    }

    /// Whether the last session for this activity meets mastery: accuracy >= 0.80, avg reaction <= 750 ms, decision speed score >= 60.
    static func isMastered(progressStore: ProgressStore, activity: ActivityKind, playerId: UUID?) -> Bool {
        guard let last = progressStore.last(activity, playerId: playerId) else { return false }
        let total = last.decisionsCompleted
        guard total > 0 else { return false }
        let accuracy = Double(last.correct) / Double(total)
        guard accuracy >= SkillProgressionConfig.minAccuracy else { return false }
        let avgReactionMs: Int
        if let sec = last.avgLatency {
            avgReactionMs = Int(sec * 1000)
        } else {
            return false
        }
        guard avgReactionMs <= SkillProgressionConfig.maxAverageReactionTimeMs else { return false }
        guard let score = last.decisionSpeedScore, score >= SkillProgressionConfig.minDecisionSpeedScore else { return false }
        return true
    }

    /// Which criterion is failing for the current activity (for "Keep training X to improve Y").
    private static func failingCriterion(progressStore: ProgressStore, activity: ActivityKind, playerId: UUID?) -> String {
        guard let last = progressStore.last(activity, playerId: playerId) else { return "decision speed" }
        let total = last.decisionsCompleted
        if total == 0 { return "decision speed" }
        let accuracy = Double(last.correct) / Double(total)
        if accuracy < SkillProgressionConfig.minAccuracy { return "accuracy" }
        if let sec = last.avgLatency, Int(sec * 1000) > SkillProgressionConfig.maxAverageReactionTimeMs {
            return "reaction time"
        }
        if let score = last.decisionSpeedScore, score < SkillProgressionConfig.minDecisionSpeedScore {
            return "decision speed"
        }
        return "decision speed"
    }

    /// Recommended next activity and message: if current (first non-mastered) is not mastered → repeat with "Keep training X to improve Y.";
    /// if current is mastered → advance to next with "You're ready for X." Only considers training activities; returns nil if 2-Minute Test not done.
    static func recommendedNextActivity(progressStore: ProgressStore, playerId: UUID?) -> SkillProgressionRecommendation? {
        guard progressStore.last(.twoMinuteTest, playerId: playerId) != nil else { return nil }

        if !isMastered(progressStore: progressStore, activity: .awayFromPressure, playerId: playerId) {
            let improve = failingCriterion(progressStore: progressStore, activity: .awayFromPressure, playerId: playerId)
            return SkillProgressionRecommendation(
                recommendedActivity: .awayFromPressure,
                message: "Keep training \(activityTitle(.awayFromPressure)) to improve \(improve).",
                isRepeat: true
            )
        }
        if !isMastered(progressStore: progressStore, activity: .dribbleOrPass, playerId: playerId) {
            return SkillProgressionRecommendation(
                recommendedActivity: .dribbleOrPass,
                message: "You're ready for \(activityTitle(.dribbleOrPass)).",
                isRepeat: false
            )
        }
        if !isMastered(progressStore: progressStore, activity: .oneTouchPassing, playerId: playerId) {
            return SkillProgressionRecommendation(
                recommendedActivity: .oneTouchPassing,
                message: "You're ready for \(activityTitle(.oneTouchPassing)).",
                isRepeat: false
            )
        }
        return SkillProgressionRecommendation(
            recommendedActivity: .oneTouchPassing,
            message: "You're ready for \(activityTitle(.oneTouchPassing)). Keep the standard.",
            isRepeat: false
        )
    }
}
