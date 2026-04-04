//
//  TimingThresholds.swift
//  FootballScanningAI
//
//  PBA V2 — Configurable Fast / Medium / Slow thresholds for decision timing.
//

import Foundation

/// Central thresholds for classifying decision speed. Adjust here to recalibrate without changing timing logic.
/// Hierarchy (tightest → most forgiving): Away From Pressure < Dribble or Pass < One-Touch Passing < 2-Minute Test.
struct TimingThresholds {
    /// Decision Before Contact / Pre-Receive: rep counts when decisionTime < this AND firstTouch == correct. Example: 0.8s.
    static let earlyDecisionThresholdForPreReceive: Double = 0.8

    /// Playing Away From Pressure: Fast < this (seconds).
    static let pressureFast: Double = 0.75
    /// Playing Away From Pressure: Medium through this (seconds); Slow above.
    static let pressureMediumUpper: Double = 1.15

    /// Dribble or Pass: Fast < this (seconds).
    static let dribblePassFast: Double = 0.95
    /// Dribble or Pass: Medium through this (seconds); Slow above.
    static let dribblePassMediumUpper: Double = 1.25
    /// One-Touch Passing: Fast < this (seconds).
    static let oneTouchFast: Double = 1.05
    /// One-Touch Passing: Medium through this (seconds); Slow above.
    static let oneTouchMediumUpper: Double = 1.35

    /// 2-Minute Test: Fast < this (seconds), Medium < medium upper, Slow ≥ medium upper.
    static let twoMinuteFast: Double = 1.25
    static let twoMinuteMediumUpper: Double = 2.5

    /// Classify decision time for Playing Away From Pressure.
    /// Fast < 0.75s, Medium 0.75–1.15s, Slow > 1.15s.
    static func pressureSpeedBucket(for time: Double) -> SpeedBucket {
        let bucket: SpeedBucket
        if time < pressureFast { bucket = .fast }
        else if time <= pressureMediumUpper { bucket = .medium }
        else { bucket = .slow }
        #if DEBUG
        ThresholdApplyDebug.log(
            activity: .awayFromPressure,
            rawDeltaSeconds: time,
            thresholdsDescription: "AFP fast_lt=\(pressureFast) medium_upto=\(pressureMediumUpper)",
            resultingBucket: bucket.rawValue
        )
        #endif
        return bucket
    }

    /// Classify decision time for Dribble or Pass.
    /// Fast < 0.95s, Medium 0.95–1.25s, Slow > 1.25s.
    static func dribblePassDecisionSpeed(for time: Double) -> DecisionSpeed {
        let speed: DecisionSpeed
        if time < dribblePassFast { speed = .fast }
        else if time <= dribblePassMediumUpper { speed = .medium }
        else { speed = .slow }
        #if DEBUG
        ThresholdApplyDebug.log(
            activity: .dribbleOrPass,
            rawDeltaSeconds: time,
            thresholdsDescription: "DOP fast_lt=\(dribblePassFast) medium_upto=\(dribblePassMediumUpper)",
            resultingBucket: speed.rawValue
        )
        #endif
        return speed
    }

    /// Classify decision time for One-Touch Passing.
    /// Fast < 1.05s, Medium 1.05–1.35s, Slow > 1.35s.
    static func oneTouchDecisionSpeed(for time: Double) -> DecisionSpeed {
        let speed: DecisionSpeed
        if time < oneTouchFast { speed = .fast }
        else if time <= oneTouchMediumUpper { speed = .medium }
        else { speed = .slow }
        #if DEBUG
        ThresholdApplyDebug.log(
            activity: .oneTouchPassing,
            rawDeltaSeconds: time,
            thresholdsDescription: "OTP fast_lt=\(oneTouchFast) medium_upto=\(oneTouchMediumUpper)",
            resultingBucket: speed.rawValue
        )
        #endif
        return speed
    }

    /// 2-Minute Test: Fast < 1.25s, Medium 1.25–2.5s, Slow ≥ 2.5s.
    private static func twoMinuteSpeedBucket(for time: Double) -> SpeedBucket {
        let bucket: SpeedBucket
        if time < twoMinuteFast { bucket = .fast }
        else if time < twoMinuteMediumUpper { bucket = .medium }
        else { bucket = .slow }
        #if DEBUG
        ThresholdApplyDebug.log(
            activity: .twoMinuteTest,
            rawDeltaSeconds: time,
            thresholdsDescription: "2MT fast_lt=\(twoMinuteFast) medium_lt=\(twoMinuteMediumUpper)",
            resultingBucket: bucket.rawValue
        )
        #endif
        return bucket
    }

    /// Classify decision time into fast/medium/slow by activity. Used for session_summary and consistency with UI.
    static func speedBucket(for time: Double, activity: ActivityKind) -> SpeedBucket {
        switch activity {
        case .twoMinuteTest:
            return twoMinuteSpeedBucket(for: time)
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

#if DEBUG
private enum ThresholdApplyDebug {
    static func log(activity: ActivityKind, rawDeltaSeconds: Double, thresholdsDescription: String, resultingBucket: String) {
        print("[ThresholdApply-Debug] activity=\(activity.rawValue) rawDeltaSeconds=\(rawDeltaSeconds) thresholds=\(thresholdsDescription) bucket=\(resultingBucket)")
    }
}
#endif
