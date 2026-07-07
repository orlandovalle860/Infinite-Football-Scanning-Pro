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
        recordedRepIndices: inout Set<Int>,
        repIndex: Int,
        activity: ActivityKind,
        lifetimeDisplayCount: inout Int
    ) {
        guard mode == .solo else { return }
        guard recordedRepIndices.insert(repIndex).inserted else { return }
        if SoloTimeBasedSession.isActive {
            SoloTimeBasedSession.recordRepCompleted()
        }
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
        startTimerIfNeeded(mode: mode, timer: timer)
        tryAutoloop()
    }

    static func shouldEndAfterRep(
        mode: TrainingMode,
        timer: SoloSessionTimerController,
        isWaitingForNextRep: Bool
    ) -> Bool {
        mode == .solo && SoloTimeBasedSession.isActive && timer.pendingEndAfterCurrentRep && isWaitingForNextRep
    }

    /// Best available completed-rep count for the session-complete overlay.
    static func overlayRepCount(engineLoggedRepCount: Int) -> Int {
        max(SoloTimeBasedSession.sessionRepCount, engineLoggedRepCount)
    }

    static func shouldBlockSoloDrillInput(isEnding: Bool, showComplete: Bool) -> Bool {
        isEnding || showComplete
    }
}
