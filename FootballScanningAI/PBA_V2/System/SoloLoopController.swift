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
    var preBeepMin: TimeInterval
    var preBeepMax: TimeInterval
    /// Fixed nominal “ball in flight” time (s); keep in sync with `CurrentSessionStore` override in solo autoloop.
    var returnTime: TimeInterval
    /// Fixed: cue should be readable this long before nominal arrival (perception lead).
    var decisionLeadTime: TimeInterval
    /// Fixed quiet gap after the return window before the next pre-beep can begin.
    var resetTime: TimeInterval
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
        resetTime: 2.0
    )
}

/// Owns solo autoloop timers. Use `@StateObject` — never store this reference type in `@State`.
@MainActor
final class SoloLoopRunner: ObservableObject {
    @Published private(set) var isRunning = false

    private var runToken = UUID()
    private var settings = SoloTimingSettings.default

    func start(settings: SoloTimingSettings, runNextRep: @escaping () -> Void) {
        stop()
        self.settings = settings
        isRunning = true
        let token = runToken
        scheduleNextRep(token: token, runNextRep: runNextRep)
    }

    func stop() {
        runToken = UUID()
        isRunning = false
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
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(SoloTimingSettings.default.returnTime)
        }
    }

    /// Build autoloop timing from the current `CurrentSessionStore` override (or ``default`` return time if unset).
    static func autoloopSettingsFromSessionStore() -> SoloTimingSettings {
        let s = SoloTimingSettings.default
        let t = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds ?? s.returnTime
        let returnTime = max(0.05, t)
        return SoloTimingSettings(
            preBeepMin: s.preBeepMin,
            preBeepMax: s.preBeepMax,
            returnTime: returnTime,
            decisionLeadTime: s.decisionLeadTime,
            resetTime: s.resetTime
        )
    }
}
