//
//  ActivityInstructionContent.swift
//  FootballScanningAI
//
//  PBA V2 — Instruction copy per activity: game-like sections + scoring (copy-only; no logic changes).
//

import Foundation

struct ActivityInstructionData {
    let title: String
    /// Section 3 — YOUR DECISION (activity-specific bullets).
    let yourDecisionLines: [String]
    /// Scoring — short (1–3 lines max on main screen).
    let scoringShort: String
    /// Optional detailed scoring (DOP point table, etc.) — shown under “Details”.
    let scoringDetails: String?

    // MARK: — Shared instruction structure (all activities)

    /// Section 1 — SETUP
    static let instructionSetupLines: [String] = [
        "Player moves freely while scanning and checking their shoulder.",
        "The iPad is set up behind the player.",
        "Coach stands about 12 yards away from the player."
    ]

    /// Section 2 — AT THE BEEP
    static let standardGestureTemplateLines: [String] = [
        "Scan early",
        "Know your decision",
        "Swipe as the ball arrives"
    ]

    static let instructionAtTheBeepLines: [String] = [
        "Scan early.",
        "Know your decision.",
        "Swipe as the ball arrives."
    ]

    /// When the coach logs on the remote (single source of truth; also Section 4 line 2).
    static let coachFirstDecisionLoggingLine = "Log the swipe direction as soon as the player makes their first movement or touch — not after they continue."

    /// Section 4 — COACH
    static let instructionCoachLines: [String] = [
        "Tap PASS as you play the ball.",
        coachFirstDecisionLoggingLine
    ]

    /// Reinforces early commitment (shown after YOUR DECISION bullets).
    static let timingLine = "Scan → decide → swipe."

    // MARK: — In-session / coach remote (same phrases as instructions where noted)

    /// Partner mode — one line at top when applicable (legacy hub copy; optional).
    static let partnerRoleLine = "Coach controls the rep. Player reacts and decides."

    static let partnerCoachSetupLine = "Coach stands about 12 yards away from the player."
    static let partnerCoachBallLine = "Coach plays the ball from about 12 yards away each rep."

    /// PASS timing — aligned with instruction Section 4.
    static let partnerCoachPassTimingLine = "Tap PASS as you play the ball."

    static let partnerPlayerBeepLine = "When you hear the beep, check toward the center."

    static let coachFirstDecisionLoggingLineShort = "Log the first decision immediately (first movement, not outcome)"
}

/// Solo Display tap overlays — the app scores the first decision, not a completed run through a slot.
enum ActivityDisplaySessionCopy {
    static let tapTwoMinuteOrDOP = "Swipe your decision."
    static let tapOneTouchPassing = "Swipe the direction you chose — pass to green."
    static let tapAwayFromPressure = "Swipe your first decision — opposite the red (away from pressure)."
}

enum ActivityInstructionContent {
    static func content(for activity: ActivityKind) -> ActivityInstructionData {
        switch activity {
        case .twoMinuteTest:
            return ActivityInstructionData(
                title: ActivityKind.twoMinuteTest.displayName,
                yourDecisionLines: [
                    "Check surroundings early.",
                    "Recognize the open gate.",
                    "Swipe your decision as soon as the ball arrives."
                ],
                scoringShort: "Correct = your first decision matches the ball direction. Scoring uses accuracy, timing, and consistency.",
                scoringDetails: nil
            )
        case .awayFromPressure:
            return ActivityInstructionData(
                title: ActivityKind.awayFromPressure.displayName,
                yourDecisionLines: [
                    "Scan for pressure.",
                    "Identify the safest space.",
                    "Swipe away from pressure as the ball arrives."
                ],
                scoringShort: "Correct = your first decision is opposite the red. Block score uses correct reps and decision timing.",
                scoringDetails: nil
            )
        case .dribbleOrPass:
            return ActivityInstructionData(
                title: ActivityKind.dribbleOrPass.displayName,
                yourDecisionLines: [
                    "Scan before expected arrival.",
                    "If forward space is open → dribble.",
                    "If not → pass.",
                    "Swipe your decision as the ball arrives."
                ],
                scoringShort: """
                Forward pass = best choice when you decide it early.
                Correct first decision = rewarded.
                Wrong first decision = no points.
                """,
                scoringDetails: """
                Points per rep (first decision): forward pass 4, forward dribble 3, lateral pass 2, lateral dribble 1, backward 0. Fast decisions add a timing bonus. Max 60 points per block.
                """
            )
        case .oneTouchPassing:
            return ActivityInstructionData(
                title: ActivityKind.oneTouchPassing.displayName,
                yourDecisionLines: [
                    "Scan multiple options early.",
                    "Decide before expected arrival.",
                    "Swipe immediately on contact."
                ],
                scoringShort: "Correct = your first decision targets a green teammate. Score uses correct reps, timing, and field balance.",
                scoringDetails: nil
            )
        }
    }

    static func dontShowAgainKey(for activity: ActivityKind) -> String {
        "pba_dont_show_instructions_\(activity.rawValue)"
    }

    static func shouldShowInstructions(for activity: ActivityKind) -> Bool {
        !UserDefaults.standard.bool(forKey: dontShowAgainKey(for: activity))
    }

    static func setDontShowAgain(_ value: Bool, for activity: ActivityKind) {
        UserDefaults.standard.set(value, forKey: dontShowAgainKey(for: activity))
    }
}
