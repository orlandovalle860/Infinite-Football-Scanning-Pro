//
//  SessionTimingCalibration.swift
//  FootballScanningAI
//
//  PBA V2 — In-session-only nudge to expected pass travel (decision window) when timing is
//  consistently early or late. Capped, streak-gated; no persistence across sessions.
//

import Foundation

/// Stable string id for calibration maps; use ``ActivityKind/sessionActivityActivityId``.
typealias ActivityID = String

enum SessionTimingCalibration {
    /// Total adaptive range ≈ ±12% (within typical 10–15% product ask).
    static let minFactor: Double = 0.88
    static let maxFactor: Double = 1.12
    /// One nudge per streak trigger (~2% of nominal travel).
    static let step: Double = 0.02
    static let streakRequired: Int = 3
    /// Decision window (s before expected arrival): above = early trend, below = late trend.
    static let earlyBand: Double = 0.06
    static let lateBand: Double = -0.06
    /// Reps in this band (inclusive) reset streaks and decay factor toward 1.0.
    static let neutralBandMax: Double = 0.06
    static let neutralDecayStep: Double = 0.01

    static func effectiveTravelTime(baseNominal: Double, factor: Double) -> Double {
        let f = min(max(factor, minFactor), maxFactor)
        let t = baseNominal * f
        return min(2.5, max(0.2, t))
    }
}

/// Session accuracy bands for light copy only (not shown as a “level” label).
enum SessionAccuracyBand: Equatable {
    case struggling
    case developing
    case strong

    /// `accuracy` in 0...1 (correct/total).
    static func fromUnitAccuracy(_ accuracy: Double) -> SessionAccuracyBand {
        let p = accuracy > 1 ? accuracy / 100 : accuracy * 100
        if p < 70 { return .struggling }
        if p < 85 { return .developing }
        return .strong
    }
}
