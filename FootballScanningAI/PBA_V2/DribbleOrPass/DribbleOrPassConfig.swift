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

    /// Loop scaling for guided curriculum (v1 supports loops 1...3).
    /// Loop 1 = default, loop 2/3 = faster tempo + shorter windows.
    static func defaultConfig(for difficulty: TestDifficulty, loopLevel: Int) -> DribbleOrPassConfig {
        let base = defaultConfig(for: difficulty)
        switch max(1, min(3, loopLevel)) {
        case 1:
            return base
        case 2:
            return DribbleOrPassConfig(
                difficulty: difficulty,
                scanWindowSeconds: max(2.5, base.scanWindowSeconds * 0.9),
                revealStyle: base.revealStyle,
                revealSpacingSeconds: max(0.08, base.revealSpacingSeconds * 0.9),
                cueVisibleSeconds: max(0.40, base.cueVisibleSeconds * 0.9)
            )
        default:
            let advancedStyle: DribbleOrPassRevealStyle
            switch base.revealStyle {
            case .simultaneous: advancedStyle = .twoStage
            case .twoStage: advancedStyle = .sequential
            case .sequential: advancedStyle = .sequential
            }
            return DribbleOrPassConfig(
                difficulty: difficulty,
                scanWindowSeconds: max(2.2, base.scanWindowSeconds * 0.8),
                revealStyle: advancedStyle,
                revealSpacingSeconds: max(0.07, base.revealSpacingSeconds * 0.8),
                cueVisibleSeconds: max(0.35, base.cueVisibleSeconds * 0.8)
            )
        }
    }
}
