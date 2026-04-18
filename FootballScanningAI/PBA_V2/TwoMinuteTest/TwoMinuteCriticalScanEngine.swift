//
//  TwoMinuteCriticalScanEngine.swift
//  FootballScanningAI
//
//  PBA V2 — State machine for iPad. nextRep → scan window → beep → passTriggered shows ball → exitLogged.
//

import Foundation
import Combine

enum CriticalScanPhase: Equatable {
    case waitingForNextRep
    case armedScanning(repIndex: Int, ballGate: Gate, endsAt: Date)
    case beepedAwaitingPass(repIndex: Int, ballGate: Gate)
    case ballVisible(repIndex: Int, ballGate: Gate, endsAt: Date)
    case awaitingExitLog(repIndex: Int, ballGate: Gate)
    case complete
}

final class TwoMinuteCriticalScanEngine: ObservableObject {
    @Published private(set) var phase: CriticalScanPhase = .waitingForNextRep {
        didSet {
            print("[PHASE] \(oldValue) → \(phase) [repIndex=\(currentRepIndex)]")
        }
    }
    @Published private(set) var repLogs: [RepLog] = []
    @Published private(set) var repDecisions: [RepDecision] = []

    private let config: TwoMinuteTestConfig
    private let plan: [RepPlan]
    private(set) var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    private var startedAtForCurrentRep: Date?
    private var infoShownAtForCurrentRep: Date?
    private var infoHiddenAtForCurrentRep: Date?
    private var scanDelayTimer: Timer?
    private var ballHideTimer: Timer?
    /// [CueTiming-Debug] anchor for ball cue visibility (PASS → ball hide).
    private var cueTimingDebugVisibleAt: Date?
    private var passTriggeredByRep: [Int: Date] = [:]
    private var directionLoggedByRep: [Int: Date] = [:]

    init(config: TwoMinuteTestConfig, repPlans: [RepPlan] = TwoMinuteRepPlanner.generatePlan()) {
        self.config = config
        self.plan = repPlans
    }

    private func commitPhase(_ newPhase: CriticalScanPhase) {
        if case .waitingForNextRep = phase {
            switch newPhase {
            case .armedScanning, .complete, .waitingForNextRep:
                break
            default:
                print("[INVALID TRANSITION] waitingForNextRep → \(newPhase)")
                assertionFailure("[INVALID TRANSITION] waitingForNextRep → \(newPhase)")
                return
            }
        }
        phase = newPhase
    }

