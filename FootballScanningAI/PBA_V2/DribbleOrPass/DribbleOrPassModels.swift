//
//  DribbleOrPassModels.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Gate content (red/green/empty), decision speed, rep/block results.
//

import Foundation

/// Content of one gate: opponent (red), teammate (green), or open (nothing).
enum DribbleOrPassGateContent: String, Codable, CaseIterable, Hashable {
    case opponent  // RED — avoid
    case teammate  // GREEN — pass
    case open      // CLEAR — dribble
}

/// Decision timing bucket for player feedback.
enum DecisionSpeed: String, Codable, CaseIterable {
    case fast
    case medium
    case slow
}

func classifyDecisionSpeed(_ time: Double) -> DecisionSpeed {
    if time < 1.2 { return .fast }
    if time <= 2.0 { return .medium }
    return .slow
}

/// Decision hierarchy (v1: up=forward, left/right=lateral, down=backward). Green=pass, clear=dribble, red=avoid.
/// Points: forward pass 4, forward dribble 3, lateral pass 2, lateral dribble 1, backward 0.
func dribbleOrPassDecisionPoints(plan: DribbleOrPassRepPlan, chosenGate: Gate) -> Int {
    let content = plan.content(for: chosenGate)
    if content == .opponent { return 0 }
    switch chosenGate {
    case .up:
        return content == .teammate ? 4 : 3  // forward pass = 4, forward dribble = 3
    case .left, .right:
        return content == .teammate ? 2 : 1  // lateral pass = 2, lateral dribble = 1
    case .down:
        return 0  // backward = 0 (pass or dribble)
    }
}

/// Timing bonus: fast +1, medium +0, slow +0.
func dribbleOrPassTimingBonus(_ speed: DecisionSpeed) -> Double {
    switch speed {
    case .fast: return 1.0
    case .medium, .slow: return 0
    }
}

/// Result of one rep. correct = chose expected gate; decisionPoints (0–4) + timingBonus = repScore; max 5.
struct DribbleOrPassRepResult {
    let repIndex: Int
    let correct: Bool
    let decisionTime: Double
    let decisionSpeed: DecisionSpeed
    let expectedGate: Gate
    let chosenGate: Gate
    /// Decision points: forward pass 4, forward dribble 3, lateral pass 2, lateral dribble 1, backward 0.
    let decisionPoints: Int
    /// Timing bonus: fast +1, medium/slow +0.
    let timingBonus: Double
    /// Optional early direction (wire: `firstTouchLogged`); nil if coach skipped. Base `correct` comes from `chosenGate` vs scenario.
    let firstTouchGate: Gate?
    /// decisionPoints + timingBonus. Max 5 per rep.
    var repScore: Double { Double(decisionPoints) + timingBonus }
    /// True when optional early direction matched intended gate; nil when not logged.
    var firstTouchAccurate: Bool? {
        guard let ft = firstTouchGate else { return nil }
        return ft == expectedGate
    }

    init(repIndex: Int, correct: Bool, decisionTime: Double, decisionSpeed: DecisionSpeed, expectedGate: Gate, chosenGate: Gate, decisionPoints: Int, timingBonus: Double, firstTouchGate: Gate? = nil) {
        self.repIndex = repIndex
        self.correct = correct
        self.decisionTime = decisionTime
        self.decisionSpeed = decisionSpeed
        self.expectedGate = expectedGate
        self.chosenGate = chosenGate
        self.decisionPoints = decisionPoints
        self.timingBonus = timingBonus
        self.firstTouchGate = firstTouchGate
    }
}

/// Result of a full 12-rep block. totalScore = sum(repScore); max 12*5 = 60.
struct DribbleOrPassBlockResult {
    let correctCount: Int
    let fastCount: Int
    let mediumCount: Int
    let slowCount: Int
    let averageDecisionTime: Double
    /// Sum of repScore (decision + timing) across all reps. Max 60.
    let totalScore: Double
    /// Standard deviation of decision times across reps. Nil if fewer than 2 reps.
    let decisionTimeStdDev: Double?

    static func from(repResults: [DribbleOrPassRepResult]) -> DribbleOrPassBlockResult {
        let correctCount = repResults.filter(\.correct).count
        var fast = 0, medium = 0, slow = 0
        for r in repResults {
            switch r.decisionSpeed {
            case .fast: fast += 1
            case .medium: medium += 1
            case .slow: slow += 1
            }
        }
        let times = repResults.map(\.decisionTime)
        let avg = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)
        let totalScore = repResults.map(\.repScore).reduce(0, +)
        let stdDev = SessionResult.standardDeviation(of: times)
        return DribbleOrPassBlockResult(
            correctCount: correctCount,
            fastCount: fast,
            mediumCount: medium,
            slowCount: slow,
            averageDecisionTime: avg,
            totalScore: totalScore,
            decisionTimeStdDev: stdDev
        )
    }
}

/// One rep scenario: gate contents and the single correct gate (DOWN is never correct).
struct DribbleOrPassRepPlan {
    let repIndex: Int
    let up: DribbleOrPassGateContent
    let down: DribbleOrPassGateContent
    let left: DribbleOrPassGateContent
    let right: DribbleOrPassGateContent
    let expectedCorrectGate: Gate

    func content(for gate: Gate) -> DribbleOrPassGateContent {
        switch gate {
        case .up: return up
        case .down: return down
        case .left: return left
        case .right: return right
        }
    }
}
