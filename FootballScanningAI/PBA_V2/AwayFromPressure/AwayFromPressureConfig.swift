//
//  AwayFromPressureConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Playing Away From Pressure V1: scan window + danger zone duration.
//

import Foundation

struct AwayFromPressureConfig {
    let difficulty: TestDifficulty
    /// Documentary range; per-rep delay is always `UnifiedScanToBeepTiming.randomDelaySeconds()` (not difficulty-based).
    let scanDelayRange: ClosedRange<Double>
    let markerVisibleSeconds: Double
    /// Curriculum loop (1...3); for logging only — does **not** scale scan→beep delay.
    let curriculumLoopLevel: Int

    static func config(for difficulty: TestDifficulty) -> AwayFromPressureConfig {
        config(for: difficulty, loopLevel: 1)
    }

    /// Loop scaling applies to **marker / decision window** only, not scan→beep timing.
    static func config(for difficulty: TestDifficulty, loopLevel: Int) -> AwayFromPressureConfig {
        let baseMarker: Double
        switch difficulty {
        case .beginner: baseMarker = 0.8
        case .standard: baseMarker = 0.65
        case .advanced: baseMarker = 0.5
        }
        let level = max(1, min(3, loopLevel))
        let marker: Double
        switch level {
        case 1:
            marker = baseMarker
        case 2:
            marker = max(0.45, baseMarker * 0.9)
        default:
            marker = max(0.40, baseMarker * 0.82)
        }
        return AwayFromPressureConfig(
            difficulty: difficulty,
            scanDelayRange: UnifiedScanToBeepTiming.delayRangeSeconds,
            markerVisibleSeconds: marker,
            curriculumLoopLevel: level
        )
    }

    /// Optional level-based multipliers from session summary (marker / decision window ∝ `travelTime`).
    static func config(for difficulty: TestDifficulty, loopLevel: Int, levelModifiers: DifficultySettings?) -> AwayFromPressureConfig {
        let base = config(for: difficulty, loopLevel: loopLevel)
        guard let m = levelModifiers else { return base }
        return AwayFromPressureConfig(
            difficulty: base.difficulty,
            scanDelayRange: base.scanDelayRange,
            markerVisibleSeconds: max(0.35, base.markerVisibleSeconds * m.travelTime),
            curriculumLoopLevel: base.curriculumLoopLevel
        )
    }
}
