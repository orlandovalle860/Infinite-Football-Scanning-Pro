//
//  DribbleOrPassConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Difficulty presets only (no sliders).
//

import Foundation

/// How gates are revealed: all at once, two then rest, or one-by-one.
enum DribbleOrPassRevealStyle: String, Codable {
    case simultaneous  // all gates at once
    case twoStage      // 2 gates, then remaining after fixed 0.25s
    case sequential    // one-by-one with revealSpacingSeconds between
}

struct DribbleOrPassConfig {
    let difficulty: TestDifficulty
    /// Scan phase duration (seconds) before beep.
    let scanWindowSeconds: Double
    /// How gates are revealed.
    let revealStyle: DribbleOrPassRevealStyle
    /// For simultaneous/twoStage: kept for consistency. For sequential: time between reveals.
    let revealSpacingSeconds: Double
    /// How long gates stay visible after reveal (seconds).
    let cueVisibleSeconds: Double

    /// Presets only; no customization. When difficulty changes, use this.
    static func defaultConfig(for difficulty: TestDifficulty) -> DribbleOrPassConfig {
        switch difficulty {
        case .beginner:
            return DribbleOrPassConfig(
                difficulty: difficulty,
                scanWindowSeconds: 7.5,
                revealStyle: .simultaneous,
                revealSpacingSeconds: 0.30,
                cueVisibleSeconds: 1.0
            )
        case .standard:
            return DribbleOrPassConfig(
                difficulty: difficulty,
                scanWindowSeconds: 5.5,
                revealStyle: .twoStage,
                revealSpacingSeconds: 0.20,
                cueVisibleSeconds: 0.75
            )
        case .advanced:
            return DribbleOrPassConfig(
                difficulty: difficulty,
                scanWindowSeconds: 4.0,
                revealStyle: .sequential,
                revealSpacingSeconds: 0.12,
                cueVisibleSeconds: 0.5
            )
        }
    }
}
