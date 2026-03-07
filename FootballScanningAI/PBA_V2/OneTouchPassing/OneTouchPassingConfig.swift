//
//  OneTouchPassingConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Difficulty presets only (no sliders). CHECK delay range, reveal style, cue visible.
//

import Foundation

/// How teammate states are revealed: all at once, two then rest, or one-by-one.
enum OneTouchRevealStyle: String, Codable {
    case simultaneous
    case twoStage
    case sequential
}

struct OneTouchPassingConfig {
    let difficulty: TestDifficulty
    /// Random delay (seconds) before CHECK cue; range per difficulty.
    let checkDelayMin: Double
    let checkDelayMax: Double
    let revealStyle: OneTouchRevealStyle
    let revealSpacingSeconds: Double
    let cueVisibleSeconds: Double

    static func defaultConfig(for difficulty: TestDifficulty) -> OneTouchPassingConfig {
        switch difficulty {
        case .beginner:
            return OneTouchPassingConfig(
                difficulty: difficulty,
                checkDelayMin: 6,
                checkDelayMax: 9,
                revealStyle: .simultaneous,
                revealSpacingSeconds: 0.30,
                cueVisibleSeconds: 1.0
            )
        case .standard:
            return OneTouchPassingConfig(
                difficulty: difficulty,
                checkDelayMin: 4,
                checkDelayMax: 7,
                revealStyle: .twoStage,
                revealSpacingSeconds: 0.20,
                cueVisibleSeconds: 0.75
            )
        case .advanced:
            return OneTouchPassingConfig(
                difficulty: difficulty,
                checkDelayMin: 3,
                checkDelayMax: 5,
                revealStyle: .sequential,
                revealSpacingSeconds: 0.12,
                cueVisibleSeconds: 0.5
            )
        }
    }

    /// Random delay for this rep within the difficulty range.
    func randomCheckDelay() -> Double {
        Double.random(in: checkDelayMin...checkDelayMax)
    }
}
