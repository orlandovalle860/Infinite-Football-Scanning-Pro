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
    /// How gates are revealed.
    let revealStyle: DribbleOrPassRevealStyle
    /// For simultaneous/twoStage: kept for consistency. For sequential: time between reveals.
    let revealSpacingSeconds: Double
    /// How long gates stay visible after reveal (seconds).
    let cueVisibleSeconds: Double
    /// Curriculum loop (1...3); for logging only — does **not** scale scan→beep delay.
    let curriculumLoopLevel: Int

    /// Presets only; no customization. When difficulty changes, use this.
    static func defaultConfig(for difficulty: TestDifficulty) -> DribbleOrPassConfig {
        defaultConfig(for: difficulty, loopLevel: 1)
    }

    /// Loop scaling applies to reveal style / cue duration / spacing — **not** scan→beep timing.
    static func defaultConfig(for difficulty: TestDifficulty, loopLevel: Int) -> DribbleOrPassConfig {
        let base: DribbleOrPassConfig
        switch difficulty {
        case .beginner:
            base = DribbleOrPassConfig(
                difficulty: difficulty,
                revealStyle: .simultaneous,
                revealSpacingSeconds: 0.30,
                cueVisibleSeconds: 1.0,
                curriculumLoopLevel: 1
            )
        case .standard:
            base = DribbleOrPassConfig(
                difficulty: difficulty,
                revealStyle: .twoStage,
                revealSpacingSeconds: 0.20,
                cueVisibleSeconds: 0.75,
                curriculumLoopLevel: 1
            )
        case .advanced:
            base = DribbleOrPassConfig(
                difficulty: difficulty,
                revealStyle: .sequential,
                revealSpacingSeconds: 0.12,
                cueVisibleSeconds: 0.5,
                curriculumLoopLevel: 1
            )
        }
        let level = max(1, min(3, loopLevel))
        switch level {
        case 1:
            return DribbleOrPassConfig(
                difficulty: difficulty,
                revealStyle: base.revealStyle,
                revealSpacingSeconds: base.revealSpacingSeconds,
                cueVisibleSeconds: base.cueVisibleSeconds,
                curriculumLoopLevel: level
            )
        case 2:
            return DribbleOrPassConfig(
                difficulty: difficulty,
                revealStyle: base.revealStyle,
                revealSpacingSeconds: max(0.08, base.revealSpacingSeconds * 0.9),
                cueVisibleSeconds: max(0.40, base.cueVisibleSeconds * 0.9),
                curriculumLoopLevel: level
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
                revealStyle: advancedStyle,
                revealSpacingSeconds: max(0.07, base.revealSpacingSeconds * 0.8),
                cueVisibleSeconds: max(0.35, base.cueVisibleSeconds * 0.8),
                curriculumLoopLevel: level
            )
        }
    }

    /// Optional level-based multipliers (`cueDuration` scales cue visibility and reveal spacing).
    static func defaultConfig(for difficulty: TestDifficulty, loopLevel: Int, levelModifiers: DifficultySettings?) -> DribbleOrPassConfig {
        let base = defaultConfig(for: difficulty, loopLevel: loopLevel)
        guard let m = levelModifiers else { return base }
        return DribbleOrPassConfig(
            difficulty: base.difficulty,
            revealStyle: base.revealStyle,
            revealSpacingSeconds: max(0.06, base.revealSpacingSeconds * m.cueDuration),
            cueVisibleSeconds: max(0.3, base.cueVisibleSeconds * m.cueDuration),
            curriculumLoopLevel: base.curriculumLoopLevel
        )
    }
}
