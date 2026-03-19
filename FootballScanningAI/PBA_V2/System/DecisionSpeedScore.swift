//
//  DecisionSpeedScore.swift
//  FootballScanningAI
//
//  PBA V2 — Session metric combining correctness and reaction speed.
//  Normalized curve for youth soccer: 400 ms = elite, 800 ms = average, 1200 ms = slow.
//  speed_weight = clamp((1200 - reaction_time_ms) / 800, 0, 1)
//  decision_score = correct ? speed_weight : 0
//  session_score = average(decision_score) * 100
//
//  Score is 0 when: (1) every rep wrong, or (2) every rep reaction time >= 1200 ms.
//

import Foundation

enum DecisionSpeedScore {
    /// Compute session score (0–100) from rep-level reaction times (ms) and correctness.
    /// Uses youth-focused curve: 400 ms → 1.0, 800 ms → 0.5, 1200 ms → 0. Returns nil when no reps.
    static func sessionScore(reactionTimesMs: [Int], correct: [Bool]) -> Int? {
        let n = min(reactionTimesMs.count, correct.count)
        guard n > 0 else { return nil }
        var sum: Double = 0
        for i in 0..<n {
            let raw = Double(1200 - reactionTimesMs[i]) / 800.0
            let speedWeight = min(1.0, max(0.0, raw))
            let decisionScore = correct[i] ? speedWeight : 0.0
            sum += decisionScore
        }
        let avg = sum / Double(n)
        return Int(round(avg * 100))
    }
}
