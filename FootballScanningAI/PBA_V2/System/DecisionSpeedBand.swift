//
//  DecisionSpeedBand.swift
//  FootballScanningAI
//
//  PBA V2 — Performance bands for decision window (seconds before expected arrival).
//

import SwiftUI

/// Performance band for average decision window in seconds. Higher is better.
enum DecisionSpeedBand {
    case elite
    case advanced
    case competent
    case late
    case reactive

    var label: String {
        switch self {
        case .elite: return "Elite"
        case .advanced: return "Advanced"
        case .competent: return "Competent"
        case .late: return "Late"
        case .reactive: return "Too Late"
        }
    }

    var color: Color {
        switch self {
        case .elite: return .green
        case .advanced: return .blue
        case .competent: return .yellow
        case .late: return .orange
        case .reactive: return .red
        }
    }

    var explanation: String {
        switch self {
        case .elite: return "Consistently deciding well before expected arrival."
        case .advanced: return "Usually deciding before expected arrival."
        case .competent: return "Decision lands around ball arrival."
        case .late: return "Decision is often just after arrival."
        case .reactive: return "Decision usually comes too late after arrival."
        }
    }

    /// Base classification from decision window only (balanced profile).
    static func band(forDecisionWindow windowSeconds: Double?) -> DecisionSpeedBand? {
        guard let w = windowSeconds else { return nil }
        if w >= 0.25 { return .elite }
        if w >= 0.10 { return .advanced }
        if w >= 0.00 { return .competent }
        if w >= -0.10 { return .late }
        return .reactive
    }

    /// Activity-tuned classification with correctness gates where needed.
    static func band(
        forDecisionWindow windowSeconds: Double?,
        activity: ActivityKind,
        accuracyPercent: Double?
    ) -> DecisionSpeedBand? {
        guard let w = windowSeconds else { return nil }

        let thresholds: (elite: Double, advanced: Double, competent: Double, late: Double)
        switch activity {
        case .awayFromPressure:
            // AFP: slightly more forgiving timing; correctness primary.
            thresholds = (0.18, 0.06, -0.03, -0.12)
        case .dribbleOrPass:
            // DOP: balanced, slightly stricter than AFP.
            thresholds = (0.22, 0.08, -0.02, -0.12)
        case .oneTouchPassing:
            // OTP: timing-primary.
            thresholds = (0.22, 0.10, 0.00, -0.08)
        case .twoMinuteTest:
            // 2-min baseline: balanced.
            thresholds = (0.20, 0.08, -0.02, -0.10)
        }

        var band: DecisionSpeedBand
        if w >= thresholds.elite { band = .elite }
        else if w >= thresholds.advanced { band = .advanced }
        else if w >= thresholds.competent { band = .competent }
        else if w >= thresholds.late { band = .late }
        else { band = .reactive }

        guard let acc = accuracyPercent else { return band }

        // Correctness gates: AFP + DOP (and 2-min) should not hit high tiers on timing alone.
        switch activity {
        case .awayFromPressure:
            if band == .elite && acc < 88 { band = .advanced }
            if band == .advanced && acc < 78 { band = .competent }
            // Below 65%: hard cap at Competent.
            if acc < 65 && (band == .elite || band == .advanced) { band = .competent }
        case .dribbleOrPass:
            if band == .elite && acc < 85 { band = .advanced }
            if band == .advanced && acc < 75 { band = .competent }
            // Below 60%: hard cap at Competent.
            if acc < 60 && (band == .elite || band == .advanced) { band = .competent }
        case .twoMinuteTest:
            if band == .elite && acc < 85 { band = .advanced }
            if band == .advanced && acc < 75 { band = .competent }
        case .oneTouchPassing:
            // OTP timing is primary; keep only a soft floor.
            if band == .elite && acc < 75 { band = .advanced }
            if band == .advanced && acc < 60 { band = .competent }
        }
        return band
    }

    static func band(forSession session: SessionResult) -> DecisionSpeedBand? {
        let acc = session.totalReps > 0 ? (Double(session.correctCount) / Double(session.totalReps) * 100.0) : nil
        return band(
            forDecisionWindow: session.avgDecisionWindowSeconds,
            activity: session.activityType,
            accuracyPercent: acc
        )
    }

    /// Which `DecisionSpeedScore` curve the activity uses (must match stored session score).
    enum DecisionSpeedScoreCurve: Sendable {
        /// `(1200 - rt_ms) / 800` — 2-Minute Test, Away From Pressure.
        case standard
        /// `(1800 - rt_ms) / 1000` — Dribble or Pass.
        case dribbleOrPass
        /// `(1600 - rt_ms) / 1200` — One-Touch Passing.
        case oneTouch

        init(activityKind: ActivityKind) {
            switch activityKind {
            case .twoMinuteTest, .awayFromPressure:
                self = .standard
            case .dribbleOrPass:
                self = .dribbleOrPass
            case .oneTouchPassing:
                self = .oneTouch
            }
        }

        /// Session score (0–100) for a hypothetical all-correct rep at `ms`, same formula as `DecisionSpeedScore`.
        func uniformCorrectScoreAtMs(_ ms: Int) -> Int {
            switch self {
            case .standard:
                let raw = Double(1200 - ms) / 800.0
                return Int(round(min(1.0, max(0.0, raw)) * 100))
            case .dribbleOrPass:
                let raw = Double(1800 - ms) / 1000.0
                return Int(round(min(1.0, max(0.0, raw)) * 100))
            case .oneTouch:
                let raw = Double(1600 - ms) / 1200.0
                return Int(round(min(1.0, max(0.0, raw)) * 100))
            }
        }

        /// Band from 0–100 decision speed score (legacy/raw-speed classification for score-only surfaces).
        func band(forScore score: Int) -> DecisionSpeedBand {
            let eliteMin = uniformCorrectScoreAtMs(699)
            let advancedMin = uniformCorrectScoreAtMs(900)
            let competentMin = uniformCorrectScoreAtMs(1200)
            if score >= eliteMin { return .elite }
            if score >= advancedMin { return .advanced }
            if competentMin > 0 {
                if score >= competentMin { return .competent }
            } else {
                if score >= 1 { return .competent }
            }
            return .reactive
        }
    }

    /// Prefer this when showing **Decision Speed Score** so labels match the same metric as stored session scores.
    static func band(forScore score: Int?, curve: DecisionSpeedScoreCurve) -> DecisionSpeedBand? {
        guard let score else { return nil }
        return curve.band(forScore: score)
    }
}

// MARK: - First Touch Commitment (percentage) — legacy metric name; user copy moves to "decision–action" where shown.

/// Performance band for commitment %: (reps where optional early action matched intended direction ÷ total reps) × 100. Higher is better. Fields still `firstTouch*` in `SessionResult`.
enum FirstTouchCommitmentBand {
    case elite      // > 90%
    case advanced   // 75 – 90%
    case developing // 60 – 75%
    case beginner   // < 60%

    var label: String {
        switch self {
        case .elite: return "Elite"
        case .advanced: return "Advanced"
        case .developing: return "Developing"
        case .beginner: return "Beginner"
        }
    }

    var color: Color {
        switch self {
        case .elite: return .green
        case .advanced: return .blue
        case .developing: return .orange
        case .beginner: return .red
        }
    }

    /// Returns the band for the given percentage (0–100), or nil if no value.
    static func band(forPercent percent: Double?) -> FirstTouchCommitmentBand? {
        guard let p = percent else { return nil }
        if p > 90 { return .elite }
        if p >= 75 { return .advanced }
        if p >= 60 { return .developing }
        return .beginner
    }
}
