//
//  SoloRepTiming.swift
//  FootballScanningAI
//
//  Solo within-rep timing: beep → decision window → synthetic pass / stimulus.
//  Replaces SoloUnifiedStimulusTiming.
//

import Foundation

struct SoloRepTiming {
    let returnTime: TimeInterval

    init(returnTime: TimeInterval) {
        self.returnTime = max(0.05, returnTime)
    }

    static func fromCalibration(_ returnTime: TimeInterval) -> SoloRepTiming {
        SoloRepTiming(returnTime: returnTime)
    }

    static let decisionLeadSeconds: TimeInterval = 0.35
    static let defaultTolerance: TimeInterval = 0.15

    var decisionStart: TimeInterval {
        returnTime - Self.decisionLeadSeconds
    }

    var windowStart: TimeInterval {
        returnTime - Self.defaultTolerance
    }

    var windowEnd: TimeInterval {
        returnTime + Self.defaultTolerance
    }

    func isWithinWindow(elapsed: TimeInterval) -> Bool {
        elapsed >= windowStart && elapsed <= windowEnd
    }

    func acceptsPass(at now: Date, beepTime: Date) -> Bool {
        let elapsed = now.timeIntervalSince(beepTime)
        return isWithinWindow(elapsed: elapsed)
    }
}
