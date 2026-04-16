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
    struct ThresholdProfile {
        let fast: Double
        let medium: Double
    }

    enum AdaptiveDifficulty: String {
        case easy
        case standard
        case elite
    }

    private struct WindowThresholds {
        let fastAbove: Double
        let mediumAbove: Double
    }

    private static func thresholds(for activity: ActivityKind) -> WindowThresholds {
        switch activity {
        case .awayFromPressure:
            return WindowThresholds(fastAbove: 0.30, mediumAbove: 0.10)
        case .dribbleOrPass:
            return WindowThresholds(fastAbove: 0.25, mediumAbove: 0.05)
        case .oneTouchPassing:
            return WindowThresholds(fastAbove: 0.20, mediumAbove: 0.00)
        case .twoMinuteTest:
            return WindowThresholds(fastAbove: 0.10, mediumAbove: -0.10)
        }
    }

    private static func adaptiveDifficulty(for score: Int) -> AdaptiveDifficulty {
        if score < 60 { return .easy }
        if score <= 80 { return .standard }
        return .elite
    }

    private static func adjustmentSeconds(for difficulty: AdaptiveDifficulty) -> Double {
        switch difficulty {
        case .easy: return 0.05
        case .standard: return 0.0
        case .elite: return -0.05
        }
    }

    private static let defaultPassDistanceMeters: Double = 11.0

    static func expectedBallTravelTime(
        activity: ActivityKind,
        difficulty: TestDifficulty? = nil,
        passDistanceMeters: Double = defaultPassDistanceMeters
    ) -> Double {
        let tempo = difficulty?.passTempo ?? .elite
        return tempo.expectedBallTravelTime(distanceMeters: passDistanceMeters)
    }

    static func expectedBallArrivalTime(
        triggerTime: Date,
        activity: ActivityKind,
        difficulty: TestDifficulty? = nil,
        passDistanceMeters: Double = defaultPassDistanceMeters
    ) -> Date {
        triggerTime.addingTimeInterval(
            expectedBallTravelTime(
                activity: activity,
                difficulty: difficulty,
                passDistanceMeters: passDistanceMeters
            )
        )
    }

    /// Positive means player decided before expected arrival.
    static func decisionWindow(
        rawRepInterval: TimeInterval,
        activity: ActivityKind,
        difficulty: TestDifficulty? = nil,
        passDistanceMeters: Double = defaultPassDistanceMeters
    ) -> TimeInterval {
        expectedBallTravelTime(
            activity: activity,
            difficulty: difficulty,
            passDistanceMeters: passDistanceMeters
        ) - rawRepInterval
    }

    static func summaryText(windowSeconds: Double) -> String {
        if windowSeconds > 0 {
            return String(format: "%.2f s before expected arrival (relative to pass tempo)", windowSeconds)
        }
        if windowSeconds < 0 {
            return String(format: "%.2f s after expected arrival (relative to pass tempo)", abs(windowSeconds))
        }
        return "At expected arrival (relative to pass tempo)"
    }

    static var timingContextLabel: String {
        "Based on standard pass tempo"
    }

    static func adjustedThresholds(activity: ActivityKind, score: Int) -> ThresholdProfile {
        let base = thresholds(for: activity)
        let difficulty = adaptiveDifficulty(for: score)
        let adjustment = adjustmentSeconds(for: difficulty)
        let profile = ThresholdProfile(
            fast: base.fastAbove + adjustment,
            medium: base.mediumAbove + adjustment
        )
        #if DEBUG
        print("[AdaptiveThresholdDebug] activity=\(activity.rawValue) score=\(score) difficulty=\(difficulty.rawValue) baseThresholds=(fast:\(base.fastAbove),medium:\(base.mediumAbove)) adjustedThresholds=(fast:\(profile.fast),medium:\(profile.medium))")
        #endif
        return profile
    }

    static func speedBucket(forDecisionWindow windowSeconds: Double, activity: ActivityKind, score: Int) -> RepDecisionBucket {
        let thresholds = adjustedThresholds(activity: activity, score: score)
        let bucket: RepDecisionBucket
        if windowSeconds > thresholds.fast {
            bucket = .fast
        } else if windowSeconds > thresholds.medium {
            bucket = .medium
        } else {
            bucket = .slow
        }
        #if DEBUG
        print("[DecisionWindowBucket] activity=\(activity.rawValue) decisionWindowSeconds=\(windowSeconds) bucket=\(bucket.rawValue)")
        #endif
        return bucket
    }

    static func speedScoreComponent(forDecisionWindow windowSeconds: Double, activity: ActivityKind, score: Int) -> Double {
        switch speedBucket(forDecisionWindow: windowSeconds, activity: activity, score: score) {
        case .fast: return 1.0
        case .medium: return 0.85
        case .slow: return 0.4
        }
    }

    static func decisionScore(accuracy: Double, windows: [Double], activity: ActivityKind) -> Int {
        guard !windows.isEmpty else { return 0 }
        let baselineScore = Int((accuracy * 100).rounded())
        let speedComponent = windows.map { speedScoreComponent(forDecisionWindow: $0, activity: activity, score: baselineScore) }.reduce(0, +) / Double(windows.count)
        let weighted = (accuracy * 0.70) + (speedComponent * 0.30)
        return Int((weighted * 100).rounded())
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
