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

    /// Loop scaling for guided curriculum (v1 supports loops 1...3).
    /// Loop 1 = default, loop 2/3 = faster tempo + shorter windows.
    static func defaultConfig(for difficulty: TestDifficulty, loopLevel: Int) -> OneTouchPassingConfig {
        let base = defaultConfig(for: difficulty)
        switch max(1, min(3, loopLevel)) {
        case 1:
            return base
        case 2:
            return OneTouchPassingConfig(
                difficulty: difficulty,
                checkDelayMin: max(1.8, base.checkDelayMin * 0.9),
                checkDelayMax: max(2.6, base.checkDelayMax * 0.9),
                revealStyle: base.revealStyle,
                revealSpacingSeconds: max(0.08, base.revealSpacingSeconds * 0.9),
                cueVisibleSeconds: max(0.40, base.cueVisibleSeconds * 0.9)
            )
        default:
            let advancedStyle: OneTouchRevealStyle
            switch base.revealStyle {
            case .simultaneous: advancedStyle = .twoStage
            case .twoStage: advancedStyle = .sequential
            case .sequential: advancedStyle = .sequential
            }
            return OneTouchPassingConfig(
                difficulty: difficulty,
                checkDelayMin: max(1.6, base.checkDelayMin * 0.8),
                checkDelayMax: max(2.2, base.checkDelayMax * 0.8),
                revealStyle: advancedStyle,
                revealSpacingSeconds: max(0.07, base.revealSpacingSeconds * 0.8),
                cueVisibleSeconds: max(0.35, base.cueVisibleSeconds * 0.8)
            )
        }
    }

    /// Random delay for this rep within the difficulty range.
    func randomCheckDelay() -> Double {
        Double.random(in: checkDelayMin...checkDelayMax)
    }
}
