//
//  SessionProgression.swift
//  FootballScanningAI
//
//  PBA V2 — Recent session performance, trends, and coaching insight.
//

import Foundation

// MARK: - Session performance snapshot

struct SessionPerformance: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let activity: TrainingActivityType
    let score: Int
    let accuracy: Double
    let avgDecisionTime: Double
    let avgDecisionWindow: Double
}

extension SessionResult {
    /// Aggregated metrics for progression / trends (derived from stored session).
    var sessionPerformance: SessionPerformance {
        let accuracy = totalReps > 0 ? Double(correctCount) / Double(totalReps) : 0
        let score: Int
        if let s = decisionTotalScore {
            score = max(0, min(100, Int(s.rounded())))
        } else {
            score = estimatedDecisionSpeedScore ?? 0
        }
        return SessionPerformance(
            id: id,
            date: date,
            activity: activityType,
            score: score,
            accuracy: accuracy,
            avgDecisionTime: avgDecisionTime ?? 0,
            avgDecisionWindow: avgDecisionWindowSeconds ?? 0
        )
    }
}

/// Newest sessions by date, limited, then **oldest → newest** in the returned array (for trend comparison).
func getRecentSessions(from results: [SessionResult], limit: Int = 5) -> [SessionPerformance] {
    Array(
        results
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map(\.sessionPerformance)
            .reversed()
    )
}

// MARK: - Trends

enum TrendDirection: Equatable {
    case up
    case down
    case stable
}

func calculateTrend(values: [Double]) -> TrendDirection {
    guard values.count >= 2 else { return .stable }

    let first = values.first!
    let last = values.last!

    if last > first { return .up }
    if last < first { return .down }
    return .stable
}

func generateInsight(
    scoreTrend: TrendDirection,
    windowTrend: TrendDirection,
    accuracyTrend: TrendDirection
) -> String {
    if windowTrend == .up && accuracyTrend == .up {
        return "You are seeing earlier and executing correctly."
    }

    if windowTrend == .up && accuracyTrend == .down {
        return "Speed is improving, but accuracy is dropping."
    }

    if windowTrend == .down {
        return "You are reacting later under pressure."
    }

    return "Your performance is stable. Push for faster decisions."
}

extension TrendDirection {
    var arrowSymbol: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .stable: return "→"
        }
    }
}

// MARK: - Player level (last 5 sessions averaged)

enum PlayerLevel: String {
    case reactive = "Reactive"
    case recognizing = "Recognizing"
    case anticipating = "Anticipating"
    case proactive = "Proactive"
    case elite = "Elite"
}

extension PlayerLevel {
    var progressionSubtitle: String {
        switch self {
        case .reactive:
            return "Build consistency first — scan earlier each session."
        case .recognizing:
            return "You’re reading the game more clearly. Keep stacking good reps."
        case .anticipating:
            return "You are becoming more proactive in your decisions."
        case .proactive:
            return "You’re deciding early and backing it with quality."
        case .elite:
            return "Elite tempo — keep challenging complexity while staying clean."
        }
    }
}

func getAverages(sessions: [SessionPerformance]) -> (window: Double, accuracy: Double) {
    let recent = sessions
        .sorted { $0.date > $1.date }
        .prefix(5)

    let count = Double(recent.count)
    guard count > 0 else { return (0, 0) }

    let avgWindow = recent.map(\.avgDecisionWindow).reduce(0, +) / count
    let avgAccuracy = recent.map(\.accuracy).reduce(0, +) / count
    return (avgWindow, avgAccuracy)
}

func determinePlayerLevel(
    avgWindow: Double,
    avgAccuracy: Double
) -> PlayerLevel {
    if avgWindow > 0.20 && avgAccuracy >= 0.85 {
        return .elite
    }

    if avgWindow > 0.10 && avgAccuracy >= 0.75 {
        return .proactive
    }

    if avgWindow > 0.0 && avgAccuracy >= 0.70 {
        return .anticipating
    }

    if avgAccuracy >= 0.60 {
        return .recognizing
    }

    return .reactive
}

