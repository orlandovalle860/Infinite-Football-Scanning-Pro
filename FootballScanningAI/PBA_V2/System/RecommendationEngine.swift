//
//  RecommendationEngine.swift
//  FootballScanningAI
//
//  PBA V2 — Recommended Next for Train Now; priority rules + coach note.
//

import Foundation

struct Recommendation {
    let headline: String
    let rationale: String
    let nextActivity: ActivityKind
    /// Optional coach note for Start Page card.
    var coachNote: String? { rationale }
}

enum RecommendationEngine {
    /// Recommended next activity and copy for Start Page / Curriculum. Uses progressStore and playerId.
    static func recommendation(progressStore: ProgressStore, playerId: UUID?) -> Recommendation {
        // 1) Never completed 2-Minute Test → recommend test
        if progressStore.last(.twoMinuteTest, playerId: playerId) == nil {
            return Recommendation(
                headline: "Recommended First Session",
                rationale: "Train your first touch under pressure.",
                nextActivity: .twoMinuteTest
            )
        }

        let trainingOrder: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        let currentActivity: ActivityKind? = trainingOrder.first { activity in
            progressStore.isUnlocked(activity: activity, playerId: playerId) && !progressStore.isReady(activity: activity, playerId: playerId)
        } ?? (progressStore.isReady(activity: .oneTouchPassing, playerId: playerId) ? .oneTouchPassing : trainingOrder.last)

        guard let current = currentActivity else {
            return Recommendation(headline: "Good. Keep the standard.", rationale: "Train One-Touch Passing.", nextActivity: .oneTouchPassing)
        }

        let lastBlock = progressStore.last(current, playerId: playerId)
        let last2 = progressStore.lastN(current, n: 2, playerId: playerId)

        // 2) Timing slow in last 2 blocks of current → recommend Activity 1 (early decisions)
        if last2.count >= 2, last2.allSatisfy({ $0.speedBucket == .slow }) {
            return Recommendation(
                headline: "Correct decisions. Now make them earlier.",
                rationale: "Train escaping pressure so you decide before expected arrival.",
                nextActivity: .awayFromPressure
            )
        }

        // 3) Accuracy low (<=7/12) in last block → recommend same activity
        if let last = lastBlock, last.correct <= 7 {
            return Recommendation(
                headline: "You're reacting late. Scan sooner.",
                rationale: "Try another block of the same activity.",
                nextActivity: current
            )
        }

        // 4) Bias in One-Touch last block (>=50% one direction) → recommend One-Touch again
        if current == .oneTouchPassing, let last = lastBlock, let bias = last.bias, bias != "None", bias != "Balanced" {
            return Recommendation(
                headline: "You're favoring one side. Use the whole field.",
                rationale: "Train One-Touch Passing again.",
                nextActivity: .oneTouchPassing
            )
        }

        // 5) Curriculum progression: recommend next activity to work on
        if !progressStore.isReady(activity: .awayFromPressure, playerId: playerId) {
            return Recommendation(headline: "Decide away from pressure.", rationale: "Read the red cue and commit opposite on the first decision.", nextActivity: .awayFromPressure)
        }
        if !progressStore.isReady(activity: .dribbleOrPass, playerId: playerId) {
            return Recommendation(headline: "Choose action under pressure.", rationale: "Green = pass, Clear = dribble.", nextActivity: .dribbleOrPass)
        }
        return Recommendation(headline: "Decide before expected arrival.", rationale: "Pass to any green.", nextActivity: .oneTouchPassing)
    }

    /// Activity display name for UI.
    static func activityTitle(_ activity: ActivityKind) -> String {
        activity.displayName
    }

    /// Stage label for curriculum. Nil for 2-Minute Test.
    static func stageLabel(for activity: ActivityKind) -> String? {
        switch activity {
        case .twoMinuteTest: return nil
        case .awayFromPressure: return "Stage 1: Playing Away From Pressure"
        case .dribbleOrPass: return "Stage 2: Dribble or Pass"
        case .oneTouchPassing: return "Stage 3: One-Touch Passing"
        }
    }

    /// One-line description (subtitle) for each activity.
    static func activityDescription(_ activity: ActivityKind) -> String {
        switch activity {
        case .twoMinuteTest: return "Train first-touch decisions under pressure."
        case .awayFromPressure: return "Decide opposite the red on your first action."
        case .dribbleOrPass: return "Choose the correct action."
        case .oneTouchPassing: return "Decide before expected arrival."
        }
    }
}
