//
//  SoloLoopController.swift
//  FootballScanningAI
//
//  PBA V2 — Solo mode: auto-advance reps without coach input.
//

import Foundation
import Combine

/// Delays for the solo rep loop (seconds). Only **pre-beep** uses randomization; return / reset are fixed
/// for a consistent rhythm. Ball arrival for scoring uses ``returnTime`` via `CurrentSessionStore` (see display views).
struct SoloTimingSettings: Equatable {
    enum AutoloopAdvanceMode: Equatable {
        /// Legacy fixed timer between `runNextRep` calls.
        case continuous
        /// Quick style: schedule the next rep after `postRepAdvanceDelay` once the engine reaches `waitingForNextRep`.
        case afterRepCompletion
    }

    var preBeepMin: TimeInterval
    var preBeepMax: TimeInterval
    /// Fixed nominal “ball in flight” time (s); keep in sync with `CurrentSessionStore` override in solo autoloop.
    var returnTime: TimeInterval
    /// Fixed: cue should be readable this long before nominal arrival (perception lead).
    var decisionLeadTime: TimeInterval
    /// Fixed quiet gap after the return window before the next pre-beep can begin (continuous mode).
    var resetTime: TimeInterval
    var autoloopAdvanceMode: AutoloopAdvanceMode
    /// Quick style: delay after rep completion before the next pre-beep scan.
    var postRepAdvanceDelay: TimeInterval
    /// Time from pass/beep to when cues should be fully readable: `returnTime - decisionLeadTime`.
    var stimulusBeforeArrivalDelay: TimeInterval {
        max(0, returnTime - decisionLeadTime)
    }
    /// Wait after each `startRepSolo` callback before arming the next `scheduleNextRep` cycle.
    var postSoloTriggerScheduleDelay: TimeInterval {
        returnTime + resetTime
    }

    static let `default` = SoloTimingSettings(
        preBeepMin: UnifiedScanToBeepTiming.delayRangeSeconds.lowerBound,
        preBeepMax: UnifiedScanToBeepTiming.delayRangeSeconds.upperBound,
        returnTime: 1.1,
        decisionLeadTime: 0.4,
        resetTime: 2.0,
        autoloopAdvanceMode: .continuous,
        postRepAdvanceDelay: SoloTrainingStyle.quick.postRepAdvanceDelay
    )
}

/// Owns solo autoloop timers. Use `@StateObject` — never store this reference type in `@State`.
@MainActor
final class SoloLoopRunner: ObservableObject {
    @Published private(set) var isRunning = false

    private var runToken = UUID()
    private var settings = SoloTimingSettings.default
    private var pendingRunNextRep: (() -> Void)?
    private var postRepWorkItem: DispatchWorkItem?

    func start(settings: SoloTimingSettings, runNextRep: @escaping () -> Void) {
        stop()
        self.settings = settings
        pendingRunNextRep = runNextRep
        isRunning = true
        let token = runToken
        switch settings.autoloopAdvanceMode {
        case .continuous:
            scheduleNextRep(token: token, runNextRep: runNextRep)
        case .afterRepCompletion:
            runPreBeepCycle(token: token, runNextRep: runNextRep)
        }
    }

    /// Quick style: call when the engine settles on `waitingForNextRep` to schedule the next scan.
    func notifyRepWaitingForNext() {
        guard isRunning, settings.autoloopAdvanceMode == .afterRepCompletion else { return }
        guard let runNextRep = pendingRunNextRep else { return }
        postRepWorkItem?.cancel()
        let token = runToken
        let delay = settings.postRepAdvanceDelay
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.runToken == token else { return }
            self.runPreBeepCycle(token: token, runNextRep: runNextRep)
        }
        postRepWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func stop() {
        postRepWorkItem?.cancel()
        postRepWorkItem = nil
        pendingRunNextRep = nil
        runToken = UUID()
        isRunning = false
    }

