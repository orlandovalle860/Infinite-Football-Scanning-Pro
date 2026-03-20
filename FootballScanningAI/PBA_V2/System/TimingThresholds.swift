//
//  TimingThresholds.swift
//  FootballScanningAI
//
//  PBA V2 — Configurable Fast / Medium / Slow thresholds for decision timing.
//

import Foundation

/// Central thresholds for classifying decision speed. Adjust here to recalibrate without changing timing logic.
struct TimingThresholds {
    /// Decision Before Contact / Pre-Receive: rep counts when decisionTime < this AND firstTouch == correct. Example: 0.8s.
    static let earlyDecisionThresholdForPreReceive: Double = 0.8

    /// Playing Away From Pressure: Fast < this (seconds).
    static let pressureFast: Double = 0.9
    /// Playing Away From Pressure: Medium <= this; Slow > this.
    static let pressureMediumUpper: Double = 1.4

    /// Dribble or Pass: Fast < this (seconds).
    static let dribblePassFast: Double = 1.1
    /// Dribble or Pass: Medium <= this; Slow > this.
    static let dribblePassMediumUpper: Double = 1.5
    /// One-Touch Passing: Fast < this (seconds).
    static let oneTouchFast: Double = 1.2
    /// One-Touch Passing: Medium <= this; Slow > this.
    static let oneTouchMediumUpper: Double = 1.6

    /// Classify decision time for Playing Away From Pressure.
    /// Fast < 0.9s, Medium 0.9–1.4s, Slow > 1.4s.
    static func pressureSpeedBucket(for time: Double) -> SpeedBucket {
        if time < pressureFast { return .fast }
        if time <= pressureMediumUpper { return .medium }
        return .slow
    }

    /// Classify decision time for Dribble or Pass.
    /// Fast < 1.1s, Medium 1.1–1.5s, Slow > 1.5s.
    static func dribblePassDecisionSpeed(for time: Double) -> DecisionSpeed {
        if time < dribblePassFast { return .fast }
        if time <= dribblePassMediumUpper { return .medium }
        return .slow
    }

    /// Classify decision time for One-Touch Passing.
    /// Fast < 1.2s, Medium 1.2–1.6s, Slow > 1.6s.
    static func oneTouchDecisionSpeed(for time: Double) -> DecisionSpeed {
        if time < oneTouchFast { return .fast }
        if time <= oneTouchMediumUpper { return .medium }
        return .slow
    }

    /// 2-Minute Test: Fast < 1.5s, Medium < 3.0s, Slow >= 3.0s.
    static let twoMinuteFast: Double = 1.5
    static let twoMinuteMediumUpper: Double = 3.0

    /// Classify decision time into fast/medium/slow by activity. Used for session_summary and consistency with UI.
    static func speedBucket(for time: Double, activity: ActivityKind) -> SpeedBucket {
        switch activity {
        case .twoMinuteTest:
            if time < twoMinuteFast { return .fast }
            if time < twoMinuteMediumUpper { return .medium }
            return .slow
        case .awayFromPressure:
            return pressureSpeedBucket(for: time)
        case .dribbleOrPass:
            let ds = dribblePassDecisionSpeed(for: time)
            switch ds {
            case .fast: return .fast
            case .medium: return .medium
            case .slow: return .slow
            }
        case .oneTouchPassing:
            let ds = oneTouchDecisionSpeed(for: time)
            switch ds {
            case .fast: return .fast
            case .medium: return .medium
            case .slow: return .slow
            }
        }
    }
}
