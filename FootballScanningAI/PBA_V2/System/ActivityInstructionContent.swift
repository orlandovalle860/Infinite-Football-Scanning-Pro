//
//  ActivityInstructionContent.swift
//  FootballScanningAI
//
//  PBA V2 — Standardized instruction content per activity (goal, cues, decision rule, scoring).
//

import Foundation

struct ActivityInstructionData {
    let title: String
    let goal: String
    let whatToLookFor: String
    let whatToDo: String
    let scoring: String
}

enum ActivityInstructionContent {
    static func content(for activity: ActivityKind) -> ActivityInstructionData {
        switch activity {
        case .twoMinuteTest:
            return ActivityInstructionData(
                title: "2-Minute Test",
                goal: "See how quickly and accurately you read where the ball is going.",
                whatToLookFor: "A ball will appear in one of four directions: UP, LEFT, RIGHT, or DOWN. Scan the whole field before the beep.",
                whatToDo: "Make your first decision match the ball’s side — exit through the same direction you read. Decide before the ball arrives.",
                scoring: "Each rep is correct if your exit direction matches the ball. Speed (fast/medium/slow) and consistency build your baseline."
            )
        case .awayFromPressure:
            return ActivityInstructionData(
                title: "Playing Away From Pressure",
                goal: "Turn away from pressure into space — commit your first move opposite where pressure shows.",
                whatToLookFor: "After the beep, a red wedge shows where pressure is coming from.",
                whatToDo: "Move in the direction opposite the pressure (through the gate opposite the red). Your first decision should match that escape.",
                scoring: "Each rep has one correct exit: the gate opposite the red pressure. Correct = your logged direction matched that escape. The block score uses correct reps and decision timing."
            )
        case .dribbleOrPass:
            return ActivityInstructionData(
                title: "Dribble or Pass",
                goal: "Choose the best option: pass to a teammate (green), carry into space (open gate), or avoid pressure (red).",
                whatToLookFor: "Red = pressure. Green = teammate. Open gate = space to carry the ball. After the beep, each gate shows one: red fill (avoid), green fill (pass), or open (carry).",
                whatToDo: "Pick one direction. Forward pass (green) scores highest; forward carry next; lateral options then backward.",
                scoring: "Points per rep: forward pass 4, forward dribble 3, lateral pass 2, lateral dribble 1, backward 0. Fast decisions get a timing bonus. Max 60 per block."
            )
        case .oneTouchPassing:
            return ActivityInstructionData(
                title: "One-Touch Passing",
                goal: "Pass to a teammate (green) with a committed first decision.",
                whatToLookFor: "Red = pressure. Green = teammate. Gates show green (teammates – pass) or red (opponents – avoid).",
                whatToDo: "Choose any green gate. Execute a pass to that option. Avoid red.",
                scoring: "Correct = you passed to a green gate. Block score uses correct count, timing (fast/medium/slow), and bias (balanced vs one side)."
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
