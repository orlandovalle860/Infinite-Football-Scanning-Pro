//
//  OneTouchPassingModels.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: One-Touch Passing. Multi-correct (any green), rep/block results.
//

import Foundation

/// One rep: which directions are green (available) vs red (covered). Player passes to any green.
struct OneTouchRepPlan {
    let repIndex: Int
    let greenDirections: Set<Gate>
    let redDirections: Set<Gate>

    init(repIndex: Int, greenDirections: Set<Gate>) {
        self.repIndex = repIndex
        self.greenDirections = greenDirections
        self.redDirections = Set(Gate.allCases).subtracting(greenDirections)
    }

    func isGreen(_ gate: Gate) -> Bool { greenDirections.contains(gate) }
}

/// Result of one rep. Uses DecisionSpeed from DribbleOrPass (same thresholds: fast <1.2, medium 1.2–2.0, slow >2.0).
struct OneTouchRepResult {
    let repIndex: Int
    let correct: Bool
    let chosenGate: Gate
    let decisionTime: Double
    let decisionSpeed: DecisionSpeed
}

/// Result of a full 12-rep block.
struct OneTouchBlockResult {
    let correctCount: Int
    let fastCount: Int
    let mediumCount: Int
    let slowCount: Int
    let averageDecisionTime: Double
    let directionCounts: [Gate: Int]
    /// Standard deviation of decision times across reps. Nil if < 2 reps.
    let decisionTimeStdDev: Double?

    static func from(repResults: [OneTouchRepResult]) -> OneTouchBlockResult {
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
        var dirCounts: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for r in repResults {
            dirCounts[r.chosenGate, default: 0] += 1
        }
        let stdDev = SessionResult.standardDeviation(of: times)
        return OneTouchBlockResult(
            correctCount: correctCount,
            fastCount: fast,
            mediumCount: medium,
            slowCount: slow,
            averageDecisionTime: avg,
            directionCounts: dirCounts,
            decisionTimeStdDev: stdDev
        )
    }
}
