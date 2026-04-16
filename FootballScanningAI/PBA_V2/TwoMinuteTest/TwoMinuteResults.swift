//
//  TwoMinuteResults.swift
//  FootballScanningAI
//
//  PBA V2 — Player type, test result model, bias, coach insight, recommended next (unique feedback per result).
//

import Foundation

// MARK: - Player Type (from 2-min test)

enum PlayerType: String, Codable {
    case reactor
    case scanner
    case anticipator
    case playmaker

    var title: String {
        switch self {
        case .reactor: return "Reactor"
        case .scanner: return "Scanner"
        case .anticipator: return "Anticipator"
        case .playmaker: return "Playmaker"
        }
    }

    var tagline: String {
        switch self {
        case .reactor: return "Decides after expected arrival."
        case .scanner: return "Sees pressure, commits late."
        case .anticipator: return "Reads pressure early."
        case .playmaker: return "Decides early and plays fast."
        }
    }
}

// MARK: - Gate user-facing name

extension Gate {
    var userFacingName: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

// MARK: - Two-Minute Test Result (aggregate from reps)

struct TwoMinuteTestResult: Identifiable, Hashable {
    let id = UUID()
    let correctCount: Int
    let totalReps: Int
    let fastCount: Int
    let mediumCount: Int
    let slowCount: Int
    let directionCounts: [Gate: Int]
    let biasDirection: Gate?
    let avgDecisionTime: Double?
    let difficulty: TestDifficulty
    /// Forward Intent: reps where ball was up and player chose correctly.
    let forwardChoiceCount: Int
    /// Forward Intent: reps where a forward (up) option was available.
    let forwardOpportunityCount: Int

    init(correctCount: Int, totalReps: Int, fastCount: Int, mediumCount: Int, slowCount: Int, directionCounts: [Gate: Int], biasDirection: Gate?, avgDecisionTime: Double?, difficulty: TestDifficulty, forwardChoiceCount: Int = 0, forwardOpportunityCount: Int = 0) {
        self.correctCount = correctCount
        self.totalReps = totalReps
        self.fastCount = fastCount
        self.mediumCount = mediumCount
        self.slowCount = slowCount
        self.directionCounts = directionCounts
        self.biasDirection = biasDirection
        self.avgDecisionTime = avgDecisionTime
        self.difficulty = difficulty
        self.forwardChoiceCount = forwardChoiceCount
        self.forwardOpportunityCount = forwardOpportunityCount
    }

    /// Build from rep logs (e.g. 10 reps).
    static func from(logs: [RepLog], difficulty: TestDifficulty) -> TwoMinuteTestResult {
        let correctCount = logs.filter(\.correct).count
        let totalReps = logs.count
        var fast = 0, medium = 0, slow = 0
        var directionCounts: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        var totalTime: Double = 0
        var timeCount = 0
        let forwardOpportunityCount = logs.filter { $0.ballGate == .up }.count
        let forwardChoiceCount = logs.filter { $0.ballGate == .up && $0.correct }.count
        let windows = logs.compactMap { $0.decisionWindowSeconds(activity: .twoMinuteTest, difficulty: difficulty) }
        let accuracy = totalReps > 0 ? Double(correctCount) / Double(totalReps) : 0
        let adaptiveScore = DecisionTimingModel.decisionScore(accuracy: accuracy, windows: windows, activity: .twoMinuteTest)

        for log in logs {
            if let window = log.decisionWindowSeconds(activity: .twoMinuteTest, difficulty: difficulty) {
                switch DecisionTimingModel.speedBucket(forDecisionWindow: window, activity: .twoMinuteTest, score: adaptiveScore) {
                case .fast: fast += 1
                case .medium: medium += 1
                case .slow: slow += 1
                }
            }
            directionCounts[log.exitedGate, default: 0] += 1
            if let window = log.decisionWindowSeconds(activity: .twoMinuteTest, difficulty: difficulty) {
                totalTime += window
                timeCount += 1
            }
        }

        let biasDirection = TwoMinuteBias.computeBias(directionCounts: directionCounts, total: totalReps)
        let avgDecisionTime = timeCount > 0 ? totalTime / Double(timeCount) : nil

        return TwoMinuteTestResult(
            correctCount: correctCount,
            totalReps: totalReps,
            fastCount: fast,
            mediumCount: medium,
            slowCount: slow,
            directionCounts: directionCounts,
            biasDirection: biasDirection,
            avgDecisionTime: avgDecisionTime,
            difficulty: difficulty,
            forwardChoiceCount: forwardChoiceCount,
            forwardOpportunityCount: forwardOpportunityCount
        )
    }
}

/// Bundles result and rep logs for presentation (e.g. fullScreenCover) so decisions can be saved when session is saved.
struct TwoMinuteResultItem: Identifiable, Equatable {
    let result: TwoMinuteTestResult
    let logs: [RepLog]
    var id: UUID { result.id }

