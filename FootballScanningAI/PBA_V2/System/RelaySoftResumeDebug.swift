//
//  RelaySoftResumeDebug.swift
//  FootballScanningAI
//
//  DEBUG: soft-resume / grace-window tracing (Release builds: no-op).
//

import Foundation

enum RelaySoftResumeDebug {
    private static let prefix = "[SoftResume-Debug]"

    static func logInterruptionStart(at date: Date) {
        #if DEBUG
        print("\(prefix) interruption_start timestamp=\(date.timeIntervalSince1970)")
        #endif
    }

    static func logInterruptionResume(duration: TimeInterval, graceSeconds: TimeInterval, eligible: Bool) {
        #if DEBUG
        print("\(prefix) interruption_duration_seconds=\(String(format: "%.2f", duration)) grace_window_seconds=\(String(format: "%.1f", graceSeconds)) soft_resume_eligible=\(eligible)")
        #endif
    }

    static func logReconnectOutcome(success: Bool, detail: String) {
        #if DEBUG
        print("\(prefix) reconnect success=\(success) detail=\(detail)")
        #endif
    }

    static func logSessionValidation(passed: Bool, detail: String) {
        #if DEBUG
        print("\(prefix) session_validation passed=\(passed) detail=\(detail)")
        #endif
    }

    static func logCheckpointComparison(displayRep: Int, coachRep: Int, relaySessionMatch: Bool, activityMatch: Bool) {
        #if DEBUG
        print("\(prefix) checkpoint_comparison displayRep=\(displayRep) coachRep=\(coachRep) relaySessionIdMatch=\(relaySessionMatch) activityMatch=\(activityMatch)")
        #endif
    }

    static func logSoftResumeOutcome(success: Bool, reason: String) {
        #if DEBUG
        print("\(prefix) soft_resume success=\(success) reason=\(reason)")
        #endif
    }

    static func logFallbackToRejoin(reason: String) {
        #if DEBUG
        print("\(prefix) fallback_to_rejoin reason=\(reason)")
        #endif
    }
}
