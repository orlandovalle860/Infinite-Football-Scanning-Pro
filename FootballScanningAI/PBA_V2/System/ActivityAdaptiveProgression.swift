//
//  ActivityAdaptiveProgression.swift
//  FootballScanningAI
//
//  PBA V2 — Activity-level adaptive progression from recent sessions.
//

import Foundation

enum ActivityAdaptiveLevel: String {
    case foundation = "Foundation"
    case developing = "Developing"
    case strong = "Strong"
    case elite = "Elite"

    var rank: Int {
        switch self {
        case .foundation: return 0
        case .developing: return 1
        case .strong: return 2
        case .elite: return 3
        }
    }

    var mappedBadgeName: String {
        switch self {
        case .foundation: return "Getting Started"
        case .developing: return "Locked In"
        case .strong: return "Early Thinker"
        case .elite: return "Ahead of Play"
        }
    }
}

struct ActivityAdaptivePlan {
    let level: ActivityAdaptiveLevel
    let focusCue: String
    let constraintsSummary: String
    let recommendedDifficulty: TestDifficulty
    let modifiers: DifficultySettings
}

struct ActivityAdaptiveSnapshot {
    let plan: ActivityAdaptivePlan
    let averageLatePercentage: Double
    let averageScore: Double
    let nextLevel: ActivityAdaptiveLevel?
    let progressToNextLevel: Double
    let isNearNextLevel: Bool
}

func makeActivityAdaptivePlan(from allRecentSessions: [SessionResult]) -> ActivityAdaptivePlan {
    makeActivityAdaptiveSnapshot(from: allRecentSessions).plan
}

func makeActivityAdaptiveSnapshot(from allRecentSessions: [SessionResult]) -> ActivityAdaptiveSnapshot {
    let sessionsForEvaluation: [SessionResult]
    if allRecentSessions.count >= 3 {
        sessionsForEvaluation = Array(allRecentSessions.prefix(3))
    } else if let latest = allRecentSessions.first {
        sessionsForEvaluation = [latest]
    } else {
        sessionsForEvaluation = []
    }

    guard !sessionsForEvaluation.isEmpty else {
        let plan = ActivityAdaptivePlan(
            level: .foundation,
            focusCue: "Build early decisions with clean technique.",
            constraintsSummary: "Delayed pressure, extra time, more space",
            recommendedDifficulty: .beginner,
            modifiers: DifficultySettings(cueDuration: 1.15, travelTime: 1.15, thresholdAdjustment: 0.12)
        )
        return ActivityAdaptiveSnapshot(
            plan: plan,
            averageLatePercentage: 0,
            averageScore: 0,
            nextLevel: .developing,
            progressToNextLevel: 0,
            isNearNextLevel: false
        )
    }

    let avgLatePercentage = sessionsForEvaluation.map(latePercentage).reduce(0, +) / Double(sessionsForEvaluation.count)
    let avgScore = sessionsForEvaluation.map(sessionScoreOutOf100).reduce(0, +) / Double(sessionsForEvaluation.count)
    let plan: ActivityAdaptivePlan
    if avgLatePercentage > 0.40 {
        plan = ActivityAdaptivePlan(
            level: .foundation,
            focusCue: "Decide earlier before the ball arrives.",
            constraintsSummary: "Delayed pressure, extra time, more space",
            recommendedDifficulty: .beginner,
            modifiers: DifficultySettings(cueDuration: 1.15, travelTime: 1.15, thresholdAdjustment: 0.12)
        )
    } else if avgLatePercentage < 0.15, avgScore > 85 {
        plan = ActivityAdaptivePlan(
            level: .elite,
            focusCue: "Read pressure instantly and execute one-touch.",
            constraintsSummary: "Blindside pressure, faster tempo, reduced time window",
            recommendedDifficulty: .advanced,
            modifiers: DifficultySettings(cueDuration: 0.82, travelTime: 0.85, thresholdAdjustment: -0.10)
        )
    } else if avgLatePercentage < 0.25, avgScore > 75 {
        plan = ActivityAdaptivePlan(
            level: .strong,
            focusCue: "Handle immediate pressure in tighter space.",
            constraintsSummary: "Immediate pressure, tighter space, one-touch only",
            recommendedDifficulty: .advanced,
            modifiers: DifficultySettings(cueDuration: 0.90, travelTime: 0.92, thresholdAdjustment: -0.05)
        )
    } else {
        plan = ActivityAdaptivePlan(
            level: .developing,
            focusCue: "Commit sooner while staying accurate.",
            constraintsSummary: "Light pressure, normal tempo",
            recommendedDifficulty: .standard,
            modifiers: DifficultySettings(cueDuration: 1.0, travelTime: 1.0, thresholdAdjustment: 0.0)
        )
    }

    let next = nextLevel(after: plan.level)
    let progress = progressToNextLevel(
        currentLevel: plan.level,
        averageLatePercentage: avgLatePercentage,
        averageScore: avgScore
    )
    return ActivityAdaptiveSnapshot(
        plan: plan,
        averageLatePercentage: avgLatePercentage,
        averageScore: avgScore,
        nextLevel: next,
        progressToNextLevel: progress,
        isNearNextLevel: next != nil && progress >= 0.8 && progress < 1.0
    )
}

private func nextLevel(after level: ActivityAdaptiveLevel) -> ActivityAdaptiveLevel? {
    switch level {
    case .foundation: return .developing
    case .developing: return .strong
    case .strong: return .elite
    case .elite: return nil
    }
}

private func progressToNextLevel(currentLevel: ActivityAdaptiveLevel, averageLatePercentage: Double, averageScore: Double) -> Double {
    func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    switch currentLevel {
    case .foundation:
        // Progress toward <= 0.40 down to 0.25 late% band.
        return clamp((0.40 - averageLatePercentage) / 0.15)
    case .developing:
        // Toward strong: late < 0.25 and score > 75.
        let timingProgress = clamp((0.40 - averageLatePercentage) / 0.15)
        let scoreProgress = clamp((averageScore - 70) / 5)
        return (timingProgress + scoreProgress) / 2
    case .strong:
        // Toward elite: late < 0.15 and score > 85.
        let timingProgress = clamp((0.25 - averageLatePercentage) / 0.10)
        let scoreProgress = clamp((averageScore - 75) / 10)
        return (timingProgress + scoreProgress) / 2
    case .elite:
        return 1
    }
}

private func latePercentage(_ session: SessionResult) -> Double {
    let total = session.speedCounts.fast + session.speedCounts.medium + session.speedCounts.slow
    guard total > 0 else { return 0 }
    return Double(session.speedCounts.slow) / Double(total)
}

private func sessionScoreOutOf100(_ session: SessionResult) -> Double {
    if let totalScore = session.decisionTotalScore {
        if totalScore <= 60 {
            return max(0, min(100, (totalScore / 60.0) * 100.0))
        }
        return max(0, min(100, totalScore))
    }
    guard session.totalReps > 0 else { return 0 }
    return max(0, min(100, (Double(session.correctCount) / Double(session.totalReps)) * 100.0))
}
