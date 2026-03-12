//
//  DecisionSpeedBand.swift
//  FootballScanningAI
//
//  PBA V2 — Performance bands for decision speed (seconds): Elite, Advanced, Developing, Beginner.
//

import SwiftUI

/// Performance band for average decision time in seconds. Lower is better.
enum DecisionSpeedBand {
    case elite      // < 0.70 s
    case advanced   // 0.70 – 0.90 s
    case developing // 0.90 – 1.20 s
    case beginner   // > 1.20 s

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

    var explanation: String {
        switch self {
        case .elite: return "Deciding before the ball arrives."
        case .advanced: return "Strong timing under pressure."
        case .developing: return "Building consistency; keep scanning early."
        case .beginner: return "Focus on scanning earlier before receiving."
        }
    }

    /// Returns the band for the given average decision time in seconds, or nil if no value.
    static func band(forSeconds seconds: Double?) -> DecisionSpeedBand? {
        guard let s = seconds else { return nil }
        if s < 0.70 { return .elite }
        if s <= 0.90 { return .advanced }
        if s <= 1.20 { return .developing }
        return .beginner
    }
}

// MARK: - First Touch Commitment (percentage)

/// Performance band for first touch commitment %: (first touches matching intended direction ÷ total reps) × 100. Higher is better.
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
