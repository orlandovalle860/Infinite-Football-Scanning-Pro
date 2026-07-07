//
//  OneTouchPassingConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Difficulty presets only (no sliders). Scan→beep uses unified timing; reveal style / cue duration vary by difficulty.
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
    let revealStyle: OneTouchRevealStyle
    let revealSpacingSeconds: Double
    let cueVisibleSeconds: Double
    /// Curriculum loop (1...3); for logging only — does **not** scale scan→beep delay.
    let curriculumLoopLevel: Int

    static func defaultConfig(for difficulty: TestDifficulty) -> OneTouchPassingConfig {
        defaultConfig(for: difficulty, loopLevel: 1)
    }

    /// Loop scaling applies to reveal style / cue duration / spacing — **not** scan→beep timing.
    static func defaultConfig(for difficulty: TestDifficulty, loopLevel: Int) -> OneTouchPassingConfig {
        let base: OneTouchPassingConfig
        switch difficulty {
        case .beginner:
            base = OneTouchPassingConfig(
                difficulty: difficulty,
                revealStyle: .simultaneous,
                revealSpacingSeconds: 0.30,
                cueVisibleSeconds: 1.0,
                curriculumLoopLevel: 1
            )
        case .standard:
            base = OneTouchPassingConfig(
                difficulty: difficulty,
                revealStyle: .twoStage,
                revealSpacingSeconds: 0.20,
                cueVisibleSeconds: 0.75,
                curriculumLoopLevel: 1
            )
        case .advanced:
            base = OneTouchPassingConfig(
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
            return OneTouchPassingConfig(
                difficulty: difficulty,
                revealStyle: base.revealStyle,
                revealSpacingSeconds: base.revealSpacingSeconds,
                cueVisibleSeconds: base.cueVisibleSeconds,
                curriculumLoopLevel: level
            )
        case 2:
            return OneTouchPassingConfig(
                difficulty: difficulty,
                revealStyle: base.revealStyle,
                revealSpacingSeconds: max(0.08, base.revealSpacingSeconds * 0.9),
                cueVisibleSeconds: max(0.40, base.cueVisibleSeconds * 0.9),
                curriculumLoopLevel: level
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
                revealStyle: advancedStyle,
                revealSpacingSeconds: max(0.07, base.revealSpacingSeconds * 0.8),
                cueVisibleSeconds: max(0.35, base.cueVisibleSeconds * 0.8),
                curriculumLoopLevel: level
            )
        }
    }

    /// Optional level-based multipliers (`cueDuration` scales cue visibility and reveal spacing).
    static func defaultConfig(for difficulty: TestDifficulty, loopLevel: Int, levelModifiers: DifficultySettings?) -> OneTouchPassingConfig {
        let base = defaultConfig(for: difficulty, loopLevel: loopLevel)
        guard let m = levelModifiers else { return base }
        return OneTouchPassingConfig(
            difficulty: base.difficulty,
            revealStyle: base.revealStyle,
            revealSpacingSeconds: max(0.06, base.revealSpacingSeconds * m.cueDuration),
            cueVisibleSeconds: max(0.3, base.cueVisibleSeconds * m.cueDuration),
            curriculumLoopLevel: base.curriculumLoopLevel
        )
    }
}
