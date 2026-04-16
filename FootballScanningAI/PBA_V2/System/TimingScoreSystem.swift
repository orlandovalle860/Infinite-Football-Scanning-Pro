//
//  TimingScoreSystem.swift
//  FootballScanningAI
//
//  PBA V2 — Per-session timing score and actionable feedback.
//

import Foundation

struct TimingScoreBreakdown {
    let earlyCount: Int
    let onTimeCount: Int
    let lateCount: Int

    let earnedPoints: Int
    let maxPoints: Int
    let scorePercent: Int
    let scoreBand: String

    let averageTimingLabel: String
    let feedback: String
    let progressionHint: String
}

enum TimingScoreSystem {
    /// early=3, on-time=2, late=1. Uses decision offset average for timing label.
    static func makeBreakdown(
        early: Int,
        onTime: Int,
        late: Int,
        averageDecisionOffset: Double
    ) -> TimingScoreBreakdown {
        let totalReps = max(0, early + onTime + late)
        let earnedPoints = (early * 3) + (onTime * 2) + (late * 1)
        let maxPoints = max(1, totalReps * 3)
        let scorePercent = Int(((Double(earnedPoints) / Double(maxPoints)) * 100).rounded())

        let band: String
        switch scorePercent {
        case 90...100: band = "Elite Timing"
        case 75...89: band = "Strong"
        case 60...74: band = "Developing"
        default: band = "Reactive"
        }

        let avgLabel: String
        if averageDecisionOffset >= 0 {
            avgLabel = String(format: "Average Timing: Early by %.2fs", averageDecisionOffset)
        } else {
            avgLabel = String(format: "Average Timing: Late by %.2fs", abs(averageDecisionOffset))
        }

        let feedback: String
        if late > onTime && late > early {
            feedback = "You’re reacting to the ball. Decide earlier."
        } else if onTime > early && onTime > late {
            feedback = "You’re close. Commit earlier."
        } else {
            feedback = "Excellent. You’re ahead of pressure."
        }

        let progressionHint: String
        if early >= onTime && early >= late {
            progressionHint = "Ready for Game Speed tempo"
        } else {
            progressionHint = "Increase early decisions next session"
        }

        return TimingScoreBreakdown(
            earlyCount: early,
            onTimeCount: onTime,
            lateCount: late,
            earnedPoints: earnedPoints,
            maxPoints: maxPoints,
            scorePercent: scorePercent,
            scoreBand: band,
            averageTimingLabel: avgLabel,
            feedback: feedback,
            progressionHint: progressionHint
        )
    }
}

