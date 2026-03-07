//
//  TimingThresholds.swift
//  FootballScanningAI
//
//  PBA V2 — Configurable Fast / Medium / Slow thresholds for decision timing.
//  Playing Away From Pressure and Dribble or Pass use first-touch timing when available.
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
    static let dribblePassFast: Double = 1.0
    /// Dribble or Pass: Medium <= this; Slow > this.
    static let dribblePassMediumUpper: Double = 1.5

    /// Classify decision time for Playing Away From Pressure.
    /// Fast < 0.9s, Medium 0.9–1.4s, Slow > 1.4s.
    static func pressureSpeedBucket(for time: Double) -> SpeedBucket {
        if time < pressureFast { return .fast }
        if time <= pressureMediumUpper { return .medium }
        return .slow
    }

    /// Classify decision time for Dribble or Pass.
    /// Fast < 1.0s, Medium 1.0–1.5s, Slow > 1.5s.
    static func dribblePassDecisionSpeed(for time: Double) -> DecisionSpeed {
        if time < dribblePassFast { return .fast }
        if time <= dribblePassMediumUpper { return .medium }
        return .slow
    }
}
