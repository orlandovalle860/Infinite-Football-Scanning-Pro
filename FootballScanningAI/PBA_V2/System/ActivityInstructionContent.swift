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
        "Player moves freely inside a 5×5 grid, scanning and checking their shoulder.",
        "The iPad is set up behind the player.",
        "Coach stands about 10 yards away from the center of the grid."
    ]

    /// Section 2 — AT THE BEEP
    static let instructionAtTheBeepLines: [String] = [
        "When you hear the beep, check toward the center of the grid.",
        "At the same moment, the coach plays a pass and taps PASS (or the volume button)."
    ]

    /// When the coach logs on the remote (single source of truth; also Section 4 line 2).
    static let coachFirstDecisionLoggingLine = "Log the direction as soon as the player makes their first movement or touch — not after they continue."

    /// Section 4 — COACH
    static let instructionCoachLines: [String] = [
        "Tap PASS as you play the ball.",
        coachFirstDecisionLoggingLine
    ]

    /// Reinforces early commitment (shown after YOUR DECISION bullets).
    static let timingLine = "Decide before the ball arrives."

    // MARK: — In-session / coach remote (same phrases as instructions where noted)

    /// Partner mode — one line at top when applicable (legacy hub copy; optional).
    static let partnerRoleLine = "Coach controls the rep. Player reacts and decides."

    static let partnerCoachSetupLine = "Coach stands about 10 yards away from the center of the grid."
    static let partnerCoachBallLine = "Coach plays the ball from about 10 yards away each rep."

    /// PASS timing — aligned with instruction Section 4.
    static let partnerCoachPassTimingLine = "Tap PASS as you play the ball."

    static let partnerPlayerBeepLine = "When you hear the beep, check toward the center of the grid."

    static let coachFirstDecisionLoggingLineShort = "Log the first decision immediately (first movement, not outcome)"
}

/// Solo Display tap overlays — the app scores the first decision, not a completed run through a slot.
enum ActivityDisplaySessionCopy {
    static let tapTwoMinuteOrDOP = "Tap the direction of your first decision."
    static let tapOneTouchPassing = "Tap the direction you chose — pass to green."
    static let tapAwayFromPressure = "Tap your first decision — opposite the red (away from pressure)."
}

enum ActivityInstructionContent {
    static func content(for activity: ActivityKind) -> ActivityInstructionData {
        switch activity {
        case .twoMinuteTest:
            return ActivityInstructionData(
                title: "2-Minute Test",
                yourDecisionLines: [
                    "Match your first decision to the cue / ball direction."
                ],
                scoringShort: "Correct = your first decision matches the ball direction. Baseline uses accuracy, timing, and consistency.",
                scoringDetails: nil
            )
        case .awayFromPressure:
            return ActivityInstructionData(
                title: "Playing Away From Pressure",
                yourDecisionLines: [
                    "Go opposite the red pressure (into space).",
                    "First commitment counts — don’t wait for a full turn or exit."
                ],
                scoringShort: "Correct = your first decision is opposite the red. Block score uses correct reps and decision timing.",
                scoringDetails: nil
            )
        case .dribbleOrPass:
            return ActivityInstructionData(
                title: "Dribble or Pass",
                yourDecisionLines: [
                    "Pass forward if you can; otherwise dribble into space.",
                    "Avoid red; favor green or open space."
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
                title: "One-Touch Passing",
                yourDecisionLines: [
                    "Choose your target before the ball arrives.",
                    "Play one-touch to the green you already picked."
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
