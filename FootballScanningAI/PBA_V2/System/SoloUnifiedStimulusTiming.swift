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

    /// Delay after the beep sound before opening the decision window / gating, using inline wall return calibration.
    static func stimulusDelayAfterBeepForSolo(returnTime: TimeInterval) -> TimeInterval {
        max(0.05, returnTime - decisionLeadTimeSeconds)
    }
}