    private func runPreBeepCycle(token: UUID, runNextRep: @escaping () -> Void) {
        guard isRunning, runToken == token else { return }

        let lo = min(settings.preBeepMin, settings.preBeepMax)
        let hi = max(settings.preBeepMin, settings.preBeepMax)
        let preBeepDelay = Double.random(in: lo...hi)

        DispatchQueue.main.asyncAfter(deadline: .now() + preBeepDelay) { [weak self] in
            guard let self, self.isRunning, self.runToken == token else { return }
            runNextRep()
        }
    }

    private func scheduleNextRep(token: UUID, runNextRep: @escaping () -> Void) {
        guard isRunning, runToken == token else { return }

        let lo = min(settings.preBeepMin, settings.preBeepMax)
        let hi = max(settings.preBeepMin, settings.preBeepMax)
        let preBeepDelay = Double.random(in: lo...hi)

        DispatchQueue.main.asyncAfter(deadline: .now() + preBeepDelay) { [weak self] in
            guard let self, self.isRunning, self.runToken == token else { return }

            runNextRep()

            let settleBeforeNextScan = self.settings.postSoloTriggerScheduleDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + settleBeforeNextScan) { [weak self] in
                guard let self, self.isRunning, self.runToken == token else { return }
                self.scheduleNextRep(token: token, runNextRep: runNextRep)
            }
        }
    }
}

extension SoloTimingSettings {
    /// Ensures a nominal travel is in the session store (does not clear an existing override from wall / pass-tempo calibration).
    static func applySoloAutoloopBallReturnToSessionStore() {
        if CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds == nil {
            let fallback = SoloWallCalibrationController.effectiveSoloWallReturnTimeSeconds()
                ?? SoloTimingSettings.default.returnTime
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(fallback)
        }
    }

    /// Build autoloop timing for a fixed wall return time (seconds).
    static func autoloopSettings(forReturnTime returnTime: TimeInterval) -> SoloTimingSettings {
        let s = SoloTimingSettings.default
        let rt = max(0.05, returnTime)
        return SoloTimingSettings(
            preBeepMin: s.preBeepMin,
            preBeepMax: s.preBeepMax,
            returnTime: rt,
            decisionLeadTime: s.decisionLeadTime,
            resetTime: s.resetTime,
            autoloopAdvanceMode: s.autoloopAdvanceMode,
            postRepAdvanceDelay: s.postRepAdvanceDelay
        )
    }

    /// Solo autoloop: sync calibrated wall return into `CurrentSessionStore` and build matching loop timing.
    static func soloAutoloopSettings(wallController: SoloWallCalibrationController) -> SoloTimingSettings {
        let rt = max(0.05, wallController.calibratedReturnTime)
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(rt)
        return soloAutoloopSettings(forReturnTime: rt, trainingStyle: SoloTimeBasedSession.trainingStyle)
    }

    /// Build autoloop timing from the current `CurrentSessionStore` override (or ``default`` return time if unset).
    static func autoloopSettingsFromSessionStore() -> SoloTimingSettings {
        let s = SoloTimingSettings.default
        let t = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds ?? s.returnTime
        return soloAutoloopSettings(forReturnTime: t, trainingStyle: SoloTimeBasedSession.trainingStyle)
    }

    static func soloAutoloopSettings(
        forReturnTime returnTime: TimeInterval,
        trainingStyle: SoloTrainingStyle?
    ) -> SoloTimingSettings {
        let base = autoloopSettings(forReturnTime: returnTime)
        let style = trainingStyle ?? SoloTrainingStyle.loadLastSelected()
        guard style.usesAutoloop else { return base }
        return SoloTimingSettings(
            preBeepMin: base.preBeepMin,
            preBeepMax: base.preBeepMax,
            returnTime: base.returnTime,
            decisionLeadTime: base.decisionLeadTime,
            resetTime: base.resetTime,
            autoloopAdvanceMode: .afterRepCompletion,
            postRepAdvanceDelay: style.postRepAdvanceDelay
        )
    }
}