struct PlayerProgression: Equatable {
    let currentLevel: PlayerLevel
    let avgDecisionWindow: Double
    let avgAccuracy: Double
}

func generateProgression(sessions: [SessionPerformance]) -> PlayerProgression {
    let averages = getAverages(sessions: sessions)

    let level = determinePlayerLevel(
        avgWindow: averages.window,
        avgAccuracy: averages.accuracy
    )

    return PlayerProgression(
        currentLevel: level,
        avgDecisionWindow: averages.window,
        avgAccuracy: averages.accuracy
    )
}

// MARK: - Level-based training recommendation

struct LevelRecommendation: Equatable {
    let activity: TrainingActivityType
    let focus: String
}

func getLevelRecommendation(level: PlayerLevel) -> LevelRecommendation {
    switch level {
    case .reactive:
        return LevelRecommendation(
            activity: .awayFromPressure,
            focus: "Take more time and recognize pressure earlier"
        )
    case .recognizing:
        return LevelRecommendation(
            activity: .awayFromPressure,
            focus: "Make earlier decisions more consistently"
        )
    case .anticipating:
        return LevelRecommendation(
            activity: .dribbleOrPass,
            focus: "Stay accurate while increasing speed"
        )
    case .proactive:
        return LevelRecommendation(
            activity: .oneTouchPassing,
            focus: "Execute faster with consistency"
        )
    case .elite:
        return LevelRecommendation(
            activity: .oneTouchPassing,
            focus: "Push speed to the highest level under pressure"
        )
    }
}

struct DifficultySettings: Equatable {
    let cueDuration: Double
    let travelTime: Double
    let thresholdAdjustment: Double
}

func getDifficulty(for level: PlayerLevel) -> DifficultySettings {
    switch level {
    case .reactive:
        return DifficultySettings(cueDuration: 1.2, travelTime: 1.2, thresholdAdjustment: 0.2)
    case .recognizing:
        return DifficultySettings(cueDuration: 1.1, travelTime: 1.1, thresholdAdjustment: 0.1)
    case .anticipating:
        return DifficultySettings(cueDuration: 1.0, travelTime: 1.0, thresholdAdjustment: 0.0)
    case .proactive:
        return DifficultySettings(cueDuration: 0.9, travelTime: 0.9, thresholdAdjustment: -0.05)
    case .elite:
        return DifficultySettings(cueDuration: 0.8, travelTime: 0.8, thresholdAdjustment: -0.1)
    }
}

extension ActivityKind {
    /// Display name for level-based recommendations and summaries.
    var displayName: String {
        switch self {
        case .twoMinuteTest: return "2-Minute Test"
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        }
    }
}

// MARK: - In-session adaptive difficulty

struct AdaptiveState: Equatable {
    var successStreak: Int = 0
    var failureStreak: Int = 0
}

func updateAdaptiveState(state: inout AdaptiveState, wasCorrect: Bool, decisionWindow: Double) {
    let success = wasCorrect && decisionWindow > 0

    if success {
        state.successStreak += 1
        state.failureStreak = 0
    } else {
        state.failureStreak += 1
        state.successStreak = 0
    }
}

func clampAdaptiveDifficulty(_ s: DifficultySettings) -> DifficultySettings {
    DifficultySettings(
        cueDuration: min(1.5, max(0.6, s.cueDuration)),
        travelTime: min(1.5, max(0.7, s.travelTime)),
        thresholdAdjustment: s.thresholdAdjustment
    )
}

/// After streak thresholds, nudges multipliers and resets the streak that fired (gradual, not every rep).
func adjustDifficulty(state: inout AdaptiveState, current: DifficultySettings) -> DifficultySettings {
    var cue = current.cueDuration
    var travel = current.travelTime
    let thr = current.thresholdAdjustment

    if state.successStreak >= 3 {
        cue *= 0.95
        travel *= 0.95
        state.successStreak = 0
    } else if state.failureStreak >= 3 {
        cue *= 1.05
        travel *= 1.05
        state.failureStreak = 0
    }

    return clampAdaptiveDifficulty(DifficultySettings(cueDuration: cue, travelTime: travel, thresholdAdjustment: thr))
}
