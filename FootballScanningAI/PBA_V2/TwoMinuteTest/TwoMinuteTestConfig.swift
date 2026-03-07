//
//  TwoMinuteTestConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Difficulty and config for 2-Minute Critical Scan test.
//

import Foundation

/// Difficulty level: scan window and star visibility duration.
enum TestDifficulty: String, CaseIterable, Hashable, Codable {
    case beginner
    case standard
    case advanced
}

struct TwoMinuteTestConfig {
    let difficulty: TestDifficulty
    let scanDelayRange: ClosedRange<Double>
    let starVisibleSeconds: Double

    static func config(for difficulty: TestDifficulty) -> TwoMinuteTestConfig {
        switch difficulty {
        case .beginner:
            return TwoMinuteTestConfig(difficulty: difficulty, scanDelayRange: 7 ... 9, starVisibleSeconds: 1.0)
        case .standard:
            return TwoMinuteTestConfig(difficulty: difficulty, scanDelayRange: 5 ... 7, starVisibleSeconds: 0.8)
        case .advanced:
            return TwoMinuteTestConfig(difficulty: difficulty, scanDelayRange: 3 ... 5, starVisibleSeconds: 0.6)
        }
    }
}

private let twoMinuteTestDifficultyKey = "twoMinuteTestDifficulty"

extension TestDifficulty {
    static func loadFromUserDefaults() -> TestDifficulty {
        guard let raw = UserDefaults.standard.string(forKey: twoMinuteTestDifficultyKey),
              let value = TestDifficulty(rawValue: raw) else {
            return .standard
        }
        return value
    }

    func saveToUserDefaults() {
        UserDefaults.standard.set(rawValue, forKey: twoMinuteTestDifficultyKey)
    }
}
