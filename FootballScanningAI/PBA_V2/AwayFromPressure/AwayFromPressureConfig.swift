//
//  AwayFromPressureConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Playing Away From Pressure V1: scan window + danger zone duration.
//

import Foundation

struct AwayFromPressureConfig {
    let difficulty: TestDifficulty
    let scanDelayRange: ClosedRange<Double>
    let markerVisibleSeconds: Double

    static func config(for difficulty: TestDifficulty) -> AwayFromPressureConfig {
        switch difficulty {
        case .beginner:
            return AwayFromPressureConfig(difficulty: difficulty, scanDelayRange: 6 ... 8, markerVisibleSeconds: 0.8)
        case .standard:
            return AwayFromPressureConfig(difficulty: difficulty, scanDelayRange: 4 ... 6, markerVisibleSeconds: 0.65)
        case .advanced:
            return AwayFromPressureConfig(difficulty: difficulty, scanDelayRange: 3 ... 5, markerVisibleSeconds: 0.5)
        }
    }

    /// Loop scaling for guided curriculum (v1 supports loops 1...3).
    /// Loop 1 = default, loop 2/3 = slightly faster tempo + shorter decision window.
    static func config(for difficulty: TestDifficulty, loopLevel: Int) -> AwayFromPressureConfig {
        let base = config(for: difficulty)
        switch max(1, min(3, loopLevel)) {
        case 1:
            return base
        case 2:
            return AwayFromPressureConfig(
                difficulty: difficulty,
                scanDelayRange: (base.scanDelayRange.lowerBound * 0.9)...(base.scanDelayRange.upperBound * 0.9),
                markerVisibleSeconds: max(0.45, base.markerVisibleSeconds * 0.9)
            )
        default:
            return AwayFromPressureConfig(
                difficulty: difficulty,
                scanDelayRange: (base.scanDelayRange.lowerBound * 0.8)...(base.scanDelayRange.upperBound * 0.8),
                markerVisibleSeconds: max(0.40, base.markerVisibleSeconds * 0.82)
            )
        }
    }
}
