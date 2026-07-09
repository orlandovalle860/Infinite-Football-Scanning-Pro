//
//  SessionStartCueRepGate.swift
//  FootballScanningAI
//
//  Rep-engine lifecycle: instruction overlay, post-instruction buffer, first-rep guard.
//  Session teardown runs only via endSession(reason:) — not display onDisappear during activity switches.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum SessionExitReason: String {
    case userEnd
    case timerExpired
    case leftSessionContainer
    case drillSurfaceDismissed
    case sessionCleared
    case partnerDisconnected
    case appBackgrounded
}

@MainActor
enum SessionStartCueRepGate {
    /// Pause after instructional text dismisses before the first rep/beep (solo + partner, all activities).
    static let instructionToRepDelay: TimeInterval = 0.5

    private(set) static var isAppActive = true
    private(set) static var isInSessionContainer = false
    private(set) static var sessionIsActive = false
    private(set) static var repEngineCanStart = false
    private static var isAwaitingPostInstructionDelay = false
    private static var hasStartedFirstRep = false
    private static var pendingResumeWorkItem: DispatchWorkItem?
    private static var needsForegroundReconciliation = false
    private static var isPerformingForegroundReconciliation = false
    /// Partner Train Again: skip per-surface `prepareDrillSurface` until bootstrap completes.
    private(set) static var isPartnerTrainAgainBootstrapping = false
    /// Set only by `UIApplication.didEnterBackgroundNotification` — never by `.inactive` or `willResignActive`.
    private static var didEnterBackground = false

    private static func ensureLifecycleObservers() {
#if canImport(UIKit)
        SessionStartCueRepGateLifecycleMonitor.bootstrap()
#endif
    }

    // MARK: - Session lifecycle (explicit exit only)

    /// Timed session container appeared — session stays active across activity switches inside the container.
    static func beginSessionContainer() {
        ensureLifecycleObservers()
        let wasInContainer = isInSessionContainer
        isInSessionContainer = true
        sessionIsActive = true
        guard !wasInContainer else { return }
        repEngineCanStart = false
        hasStartedFirstRep = false
        isAwaitingPostInstructionDelay = false
        cancelPendingResume()
    }

    /// Sole entry point for session teardown (finish, timer, leave container, legacy drill dismiss).
    static func endSession(reason: SessionExitReason) {
        _ = reason
        isInSessionContainer = false
        sessionIsActive = false
        repEngineCanStart = false
        hasStartedFirstRep = false
        needsForegroundReconciliation = false
        isPerformingForegroundReconciliation = false
        didEnterBackground = false
        cancelPendingResume()
    }

    /// A drill display surface appeared — reset per-activity rep state without ending the timed session.
    static func onDrillSurfaceAppeared() {
        ensureLifecycleObservers()
        if isInSessionContainer {
            prepareDrillSurface()
        } else {
            activateStandaloneDrillSession()
        }
    }

    /// Drill surface removed. Only ends session when not inside the timed session container.
    static func onDrillSurfaceDisappeared() {
        guard !isInSessionContainer else { return }
        endSession(reason: .drillSurfaceDismissed)
    }

    /// Standalone drill (legacy / partner direct route) — not wrapped in TimedSessionContainerView.
    private static func activateStandaloneDrillSession() {
        isInSessionContainer = false
        sessionIsActive = true
        prepareDrillSurface()
    }

    private static var repEngineMutationsAllowed: Bool {
        if isInSessionContainer {
            return TimedSessionController.shared.canAcceptSessionMutations
        }
        return sessionIsActive
    }

    /// New activity surface within an ongoing session — instruction / first-rep state only.
    static func prepareDrillSurface() {
        guard !isPartnerTrainAgainBootstrapping else { return }
        guard repEngineMutationsAllowed else { return }
        repEngineCanStart = false
        hasStartedFirstRep = false
        isAwaitingPostInstructionDelay = false
        cancelPendingResume()
    }

    // MARK: - App lifecycle

