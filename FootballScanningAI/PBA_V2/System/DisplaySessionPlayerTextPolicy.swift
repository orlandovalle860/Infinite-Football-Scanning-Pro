//
//  DisplaySessionPlayerTextPolicy.swift
//  FootballScanningAI
//
//  Display (iPad player) text overlay policy.
//
//  During an active rep cycle (stimulus → player acts → stimulus clears), the Display
//  must show no text overlays — only visual cues (X markers, wedges, ball, arrows).
//
//  Text overlays are allowed only:
//  - Between reps (`.waitingForNextRep`)
//  - Block/session complete (`.blockComplete` or `.complete`)
//  - Pre-session flows (Get Ready, countdown, calibration) — separate overlays, not gated here
//
//  Coach remote device has its own copy. Engine `instructionTitle` / `instructionSubtitle`
//  are cleared during mid-rep phases as a defensive measure.
//

enum DisplaySessionPlayerTextPolicy {
    static func showsBetweenRepPlayerText(for phase: OneTouchPassingPhase) -> Bool {
        switch phase {
        case .waitingForNextRep, .blockComplete:
            return true
        default:
            return false
        }
    }

    static func showsBetweenRepPlayerText(for phase: DribbleOrPassPhase) -> Bool {
        switch phase {
        case .waitingForNextRep, .blockComplete:
            return true
        default:
            return false
        }
    }

    static func showsBetweenRepPlayerText(for phase: AwayFromPressurePhase) -> Bool {
        switch phase {
        case .waitingForNextRep, .blockComplete:
            return true
        default:
            return false
        }
    }

    static func showsBetweenRepPlayerText(for phase: CriticalScanPhase) -> Bool {
        switch phase {
        case .waitingForNextRep, .complete:
            return true
        default:
            return false
        }
    }
}
