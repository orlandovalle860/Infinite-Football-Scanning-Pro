//
//  TimedSessionDisplayIntegration.swift
//  FootballScanningAI
//
//  Hooks display session views into the shared TimedSessionController (solo + partner).
//

import SwiftUI

extension Notification.Name {
    static let timedSessionEndRequested = Notification.Name("TimedSessionEndRequested")
    static let timedSessionSwitchActivity = Notification.Name("TimedSessionSwitchActivity")
    static let coachEndTimedSessionRequested = Notification.Name("CoachEndTimedSessionRequested")
    static let partnerTimedSessionEndedFromDisplay = Notification.Name("PartnerTimedSessionEndedFromDisplay")
    /// Coach phone: display finished Train Again bootstrap — reset TAP TO START / rep index.
    static let partnerDisplayRepEngineBecameReady = Notification.Name("PartnerDisplayRepEngineBecameReady")
}

enum TimedSessionDisplayIntegration {
    static var controller: TimedSessionController { TimedSessionController.shared }

    static var usesSharedSession: Bool {
        TimedSessionEnginePolicy.isTimedSession
    }

    static var runEngineContinuously: Bool {
        TimedSessionEnginePolicy.runEngineContinuously
    }

    /// Display should restart engine chunks when either the timed session loops or the partner coach remote wraps (10/12).
    static var shouldLoopEngineChunks: Bool {
        runEngineContinuously || coachRemoteLoopsEngineChunks
    }

    static var sessionMode: TrainingMode {
        usesSharedSession ? controller.mode : PBASessionFlowPolicy.lastSelectedTrainingMode()
    }

    static func sessionTimer(local: SoloSessionTimerController) -> SoloSessionTimerController {
        usesSharedSession ? controller.sessionTimer : local
    }

    static func timerDisplayText(local: SoloSessionTimerController) -> String {
        usesSharedSession ? controller.timerDisplayText : local.presentationText
    }

    static func showsSessionTimerOverlay(mode: TrainingMode, isCalibrating: Bool, localTimer: SoloSessionTimerController) -> Bool {
        guard !isCalibrating else { return false }
        if usesSharedSession { return false }
        guard mode == .solo, SoloTimeBasedSession.isActive else { return false }
        return localTimer.isVisible
    }

    /// Block-local "Rep X of Y" chrome — hidden when the timed session container owns the rep counter.
    static func showsBlockRepProgressOverlay(mode: TrainingMode) -> Bool {
        guard mode != .solo else { return false }
        return !usesSharedSession
    }

    /// Coach remote block rep header — partner sessions are timer-driven, not fixed 12-rep blocks.
    static var showsCoachBlockRepProgress: Bool { false }

    /// Coach rep taps / haptics only after the display timed session is live.
    static var coachRemoteRepControlEnabled: Bool {
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        if coordinator.isPartnerTrainingSessionActive {
            return coordinator.currentTimedSessionActivityId != nil
                && coordinator.isDisplayRepEngineReady
        }
        if TimedSessionController.shared.isSessionActive {
            return true
        }
        return false
    }

    /// Timed partner coach remotes loop engine chunks (10/12 reps) until the session timer ends — no block-complete screen.
    static var coachRemoteLoopsEngineChunks: Bool {
        TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
    }

    /// Timed partner: skip 3–2–1–Go on activity switches and Train Again (first activity only).
    static func shouldSkipPartnerSessionStartCue(mode: TrainingMode) -> Bool {
        guard mode == .partner, usesSharedSession else { return false }
        return controller.partnerSessionStartChromeCompleted
    }

    static func showsPartnerSessionStartCountdown(mode: TrainingMode, effectiveUsesAutoLoop: Bool) -> Bool {
        guard !effectiveUsesAutoLoop, mode.requiresPhoneDisplayRelay else { return false }
        if usesSharedSession {
            return !controller.partnerSessionStartChromeCompleted
        }
        return true
    }

    static func markPartnerSessionStartChromeCompletedIfNeeded(mode: TrainingMode) {
        guard mode == .partner, usesSharedSession else { return }
        controller.markPartnerSessionStartChromeCompleted()
    }

    /// Activity switch / Train Again: unlock coach TAP TO START without re-running countdown + instruction.
    static func fastPathPartnerTimedDrillSurfaceIfNeeded(
        mode: TrainingMode,
        partnerDrillReady: Bool
    ) {
        guard partnerDrillReady else { return }
        guard shouldSkipPartnerSessionStartCue(mode: mode) else { return }
        SessionStartCueRepGate.fastPathPartnerTimedActivitySurfaceReady()
    }

    static func partnerTimedDrillSurfaceReady(
        mode: TrainingMode,
        coachConnectedForCalibration: Bool,
        hasCompletedPassTempoCalibration: Bool,
        showPassTempoCalibration: Bool,
        showConnectedConfirmation: Bool
    ) -> Bool {
        guard mode.requiresPhoneDisplayRelay else { return true }
        return coachConnectedForCalibration
            && hasCompletedPassTempoCalibration
            && !showPassTempoCalibration
            && !showConnectedConfirmation
    }

