//
//  ProfileEvaluator.swift
//  FootballScanningAI
//
//  PBA V2 — Deterministic profile from 2-minute test metrics (4 labels).
//

import Foundation

enum ProfileEvaluator {
    /// Compute profile from test metrics. Predictable requires bias Left/Right and that side >= 65% of exits.
    static func profile(
        speedBucket: SpeedBucket,
        bias: String?,
        forwardCorrect: Int?,
        leftExits: Int,
        rightExits: Int,
        totalExits: Int
    ) -> PlayerProfile {
        if speedBucket == .slow {
            return .latePlanner
        }
        if let b = bias, (b == "Left" || b == "Right"), totalExits > 0 {
            let sideCount = b == "Left" ? leftExits : rightExits
            if Double(sideCount) / Double(totalExits) >= 0.65 {
                return .predictable
            }
        }
        if let f = forwardCorrect, f <= 1 {
            return .safePlayer
        }
        return .gameReady
    }
}
