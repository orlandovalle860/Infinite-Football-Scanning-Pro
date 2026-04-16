//
//  CoachingTrainingNotificationCopy.swift
//  FootballScanningAI
//
//  Coaching-style local notification copy: multiple variants per theme + optional anchors.
//

import Foundation

/// Categories used for prioritization, variation keys, and analytics-style grouping.
enum CoachingTrainingNudgeKind: String, CaseIterable {
    case performanceInconsistent
    case performanceImproving
    case performanceSlowDecisions
    case performanceDeclining
    case flowNextFocus
    case flowReadyToProgress
    case inactivityEarly
}

enum CoachingTrainingNotificationCopy {

    /// Short notification title (system line 1).
    static func title(for kind: CoachingTrainingNudgeKind) -> String {
        switch kind {
        case .performanceInconsistent: return "Sharpen your next block"
        case .performanceImproving: return "Keep the momentum"
        case .performanceSlowDecisions: return "Win time before the ball"
        case .performanceDeclining: return "Reset the picture"
        case .flowNextFocus: return "Your training path"
        case .flowReadyToProgress: return "You're ready for more"
        case .inactivityEarly: return "Eyes up — quick session"
        }
    }

    /// 1–2 sentences; caller picks variant and avoids repeating the last body.
    static func bodies(for kind: CoachingTrainingNudgeKind) -> [String] {
        switch kind {
        case .performanceInconsistent:
            return [
                "Last block jumped between speeds — pick one rhythm and hold it for the full set.",
                "Your tempo was up and down. Breathe, scan early, then commit the same way each rep.",
                "Inconsistent decisions cost you under pressure. One pre-ball picture every rep this session.",
                "Speed of play is speed of thought — make your first read calmer, then repeat it.",
            ]
        case .performanceImproving:
            return [
                "You're trending better than your last session — stack another block while it feels fresh.",
                "The numbers moved the right way. One more block today locks the habit in.",
                "Good step forward from last time. Train again before the feeling fades.",
            ]
        case .performanceSlowDecisions:
            return [
                "The window closes before expected arrival — decide a step earlier on each rep.",
                "Your last block was a tick late but mostly right. Steal time with an earlier scan.",
                "You're seeing it — now trigger the first action sooner; match speed starts there.",
            ]
        case .performanceDeclining:
            return [
                "Last session dipped versus your previous one — slow down, get one clean read, then build speed.",
                "Reset with quality over rush: correct first choices, then increase tempo next block.",
                "Trend slipped a little — own one cue (body angle + first touch idea) before the ball moves.",
            ]
        case .flowNextFocus:
            return [
                "Your path is pointing at %@ — %@",
                "Next up in your loop: %@. %@",
                "When you train, start with %@ — %@",
            ]
        case .flowReadyToProgress:
            return [
                "You've basically cleared the bar for the next activity — open %@ when you're fresh.",
                "You're in range to level up — %@ is unlocked; one focused block seals it.",
                "Ready to progress: %@ is waiting. Keep decisions clean and tempo honest.",
            ]
        case .inactivityEarly:
            return [
                "A short scanning block today keeps your first touch honest — train before the idea gets rusty.",
                "No session in a couple of days — ten minutes of decisions beats guessing on Saturday.",
                "Eyes and feet go stale without reps. Jump into one block and rehearse your pre-ball picture.",
            ]
        }
    }

    /// Fill `%@` placeholders for flow messages (activity title, curriculum focus).
    static func formatFlowNextFocus(template: String, activityTitle: String, focus: String) -> String {
        String(format: template, activityTitle, focus)
    }

    static func formatFlowReady(template: String, nextActivityTitle: String) -> String {
        String(format: template, nextActivityTitle)
    }
}
