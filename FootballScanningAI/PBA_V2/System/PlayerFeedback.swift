//
//  PlayerFeedback.swift
//  FootballScanningAI
//
//  PBA V2 — Session-level coaching feedback from accuracy, decision window, and score (deterministic).
//

import Foundation

enum PlayerFeedbackProfile: String, Codable, Equatable {
    case elite
    case fastButInaccurate
    case accurateButLate
    case struggling
}

struct PlayerFeedback: Equatable {
    let profile: PlayerFeedbackProfile
    let message: String
}

enum PlayerFeedbackEngine {

    /// Accuracy in 0…1, average decision window in seconds (nil treated as 0 for classification), decision score 0…100 for logging.
    static func metrics(from result: SessionResult) -> (accuracy: Double, averageDecisionWindow: Double, decisionScore: Double) {
        let accuracy = result.totalReps > 0 ? Double(result.correctCount) / Double(result.totalReps) : 0
        let averageDecisionWindow = result.avgDecisionTime ?? 0
        let decisionScore = decisionScoreNormalized(from: result)
        return (accuracy, averageDecisionWindow, decisionScore)
    }

    /// Deterministic feedback from the completed session (does not affect scoring or progression).
    static func feedback(from result: SessionResult) -> PlayerFeedback {
        let accuracy = result.totalReps > 0 ? Double(result.correctCount) / Double(result.totalReps) : 0
        let w = result.avgDecisionTime ?? 0

        let profile: PlayerFeedbackProfile
        if accuracy >= 0.80 && w > 0.15 {
            profile = .elite
        } else if accuracy < 0.70 && w > 0 {
            profile = .fastButInaccurate
        } else if accuracy >= 0.70 && w <= 0 {
            profile = .accurateButLate
        } else {
            profile = .struggling
        }

        let message = message(for: profile, session: result)
        return PlayerFeedback(profile: profile, message: message)
    }

    /// Call once when a session result is saved (e.g. from `addSessionResult`).
    static func logFeedbackDebug(for result: SessionResult) {
        let fb = feedback(from: result)
        let m = metrics(from: result)
        let wStr = result.avgDecisionTime.map { String(format: "%.4f", $0) } ?? "nil"
        print("[FeedbackDebug] accuracy=\(m.accuracy) decisionWindow=\(wStr) decisionScore=\(m.decisionScore) profile=\(fb.profile.rawValue) message=\(fb.message)")
    }

    private static func decisionScoreNormalized(from result: SessionResult) -> Double {
        if let s = result.decisionTotalScore {
            return min(100, max(0, s))
        }
        if let e = result.estimatedDecisionSpeedScore {
            return Double(min(100, max(0, e)))
        }
        return 0
    }

    private static func message(for profile: PlayerFeedbackProfile, session: SessionResult) -> String {
        if session.activityType == .dribbleOrPass,
           let optimal = session.decisionOptimalCount,
           let acceptableOnly = session.decisionAcceptableOnlyCount,
           session.totalReps > 0 {
            let total = session.totalReps
            let incorrect = total - session.correctCount
            let w = session.avgDecisionTime ?? 0
            let early = w > 0.15
            let late = w <= 0
            let optimalShare = Double(optimal) / Double(total)
            let acceptableShare = Double(acceptableOnly) / Double(total)

            if incorrect >= 1, early {
                return "Good early decisions — now choose the right option"
            }
            if optimalShare >= 0.55, late {
                return "Right idea — make the decision earlier"
            }
            if acceptableShare >= 0.35, incorrect <= 2, optimalShare < 0.55 {
                return "Safe decision — look forward sooner"
            }
            if optimalShare >= 0.65, early, incorrect == 0 {
                return "Excellent — early and correct"
            }
        }

        switch profile {
        case .elite:
            return "Elite — you're seeing it early and acting on it. Now handle more complexity."
        case .fastButInaccurate:
            return "Good early decisions — now choose the right option"
        case .accurateButLate:
            return "You're choosing well, but too late. Decide before expected arrival."
        case .struggling:
            return "You're reacting instead of seeing it early. Scan sooner before the pass."
        }
    }
}
