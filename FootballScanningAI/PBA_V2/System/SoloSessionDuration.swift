//
//  SoloSessionDuration.swift
//  FootballScanningAI
//
//  Solo time-based training: duration selection, session state, and rep budget.
//

import Foundation

enum SoloSessionDurationChoice: String, CaseIterable, Identifiable {
    case tenMin = "10min"
    case fifteenMin = "15min"
    case twentyMin = "20min"
    case free = "free"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tenMin: return "10 minutes"
        case .fifteenMin: return "15 minutes"
        case .twentyMin: return "20 minutes"
        case .free: return "Train freely"
        }
    }

    var durationSeconds: TimeInterval? {
        switch self {
        case .tenMin: return 10 * 60
        case .fifteenMin: return 15 * 60
        case .twentyMin: return 20 * 60
        case .free: return nil
        }
    }

    var isTimed: Bool { durationSeconds != nil }

    static func loadLastSelected() -> SoloSessionDurationChoice {
        guard let raw = UserDefaults.standard.string(forKey: AppStorageKeys.lastSessionDuration),
              let choice = SoloSessionDurationChoice(rawValue: raw) else {
            return .fifteenMin
        }
        return choice
    }

    static func saveLastSelected(_ choice: SoloSessionDurationChoice) {
        UserDefaults.standard.set(choice.rawValue, forKey: AppStorageKeys.lastSessionDuration)
    }
}

/// Active solo time-based session (set after duration selection, cleared on session complete).
@MainActor
enum SoloTimeBasedSession {
    /// Large rep budget so timed/free sessions are not cut off by block size.
    static let unlimitedRepBudget = 5000

    private(set) static var config: SoloSessionDurationChoice?
    private(set) static var trainingStyle: SoloTrainingStyle?
    private(set) static var sessionRepCount = 0
    private(set) static var sessionStartedAt: Date?

    static var isActive: Bool { config != nil }

    static var usesAutoloop: Bool {
        (trainingStyle ?? SoloTrainingStyle.loadLastSelected()).usesAutoloop
    }

    static func begin(duration choice: SoloSessionDurationChoice, style: SoloTrainingStyle) {
        config = choice
        trainingStyle = style
        sessionRepCount = 0
        sessionStartedAt = Date()
    }

    static func begin(with choice: SoloSessionDurationChoice) {
        begin(duration: choice, style: SoloTrainingStyle.loadLastSelected())
    }

    static func clear() {
        config = nil
        trainingStyle = nil
        sessionRepCount = 0
        sessionStartedAt = nil
    }

    static func recordRepCompleted() {
        sessionRepCount += 1
    }

    static func elapsedSeconds(now: Date = Date()) -> TimeInterval {
        guard let sessionStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(sessionStartedAt))
    }

    static func blockRepCount(
        activityId: String,
        soloFallback: Int,
        mode: TrainingMode
    ) -> Int {
        if mode == .solo, isActive {
            return unlimitedRepBudget
        }
        return TrainingPartnerConnectionCoordinator.shared.partnerBlockTotalReps(
            activityId: activityId,
            soloFallback: soloFallback,
            mode: mode
        )
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