    /// Legacy fixed-block “Block complete” chrome — hidden for timer-driven partner coach remotes.
    static var coachRemoteShowsBlockCompleteUI: Bool {
        !coachRemoteLoopsEngineChunks
    }

    /// After a logged rep, returns the next 0-based coach rep index, or `nil` when the legacy block should complete.
    static func coachRemoteNextRepIndexAfterPass(completedRepIndex: Int, chunkSize: Int) -> Int? {
        let next = completedRepIndex + 1
        if next >= chunkSize {
            return coachRemoteLoopsEngineChunks ? 0 : nil
        }
        return next
    }

    static func coachRemoteWrapRepIndex(_ index: Int, chunkSize: Int) -> Int {
        guard chunkSize > 0, coachRemoteLoopsEngineChunks else { return index }
        return index % chunkSize
    }

    static var canResumeRepEngine: Bool {
        !usesSharedSession || controller.canAcceptSessionMutations
    }

    static func onCalibrationReady(
        mode: TrainingMode,
        hasCompletedCalibration: Bool,
        isCalibrating: Bool,
        localTimer: SoloSessionTimerController,
        tryAutoloop: () -> Void
    ) {
        guard hasCompletedCalibration else { return }
        guard !isCalibrating else { return }
        if usesSharedSession {
            guard controller.canAcceptSessionMutations else { return }
            controller.onCalibrationReadyForCurrentActivity()
        } else if mode == .solo {
            SoloTimeBasedDisplaySessionSupport.onSoloCalibrationReady(
                mode: mode,
                hasCompletedCalibration: hasCompletedCalibration,
                isCalibrating: isCalibrating,
                timer: localTimer,
                tryAutoloop: tryAutoloop
            )
            return
        } else {
            return
        }
        tryAutoloop()
    }

    /// Call before resuming reps after instruction dismiss or engine plan restart.
    static func resumeRepEngineAfterInstructionDismissedIfAllowed(_ resume: () -> Void) {
        guard canResumeRepEngine else { return }
        resume()
    }

    static func registerActivitySegment(
        activity: ActivityKind,
        skipSessionCreation: () -> Void,
        createSession: () -> Void
    ) {
        if controller.shouldSkipActivitySessionCreation {
            controller.prepareActivitySegment(activity: activity)
            Task { await controller.ensureSupabaseActivitySegmentIfNeeded(for: activity) }
            return
        }
        createSession()
    }

    static func finishTimeBasedSession(
        mode: TrainingMode,
        showComplete: Bool,
        completionType: SessionCompletionType,
        freeze: () -> Void,
        localFinish: () -> Void
    ) {
        guard SoloTimeBasedSession.isActive, !showComplete else { return }
        if usesSharedSession {
            freeze()
            controller.finishSession(completionType: completionType)
            return
        }
        guard mode == .solo else { return }
        localFinish()
    }

    static func requestUserEnd(
        mode: TrainingMode,
        showComplete: Bool,
        isEnding: Bool,
        completionType: SessionCompletionType,
        freeze: @escaping () -> Void,
        localEnd: () -> Void
    ) {
        guard SoloTimeBasedSession.isActive, !showComplete, !isEnding else { return }
        if usesSharedSession {
            controller.requestEnd(
                completionType: controller.userInitiatedEndCompletionType,
                freeze: freeze
            )
            return
        }
        guard mode == .solo else { return }
        localEnd()
    }

    static var shouldDeferCompletionOverlay: Bool {
        usesSharedSession
    }

    /// When true, activity views must not navigate to block summary on blockComplete.
    static var suppressBlockSummaryNavigation: Bool {
        usesSharedSession
    }

    static var allowsBlockSummaryNavigation: Bool {
        !usesSharedSession
    }

    static var sharedRepCount: Int {
        controller.totalRepCount
    }

    static var sharedTimerDisplayText: String {
        controller.timerDisplayText
    }

    /// Timed sessions continue after an engine plan completes — timer drives exit, not rep blocks.
    static func continueAfterEnginePlanComplete(
        restartEngineBlock: () -> Void,
        resumeReps: () -> Void
    ) -> Bool {
        // Partner coach remotes wrap at chunk size even when display restart must still run;
        // require an active timed session mutation window so we never loop a finished/locked session.
        guard shouldLoopEngineChunks, controller.canAcceptSessionMutations else { return false }
        controller.advanceCycleIfNeeded()
        restartEngineBlock()
        resumeReps()
        return true
    }

    static func recordSessionRepIfNeeded(
        activityId: String,
        repIndex: Int,
        recordedRepTokens: inout Set<String>
    ) {
        guard SoloTimeBasedSession.isActive, controller.isManagingSession else { return }
        guard controller.canAcceptSessionMutations else { return }

        if usesSharedSession {
            controller.recordRepIfNeeded(activityId: activityId, repIndex: repIndex)
            return
        }

        guard let token = controller.repDedupeToken(for: repIndex) else { return }
        guard recordedRepTokens.insert(token).inserted else { return }
        controller.recordRepIfNeeded(activityId: activityId, repIndex: repIndex)
    }
}

extension View {
    func onTimedSessionContainerEnd(perform: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .timedSessionEndRequested)) { _ in
            perform()
        }
    }
}
