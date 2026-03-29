//
//  DecisionTimingModel.swift
//  FootballScanningAI
//
//  Decision timing reframed around ball arrival:
//  raw rep interval (trigger -> logged decision) stays internal;
//  user-facing timing uses decision window (arrival - decision).
//

import Foundation

enum DecisionTimingModel {
    /// Expected ground-pass flight time (seconds) for partner/coach delivery. Calibrated for ~10 yd;
    /// prior values (~0.58–0.68 s) matched a shorter setup (~6 yd). Scale factor 10/6.
    private static let travelByActivity: [ActivityKind: Double] = [
        .awayFromPressure: 1.03,
        .dribbleOrPass: 1.13,
        .oneTouchPassing: 0.97,
        .twoMinuteTest: 1.07,
    ]

    static func expectedBallTravelTime(activity: ActivityKind, difficulty: TestDifficulty? = nil) -> Double {
        let base = travelByActivity[activity] ?? 1.07
        guard let difficulty else { return base }
        switch difficulty {
        case .beginner: return base + 0.08
        case .standard: return base
        case .advanced: return max(0.75, base - 0.07)
        }
    }

    static func expectedBallArrivalTime(triggerTime: Date, activity: ActivityKind, difficulty: TestDifficulty? = nil) -> Date {
        triggerTime.addingTimeInterval(expectedBallTravelTime(activity: activity, difficulty: difficulty))
    }

    /// Positive means player decided before expected arrival.
    static func decisionWindow(rawRepInterval: TimeInterval, activity: ActivityKind, difficulty: TestDifficulty? = nil) -> TimeInterval {
        expectedBallTravelTime(activity: activity, difficulty: difficulty) - rawRepInterval
    }

    static func summaryText(windowSeconds: Double) -> String {
        if windowSeconds > 0 {
            return String(format: "%.2f s before arrival", windowSeconds)
        }
        if windowSeconds < 0 {
            return String(format: "%.2f s after arrival", abs(windowSeconds))
        }
        return "At arrival"
    }
}

extension SessionResult {
    /// Raw average interval (trigger -> logged first decision); kept for scoring/debug/backward compatibility.
    var avgRawRepIntervalSeconds: Double? { avgDecisionTime }

    /// Primary user-facing timing metric.
    var avgDecisionWindowSeconds: Double? {
        guard let raw = avgDecisionTime else { return nil }
        return DecisionTimingModel.decisionWindow(rawRepInterval: raw, activity: activityType, difficulty: difficulty)
    }
}

extension SessionRecord {
    /// Raw average interval (trigger -> logged first decision); persisted for analytics/scoring.
    var avgRawRepIntervalSeconds: Double? { avgLatency }

    /// Primary user-facing timing metric derived from the raw interval.
    var avgDecisionWindowSeconds: Double? {
        guard let raw = avgLatency else { return nil }
        return DecisionTimingModel.decisionWindow(rawRepInterval: raw, activity: activity, difficulty: difficulty)
    }
}

extension TwoMinuteTestResult {
    /// Raw average interval (trigger -> logged first decision), same as pre-refactor behavior.
    var avgRawRepIntervalSeconds: Double? { avgDecisionTime }

    var avgDecisionWindowSeconds: Double? {
        guard let raw = avgDecisionTime else { return nil }
        return DecisionTimingModel.decisionWindow(rawRepInterval: raw, activity: .twoMinuteTest, difficulty: difficulty)
    }
}

extension RepLog {
    /// Internal timing capture for this rep: trigger -> logged first decision.
    var rawRepIntervalSeconds: Double? {
        guard let pt = passTriggeredAt else { return nil }
        return exitLoggedAt.timeIntervalSince(pt)
    }

    /// User-facing rep timing relative to expected arrival (positive = before arrival).
    func decisionWindowSeconds(activity: ActivityKind = .twoMinuteTest, difficulty: TestDifficulty? = nil) -> Double? {
        guard let raw = rawRepIntervalSeconds else { return nil }
        return DecisionTimingModel.decisionWindow(rawRepInterval: raw, activity: activity, difficulty: difficulty)
    }
}