    static func == (lhs: TwoMinuteResultItem, rhs: TwoMinuteResultItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Player Type Determination

enum TwoMinutePlayerType {
    /// Pure function: determine type from test metrics.
    static func determinePlayerType(correct: Int, total: Int, fast: Int, medium: Int, slow: Int) -> PlayerType {
        guard total > 0 else { return .reactor }
        if correct >= max(10, Int(Double(total) * 0.9)) && fast >= 6 && slow <= 1 {
            return .playmaker
        }
        if correct >= Int(Double(total) * 0.85) && fast >= medium {
            return .anticipator
        }
        if correct >= Int(Double(total) * 0.70) {
            return .scanner
        }
        return .reactor
    }
}

// MARK: - Bias Detection

enum TwoMinuteBias {
    /// Bias if any direction >= 60% of choices (e.g. 6/10).
    static func computeBias(directionCounts: [Gate: Int], total: Int) -> Gate? {
        let threshold = max(6, Int(ceil(Double(total) * 0.6)))
        for gate in Gate.allCases {
            let count = directionCounts[gate] ?? 0
            if count >= threshold { return gate }
        }
        return nil
    }
}

// MARK: - Coach Insight (2 sentences max)

enum TwoMinuteCoachInsight {
    static func coachInsight(type: PlayerType, correct: Int, total: Int, fast: Int, medium: Int, slow: Int, bias: Gate?) -> String {
        var base: String
        switch type {
        case .playmaker:
            base = "You're deciding early and playing fast. Keep it simple and repeat the same quality reps."
        case .anticipator:
            base = "Strong awareness. You're reading pressure early—keep committing sooner so your first action matches your plan."
        case .scanner:
            base = "Good scanning. Next step is deciding earlier before expected arrival so your execution matches what you intended."
        case .reactor:
            base = "You're reacting after expected arrival. Slow your feet, scan both shoulders earlier, and commit to a first decision before receiving."
        }

        if let bias = bias {
            let dir = bias.userFacingName
            base += " You favor the \(dir) side—challenge yourself to scan both shoulders and use the whole field."
        }
        return base
    }
}

// MARK: - Recommended Next + Focus

enum TwoMinuteRecommendedNext {
    static func recommendedNext(for type: PlayerType, slow: Int, correct: Int, total: Int, bias: Gate?) -> (activity: ActivityKind, focus: String) {
        var activity: ActivityKind = .awayFromPressure
        var focus = "decide earlier before expected arrival"

        if type == .playmaker || type == .anticipator {
            activity = .dribbleOrPass
            focus = "scan early, then choose dribble vs pass"
        }
        if bias != nil {
            activity = .awayFromPressure
            focus = "scan both shoulders and use the whole field"
        }
        if total > 0 && correct <= Int(Double(total) * 0.6) {
            activity = .awayFromPressure
            focus = "find the safe option away from pressure"
        }
        return (activity, focus)
    }
}
