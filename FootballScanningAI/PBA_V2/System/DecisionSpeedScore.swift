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
        sessionScore(reactionTimesMs: reactionTimesMs, correct: correct, zeroPointMs: 1200, windowMs: 800)
    }

    /// Dribble or Pass score curve (more forgiving for real coach-tapped workflow).
    /// Formula: (1800 - reactionTimeMs) / 1000, clamped to 0...1.
    static func dribbleOrPassSessionScore(reactionTimesMs: [Int], correct: [Bool]) -> Int? {
        sessionScore(reactionTimesMs: reactionTimesMs, correct: correct, zeroPointMs: 1800, windowMs: 1000)
    }

    /// One-Touch Passing score curve (wider window): 400 ms -> 1.0, 1000 ms -> 0.5, 1600 ms -> 0.
    /// Formula: (1600 - reactionTimeMs) / 1200, clamped to 0...1.
    static func oneTouchSessionScore(reactionTimesMs: [Int], correct: [Bool]) -> Int? {
        sessionScore(reactionTimesMs: reactionTimesMs, correct: correct, zeroPointMs: 1600, windowMs: 1200)
    }

    private static func sessionScore(reactionTimesMs: [Int], correct: [Bool], zeroPointMs: Int, windowMs: Int) -> Int? {
        let n = min(reactionTimesMs.count, correct.count)
        guard n > 0 else { return nil }
        var sum: Double = 0
        for i in 0..<n {
            let raw = Double(zeroPointMs - reactionTimesMs[i]) / Double(windowMs)
            let speedWeight = min(1.0, max(0.0, raw))
            let decisionScore = correct[i] ? speedWeight : 0.0
            sum += decisionScore
        }
        let avg = sum / Double(n)
        return Int(round(avg * 100))
    }
}
