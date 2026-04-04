//
//  UnifiedScanToBeepTiming.swift
//  FootballScanningAI
//
//  PBA V2 — Next rep → scan-end cue (beep, or CHECK for OTP) uses one random delay range for all difficulties.
//

import Foundation

/// Shared scan-window timing: **not** difficulty-based and **not** curriculum-loop–scaled.
enum UnifiedScanToBeepTiming {
    /// Seconds from entering the scan phase until the beep (or CHECK cue for One-Touch Passing).
    static let delayRangeSeconds: ClosedRange<Double> = 2.0...4.0

    static func randomDelaySeconds() -> Double {
        Double.random(in: delayRangeSeconds)
    }

    #if DEBUG
    enum TimingModel: String {
        case unified
        case legacy
    }

    /// Logs one scheduled scan→beep delay. `model` is `legacy` only if an activity still uses a non-unified table.
    static func logSchedule(activity: String, delaySeconds: Double, difficulty: TestDifficulty, loopLevel: Int, model: TimingModel) {
        print("[UnifiedBeepTiming-Debug] activity=\(activity) delay=\(String(format: "%.3f", delaySeconds)) difficulty=\(difficulty.rawValue) loop=\(loopLevel) model=\(model.rawValue)")
    }
    #endif
}
