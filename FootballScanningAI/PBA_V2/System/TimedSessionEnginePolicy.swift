//
//  TimedSessionEnginePolicy.swift
//  FootballScanningAI
//
//  Explicit timed vs rep-budget engine behavior — no artificial high rep limits.
//

import Foundation

@MainActor
enum TimedSessionEnginePolicy {
    // Number of reps per engine cycle during timed sessions.
    // Engine loops continuously; this only controls cycle chunk size.
    static let timedSessionBlockSize: Int = 12

    // Two-Minute Test uses a smaller rep chunk for drill rhythm.
    // This does NOT affect session duration or save behavior.
    static let twoMinuteTestEngineChunkSize: Int = 10

    static var isTimedSession: Bool {
        TimedSessionController.shared.isManagingSession && SoloTimeBasedSession.isActive
    }

    /// Timed sessions loop engine plans until the session timer ends or the user taps End.
    static var runEngineContinuously: Bool {
        SoloTimeBasedSession.isActive
    }

    /// Plan size for scenario generation at view/engine init.
    /// Rep chunk size only — never used for session timer, ``finishSession()``, or save rep totals.
    static func enginePlanBlockSize(
        activityId: String,
        soloFallback: Int,
        mode: TrainingMode
    ) -> Int {
        if runEngineContinuously {
            return timedEngineChunkRepCount(for: activityId)
        }
        if activityId == ActivityKind.twoMinuteTest.sessionActivityActivityId {
            return twoMinuteTestEngineChunkSize
        }
        return repBudgetBlockSize(activityId: activityId, soloFallback: soloFallback, mode: mode)
    }

    /// Per-activity engine cycle size during timed sessions (session length is timer-driven).
    private static func timedEngineChunkRepCount(for activityId: String) -> Int {
        if activityId == ActivityKind.twoMinuteTest.sessionActivityActivityId {
            return twoMinuteTestEngineChunkSize
        }
        return timedSessionBlockSize
    }

    /// Legacy rep-budget sessions (non-timed container).
    static func repBudgetBlockSize(
        activityId: String,
        soloFallback: Int,
        mode: TrainingMode
    ) -> Int {
        TrainingPartnerConnectionCoordinator.shared.partnerBlockTotalReps(
            activityId: activityId,
            soloFallback: soloFallback,
            mode: mode
        )
    }

    /// Supabase `block_size` at session create — not a runtime rep cap for timed sessions.
    static var supabaseSessionBlockSize: Int {
        timedSessionBlockSize
    }
}