    /// Display views call from `onChange(of: scenePhase)`. Ignores `.inactive` and `.background`.
    static func noteScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            applicationDidBecomeActive()
        case .background, .inactive:
            break
        @unknown default:
            break
        }
    }

    /// One-shot after a true background → active transition. Not set by `.inactive` (screenshots).
    static func consumeDidEnterBackground() -> Bool {
        guard didEnterBackground else { return false }
        didEnterBackground = false
        return true
    }

    /// UIApplication.didEnterBackground only — not `willResignActive` or `.inactive`.
    static func handleDidEnterBackgroundNotification() {
        didEnterBackground = true
        isAppActive = false
        isPerformingForegroundReconciliation = false
        guard sessionIsActive, !hasStartedFirstRep else { return }
        needsForegroundReconciliation = true
        cancelPendingResume()
    }

    static func applicationDidBecomeActive() {
        isAppActive = true
    }

    /// Returns `true` only when the drill view should replay its pre-first-rep flow.
    /// One-shot: the pending flag is consumed immediately so rapid state changes cannot re-enter partially.
    static func consumeForegroundReconciliation(instructionVisible: Bool) -> Bool {
        // Foreground reconciliation only applies before the first rep.
        // After first rep begins, session resumes naturally without replay.
        if hasStartedFirstRep {
            needsForegroundReconciliation = false
            return false
        }

        guard !isPerformingForegroundReconciliation else { return false }

        let shouldReconcile = needsForegroundReconciliation
        needsForegroundReconciliation = false
        guard shouldReconcile else { return false }
        guard sessionIsActive else { return false }
        if isInSessionContainer, !TimedSessionController.shared.canAcceptSessionMutations {
            return false
        }

        isPerformingForegroundReconciliation = true
        defer { isPerformingForegroundReconciliation = false }

        if instructionVisible {
            cancelPendingResume()
            repEngineCanStart = false
            return false
        }

        prepareDrillSurface()
        return true
    }

    // MARK: - Rep engine gating

    /// Final safety check before beeps, autoloop, or coach `nextRep` handlers run.
    static func canStartRepEngine(instructionVisible: Bool) -> Bool {
        guard repEngineMutationsAllowed else { return false }
        guard isAppActive else { return false }
        guard sessionIsActive else { return false }
        guard repEngineCanStart else { return false }
        guard !instructionVisible else { return false }
        guard !isAwaitingPostInstructionDelay else { return false }
        return true
    }

    /// Allow rep timing when there is no instructional overlay path (or after it completes).
    static func enableRepEngine() {
        guard repEngineMutationsAllowed else { return }
        guard sessionIsActive, isAppActive else { return }
        repEngineCanStart = true
        notifyPartnerDisplayRepEngineReadyIfNeeded()
    }

    /// While instructions are visible (or the post-instruction buffer is active), hold the coach `nextRep`.
    /// - Returns: `true` when the rep was deferred.
    static func deferCoachNextRepIfNeeded(
        repIndex: Int,
        instructionVisible: Bool,
        pending: inout Int?
    ) -> Bool {
        guard canStartRepEngine(instructionVisible: instructionVisible) else {
            pending = repIndex
            return true
        }
        return false
    }

    /// Call when the session-start instructional overlay finishes. Rep engine resumes after ``instructionToRepDelay``.
    static func scheduleRepEngineResume(perform: @escaping @MainActor () -> Void) {
        guard repEngineMutationsAllowed else { return }
        pendingResumeWorkItem?.cancel()
        isAwaitingPostInstructionDelay = true
        repEngineCanStart = false

        let work = DispatchWorkItem { @MainActor in
            isAwaitingPostInstructionDelay = false
            pendingResumeWorkItem = nil

            guard repEngineMutationsAllowed else { return }
            guard isAppActive else { return }
            guard sessionIsActive else { return }
            guard !hasStartedFirstRep else { return }

            repEngineCanStart = true
            notifyPartnerDisplayRepEngineReadyIfNeeded()
            perform()
        }
        pendingResumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + instructionToRepDelay, execute: work)
    }

    /// Prevents duplicate first-rep triggers from delayed resume racing with other starters.
    /// - Returns: `true` when this call may proceed with the first rep cycle.
    static func claimFirstRepStart() -> Bool {
        guard repEngineMutationsAllowed else { return false }
        guard isAppActive else { return false }
        guard sessionIsActive, repEngineCanStart else { return false }
        guard !hasStartedFirstRep else { return false }
        hasStartedFirstRep = true
        return true
    }

    /// Partner display: rep engine passed instruction / post-cue buffer — safe to notify coach.
    static var shouldBroadcastDisplayRepEngineReady: Bool {
        guard sessionIsActive, repEngineCanStart else { return false }
        guard !isAwaitingPostInstructionDelay else { return false }
        return true
    }

    private static func notifyPartnerDisplayRepEngineReadyIfNeeded() {
        guard shouldBroadcastDisplayRepEngineReady else { return }
        guard TimedSessionController.shared.mode == .partner else { return }
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard !TrainingPartnerConnectionCoordinator.shared.isPartnerDisplayCountdownActive else { return }
        guard let activity = TimedSessionController.shared.currentActivity else { return }
        TrainingPartnerConnectionCoordinator.shared.broadcastDisplayRepEngineReadyFromDisplay(activity: activity)
    }

    static func cancelPendingResume() {
        pendingResumeWorkItem?.cancel()
        pendingResumeWorkItem = nil
        isAwaitingPostInstructionDelay = false
    }

    /// Partner timed Train Again — still inside ``TimedSessionContainerView``; reset per-session rep state.
    static func preparePartnerTimedTrainAgain() {
        ensureLifecycleObservers()
        isInSessionContainer = true
        sessionIsActive = true
        isPartnerTrainAgainBootstrapping = true
        repEngineCanStart = false
        hasStartedFirstRep = false
        isAwaitingPostInstructionDelay = false
        cancelPendingResume()
    }

    /// Partner Train Again failed before bootstrap finished — do not unlock coach/rep engine.
    static func abortPartnerTrainAgainBootstrap() {
        isPartnerTrainAgainBootstrapping = false
    }

    /// After partner Train Again, instruction was already shown — unlock reps; coach notify on drill surface appear.
    static func completePartnerTimedTrainAgain() {
        guard sessionIsActive else {
            #if DEBUG
            print("[TimedSession] completePartnerTimedTrainAgain skipped — gate session inactive")
            #endif
            isPartnerTrainAgainBootstrapping = false
            return
        }
        TimedSessionController.shared.markPartnerSessionStartChromeCompleted()
        isPartnerTrainAgainBootstrapping = false
        repEngineCanStart = true
        hasStartedFirstRep = false
        isAwaitingPostInstructionDelay = false
    }

    /// Timed partner activity switch / Train Again: skip countdown + instruction; notify coach when surface is live.
    static func fastPathPartnerTimedActivitySurfaceReady() {
        guard TimedSessionDisplayIntegration.usesSharedSession else { return }
        guard TimedSessionController.shared.mode == .partner else { return }
        guard TimedSessionController.shared.partnerSessionStartChromeCompleted else { return }
        guard repEngineMutationsAllowed else { return }
        repEngineCanStart = true
        hasStartedFirstRep = false
        isAwaitingPostInstructionDelay = false
        cancelPendingResume()
        notifyPartnerDisplayRepEngineReadyIfNeeded()
    }
}

#if canImport(UIKit)
private enum SessionStartCueRepGateLifecycleMonitor {
    private static let registered: Bool = {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SessionStartCueRepGate.handleDidEnterBackgroundNotification()
                TimedSessionController.shared.abandonSessionDueToAppLifecycle()
            }
        }
        center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                TimedSessionController.shared.abandonSessionDueToAppLifecycle()
            }
        }
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SessionStartCueRepGate.applicationDidBecomeActive()
            }
        }
        return true
    }()

    static func bootstrap() {
        _ = registered
    }
}
#endif
