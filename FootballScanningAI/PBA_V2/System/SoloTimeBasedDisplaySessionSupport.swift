//
//  SoloTimeBasedDisplaySessionSupport.swift
//  FootballScanningAI
//
//  Shared helpers for time-based solo display sessions (timer, session end, rep budget).
//

import SwiftUI

enum SoloTimeBasedDisplaySessionSupport {
    static func effectiveUsesAutoLoop(mode: TrainingMode) -> Bool {
        guard mode == .solo else { return mode.usesAutoLoop }
        return SoloTimeBasedSession.usesAutoloop
    }

    static func notifyQuickRepAdvanceIfNeeded(mode: TrainingMode, soloLoopRunner: SoloLoopRunner) {
        guard mode == .solo, SoloTimeBasedSession.usesAutoloop else { return }
        soloLoopRunner.notifyRepWaitingForNext()
    }

    static func recordRepIfNeeded(
        mode: TrainingMode,
        recordedRepTokens: inout Set<String>,
        repIndex: Int,
        activity: ActivityKind,
        lifetimeDisplayCount: inout Int
    ) {
        TimedSessionDisplayIntegration.recordSessionRepIfNeeded(
            activityId: activity.sessionActivityActivityId,
            repIndex: repIndex,
            recordedRepTokens: &recordedRepTokens
        )
        guard mode == .solo else { return }
        lifetimeDisplayCount = SoloLifetimeRepCounter.recordRep(for: activity)
    }

    static func freeModeEndAction(mode: TrainingMode, endSession: @escaping () -> Void) -> (() -> Void)? {
        guard mode == .solo, SoloTimeBasedSession.config == .free else { return nil }
        return endSession
    }

    static func startTimerIfNeeded(
        mode: TrainingMode,
        timer: SoloSessionTimerController
    ) {
        guard mode == .solo, SoloTimeBasedSession.isActive, let config = SoloTimeBasedSession.config else { return }
        guard !timer.isVisible else { return }
        timer.start(choice: config)
    }

    /// After solo wall calibration is ready (cached or inline), start the session timer and try autoloop when applicable.
    /// Action mode does not autoloop; this still starts the timer so cached-calibration boots are not stuck behind autoloop.
    static func onSoloCalibrationReady(
        mode: TrainingMode,
        hasCompletedCalibration: Bool,
        isCalibrating: Bool,
        timer: SoloSessionTimerController,
        tryAutoloop: () -> Void = {}
    ) {
        guard mode == .solo else { return }
        guard hasCompletedCalibration else { return }
        guard !isCalibrating else { return }
        guard SoloSessionUserStartGate.hasConfirmedUserStart else { return }
        startTimerIfNeeded(mode: mode, timer: timer)
        tryAutoloop()
    }

    static func shouldEndAfterRep(
        mode: TrainingMode,
        timer: SoloSessionTimerController,
        isWaitingForNextRep: Bool
    ) -> Bool {
        if TimedSessionDisplayIntegration.usesSharedSession {
            return timer.pendingEndAfterCurrentRep && isWaitingForNextRep
        }
        return mode == .solo && SoloTimeBasedSession.isActive && timer.pendingEndAfterCurrentRep && isWaitingForNextRep
    }

    /// Best available completed-rep count for the session-complete overlay.
    static func overlayRepCount(engineLoggedRepCount: Int) -> Int {
        if TimedSessionDisplayIntegration.usesSharedSession {
            return TimedSessionDisplayIntegration.sharedRepCount
        }
        return engineLoggedRepCount
    }

    static func shouldBlockSoloDrillInput(isEnding: Bool, showComplete: Bool) -> Bool {
        isEnding || showComplete
    }

    /// Resets display rep cursor/controller when the engine begins a new timed-session chunk.
    /// Matches the rep-state portion of drill ``runItBackFromSummary`` without block-summary UI teardown.
    /// - Important: ``resetPartnerCoachRepGate`` must **reassign** the `@State` gate (e.g. `gate = PartnerCoachRepSequenceGate()`),
    ///   not only call `reset()` in place — otherwise partner `nextRep(0)` after a 10/12 chunk is treated as stale.
    static func resetDisplayRepStateForEngineChunkRestart(
        mode: TrainingMode,
        setNextRepIndex: (Int) -> Void,
        setPendingNextRepIndex: (Int?) -> Void,
        resetRepController: () -> Void,
        resetPartnerCoachRepGate: (() -> Void)? = nil,
        clearPendingNextRep: Bool = true
    ) {
        setNextRepIndex(0)
        if clearPendingNextRep {
            setPendingNextRepIndex(nil)
        }
        resetRepController()
        if mode.requiresPhoneDisplayRelay {
            resetPartnerCoachRepGate?()
        }
    }

    /// Partner free-train: coach advances on PASS of the last chunk rep and may send `nextRep(0)` while the
    /// display is still mid-rep or stuck with `currentRepIndex` from the previous chunk. Without a full
    /// engine restart, `tryCommit` rejects `0 < currentRepIndex` and the coach loops TAP TO START forever.
    static func shouldRestartEngineForPartnerCoachChunkWrap(
        repIndex: Int,
        expectedNextCoachRepIndex: Int,
        engineCurrentRepIndex: Int,
        isTerminalPhase: Bool,
        chunkSize: Int
    ) -> Bool {
        guard TimedSessionDisplayIntegration.shouldLoopEngineChunks else { return false }
        guard repIndex == 0, chunkSize > 0 else { return false }
        if isTerminalPhase { return true }
        if expectedNextCoachRepIndex >= chunkSize { return true }
        // Gate was already wrap-reset to 0, but engine never restarted (failed mid-rep force-ready path).
        if expectedNextCoachRepIndex == 0 && engineCurrentRepIndex > 0 { return true }
        return false
    }

    /// Allow coach `nextRep(0)` after a chunk wrap even when the engine cursor is still on the prior rep.
    static func allowsPartnerCoachChunkWrapNextRep(
        repIndex: Int,
        engineCurrentRepIndex: Int
    ) -> Bool {
        TimedSessionDisplayIntegration.shouldLoopEngineChunks
            && repIndex == 0
            && engineCurrentRepIndex > 0
    }
}
