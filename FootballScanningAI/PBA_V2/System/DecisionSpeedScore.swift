//
//  DecisionSpeedScore.swift
//  FootballScanningAI
//
//  PBA V2 — unified decision score from accuracy + decision windows.
//  Window buckets: >0.25 fast, >0 medium, <=0 slow.
//

import Foundation

enum DecisionSpeedScore {
    static func sessionScore(decisionWindows: [Double], correctCount: Int, totalCount: Int, activity: ActivityKind) -> Int? {
        guard totalCount > 0, decisionWindows.count == totalCount else { return nil }
        let accuracy = Double(correctCount) / Double(totalCount)
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: decisionWindows, activity: activity)
    }
}
