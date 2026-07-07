//
//  SoloUnifiedStimulusTiming.swift
//  FootballScanningAI
//
//  Solo-only: time from beep to “stimulus on” = calibrated return time minus a fixed perception lead.
//  Partner / coach modes do not use this (each activity keeps its own playBeep path).
//

import Foundation

enum SoloUnifiedStimulusTiming {
    /// How long before nominal ball return the cue should be fully readable.
    static let decisionLeadTimeSeconds: TimeInterval = 0.35

    /// Alias for ``decisionLeadTimeSeconds`` — decision window opens at `returnTime - decisionStartOffset`.
    static let decisionStartOffset: TimeInterval = decisionLeadTimeSeconds

    /// Solo pass / wall interaction tolerance by activity (seconds around nominal ``returnTime``).
    static func tolerance(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .twoMinuteTest: return 0.15
        case .dribbleOrPass, .awayFromPressure, .oneTouchPassing: return 0.15
        }
    }

    /// Inclusive interaction window offsets from beep: `[returnTime - tolerance, returnTime + tolerance]`.
    static func interactionWindow(returnTime: TimeInterval, tolerance: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        let start = max(0, returnTime - tolerance)
        let end = returnTime + tolerance
        return (start, end)
    }

    /// Whether a solo pass / wall tap at `now` falls within the tolerance window after `beepTime`.
    static func acceptsSoloPassInteraction(
        at now: Date,
        beepTime: Date?,
        returnTime: TimeInterval,
        activity: ActivityKind
    ) -> Bool {
        guard let beepTime else { return false }
        let tol = tolerance(for: activity)
        let window = interactionWindow(returnTime: max(0.05, returnTime), tolerance: tol)
        let elapsed = now.timeIntervalSince(beepTime)
        return elapsed >= window.start && elapsed <= window.end
    }

    /// Delay after the beep sound before opening the decision window / gating, using inline wall return calibration.
    static func stimulusDelayAfterBeepForSolo(returnTime: TimeInterval) -> TimeInterval {
        max(0.05, returnTime - decisionLeadTimeSeconds)
    }
}
