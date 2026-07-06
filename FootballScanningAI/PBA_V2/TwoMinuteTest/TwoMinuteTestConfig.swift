//
//  TwoMinuteTestConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Config for 2-Minute Critical Scan. Beep delay is unified (not difficulty-based);
//  difficulty affects ball visibility and other presentation, not scan-to-beep timing.
//

import Foundation

/// Difficulty level: primarily ball-on-screen duration and presentation complexity for 2-Minute test; also used app-wide for other activities.
enum TestDifficulty: String, CaseIterable, Hashable, Codable {
    case beginner
    case standard
    case advanced
}

struct TwoMinuteTestConfig {
    let difficulty: TestDifficulty
    /// Documentary range; per-rep pre-beep delay for 2MT uses `preBeepDelayRange`.
    let scanDelayRange: ClosedRange<Double>
    let ballVisibleSeconds: Double

    /// Per-rep random wait before the tempo beep (seconds). Kept in a clear band for predictable structure.
    static let preBeepDelayRange: ClosedRange<Double> = 1.5...3.0

    /// Same base range as all PBA scan→beep timing (`UnifiedScanToBeepTiming`) — used where legacy timing is needed.
    static let twoMinuteUnifiedBeepDelayRange: ClosedRange<Double> = UnifiedScanToBeepTiming.delayRangeSeconds

    /// Random delay (seconds) after next rep before beep: mostly unified 2–4 s; occasionally a shorter burst for variety (not tied to difficulty).
    static func randomTwoMinuteBeepDelaySeconds(difficulty: TestDifficulty) -> Double {
        let delay: Double
        if Double.random(in: 0...1) < 0.12 {
            delay = Double.random(in: 1.35...1.99)
        } else {
            delay = Double.random(in: twoMinuteUnifiedBeepDelayRange)
        }
        #if DEBUG
        UnifiedScanToBeepTiming.logSchedule(
            activity: "twoMinuteCriticalScan",
            delaySeconds: delay,
            difficulty: difficulty,
            loopLevel: 1,
            model: .unified
        )
        #endif
        return delay
    }

    /// Baseline assessment: same beep timing model as training presets; ball visibility fixed for comparability.
    static let baseline: TwoMinuteTestConfig = TwoMinuteTestConfig(
        difficulty: .standard,
        scanDelayRange: twoMinuteUnifiedBeepDelayRange,
        ballVisibleSeconds: 0.8
    )

    static func config(for difficulty: TestDifficulty) -> TwoMinuteTestConfig {
        TwoMinuteTestConfig(
            difficulty: difficulty,
            scanDelayRange: twoMinuteUnifiedBeepDelayRange,
            ballVisibleSeconds: ballVisibleSecondsForDifficulty(difficulty)
        )
    }

    private static func ballVisibleSecondsForDifficulty(_ difficulty: TestDifficulty) -> Double {
        switch difficulty {
        case .beginner: return 1.0
        case .standard: return 0.8
        case .advanced: return 0.6
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
