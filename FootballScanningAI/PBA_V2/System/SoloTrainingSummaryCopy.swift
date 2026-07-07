//
//  SoloTrainingSummaryCopy.swift
//  FootballScanningAI
//
//  Static copy for post-session and Home in Solo mode — no live metrics.
//

import Foundation

enum SoloTrainingSummaryCopy {
    static func endTitle(for activity: ActivityKind) -> String {
        switch activity {
        case .twoMinuteTest: return "\(activity.displayName) complete"
        case .awayFromPressure: return "Block complete"
        case .dribbleOrPass: return "Block complete"
        case .oneTouchPassing: return "Block complete"
        }
    }

    /// 1–2 non-quantitative coaching cues.
    static func staticCoachingLines(for activity: ActivityKind) -> [String] {
        switch activity {
        case .oneTouchPassing:
            return [
                "Set your body before the ball arrives so your first touch stays clean.",
                "Scan for two real options on every play — not just the obvious one."
            ]
        case .dribbleOrPass:
            return [
                "Picture your next action one touch before pressure arrives.",
                "Protect the ball with your body, then choose forward when it’s on."
            ]
        case .awayFromPressure:
            return [
                "Take your first look before the pressure touch.",
                "Commit to the first decision — you can always adjust on the next touch."
            ]
        case .twoMinuteTest:
            return [
                "Reset your eyes after every exit — the next read starts fresh.",
                "Stay smooth and rhythmic; speed comes from preparation, not rushing."
            ]
        }
    }
}

