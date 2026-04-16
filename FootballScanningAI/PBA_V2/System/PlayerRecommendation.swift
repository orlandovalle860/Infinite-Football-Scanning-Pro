//
//  PlayerRecommendation.swift
//  FootballScanningAI
//
//  PBA V2 — Simple next-step recommendation from session accuracy and decision window.
//

import Foundation

/// Training block target for recommendations (maps to `ActivityKind` cases used in PBA flows).
typealias TrainingActivityType = ActivityKind

enum SessionPerformanceLevel: String, Codable, Equatable {
    case reactive = "Reactive"
    case developing = "Developing"
    case advancing = "Advancing"
    case elite = "Elite"

    var rank: Int {
        switch self {
        case .reactive: return 0
        case .developing: return 1
        case .advancing: return 2
        case .elite: return 3
        }
    }

    var shortFeedback: String {
        switch self {
        case .reactive:
            return "You’re reacting to the ball."
        case .developing:
            return "You’re close."
        case .advancing:
            return "You’re anticipating well."
        case .elite:
            return "You’re ahead of play."
        }
    }

    var nextFocus: String {
        switch self {
        case .reactive:
            return "Focus on deciding earlier. Try to decide before the ball reaches halfway."
        case .developing:
            return "Start committing earlier. Decide before the ball gets to you."
        case .advancing:
            return "Push for more early decisions. Know your decision before the pass is made."
        case .elite:
            return "Maintain early decisions under pressure."
        }
    }

    var tempoGuidance: String {
        switch self {
        case .reactive:
            return "Controlled tempo"
        case .developing:
            return "Introduce Game Speed"
        case .advancing:
            return "Game Speed"
        case .elite:
            return "Faster tempo / constraints"
        }
    }
}

struct PlayerRecommendation: Equatable {
    let level: SessionPerformanceLevel
    let shortFeedback: String
    let nextActivity: TrainingActivityType
    let nextFocusText: String
    let tempoGuidance: String
    let progressionSuggestion: String?
}

func generateRecommendation(
    score: Int,
    accuracy: Double,
    decisionWindow: Double,
    recentScores: [Int] = []
) -> PlayerRecommendation {
    let level = classifyPerformanceLevel(score: score)
    let progressionSuggestion = progressionSuggestionText(level: level, recentScores: recentScores)

    if decisionWindow <= 0 && accuracy >= 0.75 {
        return PlayerRecommendation(
            level: level,
            shortFeedback: level.shortFeedback,
            nextActivity: .awayFromPressure,
            nextFocusText: level.nextFocus,
            tempoGuidance: level.tempoGuidance,
            progressionSuggestion: progressionSuggestion
        )
    }

    if decisionWindow > 0 && accuracy < 0.75 {
        return PlayerRecommendation(
            level: level,
            shortFeedback: level.shortFeedback,
            nextActivity: .dribbleOrPass,
            nextFocusText: level.nextFocus,
            tempoGuidance: level.tempoGuidance,
            progressionSuggestion: progressionSuggestion
        )
    }

    if decisionWindow > 0 && accuracy >= 0.75 {
        return PlayerRecommendation(
            level: level,
            shortFeedback: level.shortFeedback,
            nextActivity: .oneTouchPassing,
            nextFocusText: level.nextFocus,
            tempoGuidance: level.tempoGuidance,
            progressionSuggestion: progressionSuggestion
        )
    }

    return PlayerRecommendation(
        level: level,
        shortFeedback: level.shortFeedback,
        nextActivity: .awayFromPressure,
        nextFocusText: level.nextFocus,
        tempoGuidance: level.tempoGuidance,
        progressionSuggestion: progressionSuggestion
    )
}

private func classifyPerformanceLevel(score: Int) -> SessionPerformanceLevel {
    switch score {
    case ..<60: return .reactive
    case ..<75: return .developing
    case ..<90: return .advancing
    default: return .elite
    }
}

private func progressionSuggestionText(level: SessionPerformanceLevel, recentScores: [Int]) -> String? {
    let recentLevels = recentScores.map(classifyPerformanceLevel(score:))
    let lastThree = Array(recentLevels.suffix(3))
    guard lastThree.count == 3 else { return nil }
    let sustained = lastThree.allSatisfy { $0.rank >= level.rank }
    return sustained ? "You’ve held this level for 3 sessions — suggest moving up." : nil
}
