//
//  SoloSessionDuration.swift
//  FootballScanningAI
//
//  Time-based training: duration selection, session state, and rep budget.
//  V1 timed sessions use a single fixed block length; Free Play stays unlimited.
//

import Foundation

enum SoloSessionDurationChoice: String, CaseIterable, Identifiable {
    /// Fixed V1 timed block (180 seconds). Raw value kept stable for UserDefaults / analytics.
    case threeMin = "3min"
    case free = "free"

    var id: String { rawValue }

    /// Fixed timed-session length for all modes (solo + partner). Free Play ignores this.
    static let timedSessionDurationSeconds: TimeInterval = 180

    var title: String {
        switch self {
        case .threeMin: return "3-Minute Training Block"
        case .free: return "Train freely"
        }
    }

    var shortTitle: String {
        switch self {
        case .threeMin: return "3-Minute Training Block"
        case .free: return "Free session"
        }
    }

    /// Soft rep guidance — not enforced.
    var repTarget: Int? {
        switch self {
        case .threeMin: return 12
        case .free: return nil
        }
    }

    var durationSeconds: TimeInterval? {
        switch self {
        case .threeMin: return Self.timedSessionDurationSeconds
        case .free: return nil
        }
    }

    var isTimed: Bool { durationSeconds != nil }

    /// Compact label for session logs and analytics (e.g. `free`, `3m`).
    var logLabel: String {
        switch self {
        case .free: return "free"
        case .threeMin: return "3m"
        }
    }

    static func loadLastSelected() -> SoloSessionDurationChoice {
        guard let raw = UserDefaults.standard.string(forKey: AppStorageKeys.lastSessionDuration) else {
            return .threeMin
        }
        if let choice = SoloSessionDurationChoice(rawValue: raw) {
            return choice
        }
        // Migrate legacy timed values (5 / 10 / 15 / 20 min) → fixed 3-minute block.
        switch raw {
        case "5min", "10min", "15min", "20min":
            return .threeMin
        default:
            return .threeMin
        }
    }

    static func saveLastSelected(_ choice: SoloSessionDurationChoice) {
        UserDefaults.standard.set(choice.rawValue, forKey: AppStorageKeys.lastSessionDuration)
    }
}

/// Active time-based session (solo or partner). Cleared when session completes.
@MainActor
enum SoloTimeBasedSession {
    private(set) static var config: SoloSessionDurationChoice?
    private(set) static var trainingStyle: SoloTrainingStyle?
    private(set) static var sessionStartedAt: Date?

    static var isActive: Bool { config != nil }

    static var usesAutoloop: Bool {
        (trainingStyle ?? SoloTrainingStyle.loadLastSelected()).usesAutoloop
    }

    static func begin(duration choice: SoloSessionDurationChoice, style: SoloTrainingStyle) {
        config = choice
        trainingStyle = style
        sessionStartedAt = nil
        SoloSessionUserStartGate.reset()
    }

    static func begin(with choice: SoloSessionDurationChoice) {
        begin(duration: choice, style: SoloTrainingStyle.loadLastSelected())
    }

    static func clear() {
        config = nil
        trainingStyle = nil
        sessionStartedAt = nil
        SoloSessionUserStartGate.reset()
    }

    /// Call when the player taps to start after calibration (solo local display).
    static func beginSessionClock() {
        sessionStartedAt = Date()
    }

    /// Fresh clock for partner Train Again — keeps duration config, resets elapsed/countdown baseline.
    static func restartSessionClock() {
        sessionStartedAt = Date()
        SoloSessionUserStartGate.reset()
    }

    static func elapsedSeconds(now: Date = Date()) -> TimeInterval {
        guard let sessionStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(sessionStartedAt))
    }
}

enum SoloSessionTimeFormat {
    static func mmss(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
