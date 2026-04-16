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
    @Published private(set) var phase: CriticalScanPhase = .waitingForNextRep
    @Published private(set) var repLogs: [RepLog] = []
    @Published private(set) var repDecisions: [RepDecision] = []

    private let config: TwoMinuteTestConfig
    private let plan: [RepPlan]
    private var currentRepIndex: Int = 0
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

    func onNextRep(repIndex: Int) {
        guard phase == .waitingForNextRep else { return }
        currentRepIndex = repIndex
        guard repIndex >= 0, repIndex < plan.count else {
            if repIndex >= plan.count { phase = .complete }
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
        phase = .armedScanning(repIndex: repIndex, ballGate: p.ballGate, endsAt: endsAt)

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
        phase = .beepedAwaitingPass(repIndex: repIndex, ballGate: ballGate)
    }

    /// Only accept PASS when we're in beepedAwaitingPass (after the beep). Ignore accidental taps during the scan window so the beep always fires.
    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        let ballGate: Gate
        switch phase {
        case .beepedAwaitingPass(let rIdx, let g):
            guard rIdx == repIndex else { return }
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
        phase = .ballVisible(repIndex: repIndex, ballGate: ballGate, endsAt: endsAt)

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
            if repIndex + 1 >= plan.count { phase = .complete } else { phase = .waitingForNextRep }
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

        if repIndex + 1 >= plan.count {
            phase = .complete
        } else {
            phase = .waitingForNextRep
        }
        return reactionTimeSeconds
    }

    /// Coach ✕ — records intentional wrong exit; still required for explicit wrong without misleading direction log.
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
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
            if repIndex + 1 >= plan.count { phase = .complete } else { phase = .waitingForNextRep }
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

        if repIndex + 1 >= plan.count {
            phase = .complete
        } else {
            phase = .waitingForNextRep
        }
        return reactionTimeSeconds
    }

    private func transitionToAwaitingExitLog(repIndex: Int, ballGate: Gate) {
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
        phase = .awaitingExitLog(repIndex: repIndex, ballGate: ballGate)
    }

    private func cancelTimers() {
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        ballHideTimer?.invalidate()
        ballHideTimer = nil
    }

    /// Call when app enters background so timers don't fire late when returning.
    func applicationDidEnterBackground() {
        cancelTimers()
    }

    deinit {
        cancelTimers()
    }

    private var travelTimeSeconds: Double {
        CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
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
