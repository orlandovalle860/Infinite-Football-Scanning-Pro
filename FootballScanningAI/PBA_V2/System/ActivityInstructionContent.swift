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
                whatToLookFor: "A star (ball) will appear in one of four directions: UP, LEFT, RIGHT, or DOWN. Scan the whole field before the beep.",
                whatToDo: "Your first touch must take you out through the same side as the star. Decide before the ball arrives.",
                scoring: "Each rep is correct if your exit direction matches the star. Speed (fast/medium/slow) and consistency build your baseline."
            )
        case .awayFromPressure:
            return ActivityInstructionData(
                title: "Playing Away From Pressure",
                goal: "Take your first touch away from pressure into space.",
                whatToLookFor: "Red = pressure. Open gate = dribble space. After the beep, a red zone appears in one direction—that’s where pressure is. Other gates show only an outline (open space).",
                whatToDo: "Exit through the opposite side—away from the red. Your first touch must take you out that way.",
                scoring: "Correct = you exited the opposite side of the danger zone. Block score is based on correct reps and timing."
            )
        case .dribbleOrPass:
            return ActivityInstructionData(
                title: "Dribble or Pass",
                goal: "Choose the best option: pass to a teammate (green), dribble into space (open gate), or avoid pressure (red).",
                whatToLookFor: "Red = pressure. Green = teammate. Open gate = dribble space. After the beep, each gate shows one: red fill (avoid), green fill (pass), or outline only (dribble).",
                whatToDo: "Pick one direction. Forward pass (green) scores highest; forward dribble next; lateral options then backward.",
                scoring: "Points per rep: forward pass 4, forward dribble 3, lateral pass 2, lateral dribble 1, backward 0. Fast decisions get a timing bonus. Max 60 per block."
            )
        case .oneTouchPassing:
            return ActivityInstructionData(
                title: "One-Touch Passing",
                goal: "Pass to a teammate (green) with your first touch.",
                whatToLookFor: "Red = pressure. Green = teammate. Gates show green (teammates – pass) or red (opponents – avoid).",
                whatToDo: "Choose any green gate. Your first touch must be a pass to that option. Avoid red.",
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