    func onNextRep(repIndex: Int) {
        guard phase == .waitingForNextRep else { return }
        currentRepIndex = repIndex
        guard repIndex >= 0, repIndex < plan.count else {
            if repIndex >= plan.count { commitPhase(.complete) }
            return
        }

        let p = plan[repIndex]
        passTriggeredAt = nil
        passTriggeredByRep[repIndex] = nil
        directionLoggedByRep[repIndex] = nil
        startedAtForCurrentRep = Date()
        infoShownAtForCurrentRep = nil
        infoHiddenAtForCurrentRep = nil
        cancelTimers()

        let delay = TwoMinuteTestConfig.randomTwoMinuteBeepDelaySeconds(difficulty: config.difficulty)
        let endsAt = Date().addingTimeInterval(delay)
        commitPhase(.armedScanning(repIndex: repIndex, ballGate: p.ballGate, endsAt: endsAt))

        // Single fire path (asyncAfter) to avoid Timer/asyncAfter race; Timer kept as backup.
        scanDelayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex, ballGate: p.ballGate) }
        }
        RunLoop.main.add(scanDelayTimer!, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.onBeepFire(repIndex: repIndex, ballGate: p.ballGate)
        }
    }

    func onBeepFire(repIndex: Int, ballGate: Gate) {
        guard case .armedScanning(let r, _, _) = phase, r == repIndex else { return }
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        commitPhase(.beepedAwaitingPass(repIndex: repIndex, ballGate: ballGate))
    }

    /// Accept PASS after the beep, or early during the scan window when the coach triggers first (partner relay).
    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        let ballGate: Gate
        switch phase {
        case .beepedAwaitingPass(let rIdx, let g):
            guard rIdx == repIndex else { return }
            ballGate = g
        case .armedScanning(let rIdx, let g, _):
            guard rIdx == repIndex else { return }
            scanDelayTimer?.invalidate()
            scanDelayTimer = nil
            ballGate = g
        default:
            return
        }

        passTriggeredAt = timestamp
        passTriggeredByRep[repIndex] = timestamp
        infoShownAtForCurrentRep = timestamp
        #if DEBUG
        DecisionSpeedDebugLog.logEngineRepLive(activity: .twoMinuteTest, repIndex: repIndex, passEmbeddedStored: timestamp)
        #endif
        ballHideTimer?.invalidate()
        let duration = config.ballVisibleSeconds
        let endsAt = Date().addingTimeInterval(duration)
        cueTimingDebugVisibleAt = Date()
        CueTimingDebugLog.logVisible(
            activity: "twoMinuteCriticalScan",
            repIndex: repIndex,
            configuredWindowSeconds: duration,
            note: "PASS→ballVisible"
        )
        commitPhase(.ballVisible(repIndex: repIndex, ballGate: ballGate, endsAt: endsAt))

        ballHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.transitionToAwaitingExitLog(repIndex: repIndex, ballGate: ballGate) }
        }
        RunLoop.main.add(ballHideTimer!, forMode: .common)
    }

    /// Max reaction time (trigger -> confirmation); reps above this are discarded.
    /// Slightly wider in real coach-operated workflows to reduce false drops.
    private static let maxReactionTimeSeconds: TimeInterval = 3.5

    /// Returns reaction time in seconds when rep was saved; nil when discarded.
    func onExitLogged(repIndex: Int, gate: Gate, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        if case .waitingForNextRep = phase {
            return nil
        }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri, _):
            rIdx = ri
        case .ballVisible(let ri, _, _):
            rIdx = ri
            if ri != repIndex { return nil }
            CueTimingDebugLog.logHidden(
                activity: "twoMinuteCriticalScan",
                repIndex: repIndex,
                visibleAt: cueTimingDebugVisibleAt,
                hiddenAt: Date(),
                reason: "exit_logged_before_timer"
            )
            cueTimingDebugVisibleAt = nil
            ballHideTimer?.invalidate()
            ballHideTimer = nil
            infoHiddenAtForCurrentRep = Date()
        default:
            return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        let triggerTime = passTriggeredAt ?? infoShownAtForCurrentRep ?? startedAtForCurrentRep ?? timestamp

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            #if DEBUG
            print("[PBA-Debug] 2MT rep discarded (slow): rep=\(repIndex), reaction=\(String(format: "%.2f", reactionTimeSeconds))s, max=\(Self.maxReactionTimeSeconds)s, hadPassTrigger=\(passTriggeredAt != nil)")
            #endif
            passTriggeredAt = nil
            cancelTimers()
            if repIndex + 1 >= plan.count { commitPhase(.complete) } else { commitPhase(.waitingForNextRep) }
            return nil
        }

        #if DEBUG
        let triggerAnchor2MT: String = {
            if passTriggeredAt != nil { return "passTriggeredAt" }
            if infoShownAtForCurrentRep != nil { return "infoShownAtForCurrentRep" }
            if startedAtForCurrentRep != nil { return "startedAtForCurrentRep" }
            return "exit_timestamp_fallback"
        }()
        let engineWallEntry2MT = Date()
        DecisionSpeedDebugLog.logScoredRep(
            activity: .twoMinuteTest,
            repIndex: repIndex,
            passTimestamp: passTriggeredAt,
            directionLogTimestamp: timestamp,
            rawDeltaSeconds: reactionTimeSeconds,
            difficulty: config.difficulty,
            visualRevealTimestamp: infoShownAtForCurrentRep,
            triggerAnchor: triggerAnchor2MT,
            engineEntryWallTime: engineWallEntry2MT
        )
        #endif

        let p = plan[repIndex]
        let expectedArrivalTime = triggerTime.addingTimeInterval(travelTimeSeconds)
        let decisionWindowSeconds = expectedArrivalTime.timeIntervalSince(timestamp)
        let score = adaptiveSessionScore(including: decisionWindowSeconds, isCorrect: gate == p.ballGate)
        directionLoggedByRep[repIndex] = timestamp
        repDecisions.append(
            RepDecision(
                repIndex: repIndex,
                direction: gate,
                isCorrect: gate == p.ballGate,
                decisionWindowSeconds: decisionWindowSeconds,
                bucket: DecisionTimingModel.speedBucket(forDecisionWindow: decisionWindowSeconds, activity: .twoMinuteTest, score: score)
            )
        )
        CurrentSessionStore.shared.recordDecisionTimingCalibrationSample(
            decisionWindowSeconds: decisionWindowSeconds,
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId
        )
        print("[DecisionWindowDebug] repIndex=\(repIndex) passTS=\(triggerTime.timeIntervalSince1970) expectedArrivalTS=\(expectedArrivalTime.timeIntervalSince1970) decisionTS=\(timestamp.timeIntervalSince1970) decisionWindowSeconds=\(decisionWindowSeconds)")
        let startedAt = startedAtForCurrentRep ?? Date()
        let infoShownAt = infoShownAtForCurrentRep ?? startedAt
        let infoHiddenAt = infoHiddenAtForCurrentRep ?? Date()
        let log = RepLog.from(
            repIndex: repIndex,
            ballGate: p.ballGate,
            exitedGate: gate,
            startedAt: startedAt,
            infoShownAt: infoShownAt,
            infoHiddenAt: infoHiddenAt,
            passTriggeredAt: passTriggeredAt,
            exitLoggedAt: timestamp
        )
        repLogs.append(log)
        passTriggeredAt = nil

        cancelTimers()
        if repIndex + 1 >= plan.count {
            commitPhase(.complete)
        } else {
            commitPhase(.waitingForNextRep)
        }
        return reactionTimeSeconds
    }

    /// Coach ✕ — records intentional wrong exit; still required for explicit wrong without misleading direction log.
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        if case .waitingForNextRep = phase {
            return nil
        }
        var ballGate: Gate?
        switch phase {
        case .awaitingExitLog(let ri, let g): if ri == repIndex { ballGate = g }
        case .ballVisible(let ri, let g, _):
            if ri == repIndex {
                ballGate = g
                CueTimingDebugLog.logHidden(
                    activity: "twoMinuteCriticalScan",
                    repIndex: repIndex,
                    visibleAt: cueTimingDebugVisibleAt,
                    hiddenAt: Date(),
                    reason: "incorrect_before_timer"
                )
                cueTimingDebugVisibleAt = nil
                ballHideTimer?.invalidate()
                ballHideTimer = nil
                infoHiddenAtForCurrentRep = Date()
            }
        default: break
        }
        guard ballGate != nil else { return nil }
        let triggerTime = passTriggeredAt ?? infoShownAtForCurrentRep ?? startedAtForCurrentRep ?? timestamp

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            #if DEBUG
            print("[PBA-Debug] 2MT incorrect rep discarded (slow): rep=\(repIndex), reaction=\(String(format: "%.2f", reactionTimeSeconds))s, max=\(Self.maxReactionTimeSeconds)s, hadPassTrigger=\(passTriggeredAt != nil)")
            #endif
            passTriggeredAt = nil
            cancelTimers()
            if repIndex + 1 >= plan.count { commitPhase(.complete) } else { commitPhase(.waitingForNextRep) }
            return nil
        }

        #if DEBUG
        let triggerAnchor2MTIncorrect: String = {
            if passTriggeredAt != nil { return "passTriggeredAt" }
            if infoShownAtForCurrentRep != nil { return "infoShownAtForCurrentRep" }
            if startedAtForCurrentRep != nil { return "startedAtForCurrentRep" }
            return "exit_timestamp_fallback"
        }()
        let engineWallEntry2MTIncorrect = Date()
        DecisionSpeedDebugLog.logScoredRep(
            activity: .twoMinuteTest,
            repIndex: repIndex,
            passTimestamp: passTriggeredAt,
            directionLogTimestamp: timestamp,
            rawDeltaSeconds: reactionTimeSeconds,
            difficulty: config.difficulty,
            visualRevealTimestamp: infoShownAtForCurrentRep,
            triggerAnchor: triggerAnchor2MTIncorrect,
            engineEntryWallTime: engineWallEntry2MTIncorrect
        )
        #endif

        let p = plan[repIndex]
        let expectedArrivalTime = triggerTime.addingTimeInterval(travelTimeSeconds)
        let decisionWindowSeconds = expectedArrivalTime.timeIntervalSince(timestamp)
        CurrentSessionStore.shared.recordDecisionTimingCalibrationSample(
            decisionWindowSeconds: decisionWindowSeconds,
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId
        )
        print("[DecisionWindowDebug] repIndex=\(repIndex) passTS=\(triggerTime.timeIntervalSince1970) expectedArrivalTS=\(expectedArrivalTime.timeIntervalSince1970) decisionTS=\(timestamp.timeIntervalSince1970) decisionWindowSeconds=\(decisionWindowSeconds)")
        let startedAt = startedAtForCurrentRep ?? Date()
        let infoShownAt = infoShownAtForCurrentRep ?? startedAt
        let infoHiddenAt = infoHiddenAtForCurrentRep ?? Date()
        let log = RepLog.from(
            repIndex: repIndex,
            ballGate: p.ballGate,
            exitedGate: p.ballGate.opposite,
            startedAt: startedAt,
            infoShownAt: infoShownAt,
            infoHiddenAt: infoHiddenAt,
            passTriggeredAt: passTriggeredAt,
            exitLoggedAt: timestamp
        )
        repLogs.append(log)
        passTriggeredAt = nil

        cancelTimers()
        if repIndex + 1 >= plan.count {
            commitPhase(.complete)
        } else {
            commitPhase(.waitingForNextRep)
        }
        return reactionTimeSeconds
    }

    private func transitionToAwaitingExitLog(repIndex: Int, ballGate: Gate) {
        guard case .ballVisible(let r, let g, _) = phase, r == repIndex, g == ballGate else {
            ballHideTimer?.invalidate()
            ballHideTimer = nil
            return
        }
        CueTimingDebugLog.logHidden(
            activity: "twoMinuteCriticalScan",
            repIndex: repIndex,
            visibleAt: cueTimingDebugVisibleAt,
            hiddenAt: Date(),
            reason: "ball_hide_timer"
        )
        cueTimingDebugVisibleAt = nil
        ballHideTimer?.invalidate()
        ballHideTimer = nil
        infoHiddenAtForCurrentRep = Date()
        commitPhase(.awaitingExitLog(repIndex: repIndex, ballGate: ballGate))
    }

    private func cancelTimers() {
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        ballHideTimer?.invalidate()
        ballHideTimer = nil
    }

    /// Clears the finished test and returns to the first rep’s waiting state (same config). Used when restarting from a summary without re-navigation.
    func restartBlockFromBeginning() {
        cancelTimers()
        cueTimingDebugVisibleAt = nil
        currentRepIndex = 0
        passTriggeredAt = nil
        startedAtForCurrentRep = nil
        infoShownAtForCurrentRep = nil
        infoHiddenAtForCurrentRep = nil
        passTriggeredByRep.removeAll()
        directionLoggedByRep.removeAll()
        repLogs.removeAll()
        repDecisions.removeAll()
        CurrentSessionStore.shared.resetDecisionTimingCalibrationForNewDrillBlock(
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId
        )
        commitPhase(.waitingForNextRep)
    }

    /// Partner transport restored without block reset: drop mid-rep timers/state; same `currentRepIndex`; coach sends `nextRep` again.
    func partnerSoftAbandonCurrentRepAwaitCoachRedo(blockRepCount: Int) {
        cancelTimers()
        cueTimingDebugVisibleAt = nil
        let safeRepIndex = max(0, min(currentRepIndex, blockRepCount - 1))
        currentRepIndex = safeRepIndex
        let k = safeRepIndex
        passTriggeredAt = nil
        passTriggeredByRep[k] = nil
        directionLoggedByRep[k] = nil
        startedAtForCurrentRep = nil
        infoShownAtForCurrentRep = nil
        infoHiddenAtForCurrentRep = nil
        commitPhase(.waitingForNextRep)
    }

    /// After iOS background: align with coordinator snapshot so a fresh `StateObject` engine does not fall back to rep 0.
    func partnerForegroundResumeAlignRepIndex(blockRepCount: Int, authoritativeRepIndex: Int) {
        if case .complete = phase { return }
        let safe = max(0, min(authoritativeRepIndex, blockRepCount - 1))
        if currentRepIndex == safe, case .waitingForNextRep = phase { return }
        cancelTimers()
        cueTimingDebugVisibleAt = nil
        currentRepIndex = safe
        let k = safe
        passTriggeredAt = nil
        passTriggeredByRep[k] = nil
        directionLoggedByRep[k] = nil
        startedAtForCurrentRep = nil
        infoShownAtForCurrentRep = nil
        infoHiddenAtForCurrentRep = nil
        commitPhase(.waitingForNextRep)
    }

    /// Cancels all scheduled timers (e.g. partner “Start New Session” / navigation away).
    func invalidateAllTimers() {
        cancelTimers()
    }

    /// Call when app enters background so timers don't fire late when returning.
    func applicationDidEnterBackground() {
        cancelTimers()
    }

    /// After foreground: timers were cleared in background — reschedule or fast-forward using embedded `endsAt` deadlines.
    func synchronizeTimersAfterEnteringForeground() {
        let now = Date()
        switch phase {
        case .armedScanning(let repIndex, let ballGate, let endsAt):
            if now >= endsAt {
                onBeepFire(repIndex: repIndex, ballGate: ballGate)
            } else {
                let remaining = max(0.01, endsAt.timeIntervalSince(now))
                scanDelayTimer?.invalidate()
                scanDelayTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex, ballGate: ballGate) }
                }
                if let t = scanDelayTimer { RunLoop.main.add(t, forMode: .common) }
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    self?.onBeepFire(repIndex: repIndex, ballGate: ballGate)
                }
            }
        case .ballVisible(let repIndex, let ballGate, let endsAt):
            if now >= endsAt {
                transitionToAwaitingExitLog(repIndex: repIndex, ballGate: ballGate)
            } else {
                let remaining = max(0.01, endsAt.timeIntervalSince(now))
                ballHideTimer?.invalidate()
                ballHideTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { self?.transitionToAwaitingExitLog(repIndex: repIndex, ballGate: ballGate) }
                }
                if let t = ballHideTimer { RunLoop.main.add(t, forMode: .common) }
            }
        default:
            break
        }
    }

    deinit {
        cancelTimers()
    }

    private var travelTimeSeconds: Double {
        let base = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
        return CurrentSessionStore.shared.calibratedBallTravelSeconds(
            baseNominal: base,
            activityId: ActivityKind.twoMinuteTest.sessionActivityActivityId
        )
    }

    private func adaptiveSessionScore(including newWindow: Double, isCorrect: Bool) -> Int {
        let existingWindows = repDecisions.map(\.decisionWindowSeconds)
        let windows = existingWindows + [newWindow]
        let existingCorrect = repDecisions.filter(\.isCorrect).count
        let correct = existingCorrect + (isCorrect ? 1 : 0)
        let total = windows.count
        guard total > 0 else { return 70 }
        let accuracy = Double(correct) / Double(total)
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: windows, activity: .twoMinuteTest)
    }
}

// MARK: - Partner relay reconnect checkpoint (no scoring impact)

extension TwoMinuteCriticalScanEngine: PartnerRelayCheckpointEmitting {
    func partnerRelayCheckpointPayload(activityId: String, relaySessionId: String?) -> PartnerRelayCheckpointPayload {
        let rep: Int
        let phaseToken: String
        switch phase {
        case .waitingForNextRep:
            rep = repLogs.count
            phaseToken = "waitingForNextRep"
        case .complete:
            rep = plan.count
            phaseToken = "complete"
        case .armedScanning(let r, _, _):
            rep = r
            phaseToken = "armedScanning"
        case .beepedAwaitingPass(let r, _):
            rep = r
            phaseToken = "beepedAwaitingPass"
        case .ballVisible(let r, _, _):
            rep = r
            phaseToken = "ballVisible"
        case .awaitingExitLog(let r, _):
            rep = r
            phaseToken = "awaitingExitLog"
        }
        return PartnerRelayCheckpointPayload(
            sourceRole: "display",
            activityId: activityId,
            repIndex: rep,
            phaseToken: phaseToken,
            relaySessionId: relaySessionId
        )
    }
}
