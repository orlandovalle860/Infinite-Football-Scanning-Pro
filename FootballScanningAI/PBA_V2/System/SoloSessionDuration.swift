//
//  SoloSessionDuration.swift
//  FootballScanningAI
//
//  Time-based training: duration selection, session state, and rep budget.
//

import Foundation

enum SoloSessionDurationChoice: String, CaseIterable, Identifiable {
    case fiveMin = "5min"
    case tenMin = "10min"
    case fifteenMin = "15min"
    case free = "free"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveMin: return "5 minutes (Quick)"
        case .tenMin: return "10 minutes (Standard)"
        case .fifteenMin: return "15 minutes (Extended)"
        case .free: return "Train freely"
        }
    }

    var shortTitle: String {
        switch self {
        case .fiveMin: return "5-minute session"
        case .tenMin: return "10-minute session"
        case .fifteenMin: return "15-minute session"
        case .free: return "Free session"
        }
    }

    /// Soft rep guidance — not enforced.
    var repTarget: Int? {
        switch self {
        case .fiveMin: return 20
        case .tenMin: return 40
        case .fifteenMin: return 60
        case .free: return nil
        }
    }

    var durationSeconds: TimeInterval? {
        switch self {
        case .fiveMin: return 5 * 60
        case .tenMin: return 10 * 60
        case .fifteenMin: return 15 * 60
        case .free: return nil
        }
    }

    var isTimed: Bool { durationSeconds != nil }

    /// Compact label for session logs and analytics (e.g. `free`, `5m`, `10m`).
    var logLabel: String {
        switch self {
        case .free: return "free"
        case .fiveMin: return "5m"
        case .tenMin: return "10m"
        case .fifteenMin: return "15m"
        }
    }

    static func loadLastSelected() -> SoloSessionDurationChoice {
        guard let raw = UserDefaults.standard.string(forKey: AppStorageKeys.lastSessionDuration),
              let choice = SoloSessionDurationChoice(rawValue: raw) else {
            return .tenMin
        }
        // Migrate legacy stored values.
        switch raw {
        case "20min": return .fifteenMin
        default: break
        }
        return choice
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
