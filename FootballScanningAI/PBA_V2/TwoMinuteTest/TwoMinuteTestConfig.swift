//
//  TwoMinuteTestConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Config for 2-Minute Critical Scan test. Baseline is fixed for comparable results; training activities use TestDifficulty.
//

import Foundation

/// Difficulty level: scan window and ball visibility duration. Used by training activities (AFP, DOP, OTP); 2-minute test uses baseline only.
enum TestDifficulty: String, CaseIterable, Hashable, Codable {
    case beginner
    case standard
    case advanced
}

struct TwoMinuteTestConfig {
    let difficulty: TestDifficulty
    let scanDelayRange: ClosedRange<Double>
    let ballVisibleSeconds: Double

    /// Fixed configuration for the 2-minute baseline test. Same for all users so decision speed and accuracy are comparable.
    static let baseline: TwoMinuteTestConfig = TwoMinuteTestConfig(
        difficulty: .standard,
        scanDelayRange: 5 ... 7,
        ballVisibleSeconds: 0.8
    )

    static func config(for difficulty: TestDifficulty) -> TwoMinuteTestConfig {
        switch difficulty {
        case .beginner:
            return TwoMinuteTestConfig(difficulty: difficulty, scanDelayRange: 7 ... 9, ballVisibleSeconds: 1.0)
        case .standard:
            return TwoMinuteTestConfig(difficulty: difficulty, scanDelayRange: 5 ... 7, ballVisibleSeconds: 0.8)
        case .advanced:
            return TwoMinuteTestConfig(difficulty: difficulty, scanDelayRange: 3 ... 5, ballVisibleSeconds: 0.6)
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
