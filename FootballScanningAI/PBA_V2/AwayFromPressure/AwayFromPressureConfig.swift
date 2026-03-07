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
            return AwayFromPressureConfig(difficulty: difficulty, scanDelayRange: 6 ... 8, markerVisibleSeconds: 1.0)
        case .standard:
            return AwayFromPressureConfig(difficulty: difficulty, scanDelayRange: 4 ... 6, markerVisibleSeconds: 0.8)
        case .advanced:
            return AwayFromPressureConfig(difficulty: difficulty, scanDelayRange: 3 ... 5, markerVisibleSeconds: 0.6)
        }
    }
}
