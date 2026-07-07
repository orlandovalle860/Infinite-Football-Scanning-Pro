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

    static func shouldEndAfterRep(
        mode: TrainingMode,
        timer: SoloSessionTimerController,
        isWaitingForNextRep: Bool
    ) -> Bool {
        mode == .solo && SoloTimeBasedSession.isActive && timer.pendingEndAfterCurrentRep && isWaitingForNextRep
    }
}
