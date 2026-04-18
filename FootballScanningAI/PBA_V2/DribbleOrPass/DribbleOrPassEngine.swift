//
//  DribbleOrPassEngine.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: scan → beep → pass → reveal gates → cue visible → exit log.
//

import Foundation
import Combine

enum DribbleOrPassPhase: Equatable {
    case waitingForNextRep
    case armedScanning(repIndex: Int, endsAt: Date)
    case beepedAwaitingPass(repIndex: Int)
    case cueRevealing(repIndex: Int, revealedGates: Set<Gate>)
    case cueVisible(repIndex: Int, endsAt: Date)
    case awaitingExitLog(repIndex: Int)
    case blockComplete
}

final class DribbleOrPassEngine: ObservableObject {
    @Published private(set) var phase: DribbleOrPassPhase = .waitingForNextRep {
        didSet {
            print("[PHASE] \(oldValue) → \(phase) [repIndex=\(currentRepIndex)]")
        }
    }
    @Published private(set) var repResults: [DribbleOrPassRepResult] = []
    @Published var instructionTitle: String = ""
    @Published var instructionSubtitle: String = ""
    @Published private(set) var revealedGates: Set<Gate> = []
    @Published private(set) var repDecisions: [RepDecision] = []

    private let config: DribbleOrPassConfig
    private let trainingMode: TrainingMode
    private let plan: [DribbleOrPassRepPlan]
    private(set) var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    /// First-touch can be logged before exit; keyed by repIndex.
    private var pendingFirstTouchByRep: [Int: (gate: Gate, timestamp: Date)] = [:]
    private var scanTimer: Timer?
    private var revealTimers: [Timer] = []
    private var cueHideTimer: Timer?
    /// [CueTiming-Debug] anchor when `cueVisible` phase starts (full greens + timer).
    private var cueTimingDebugVisibleAt: Date?
    private var passTriggeredByRep: [Int: Date] = [:]
    private var directionLoggedByRep: [Int: Date] = [:]
    private var adaptiveState = AdaptiveState()
    private var sessionAdaptiveDifficulty = DifficultySettings(cueDuration: 1.0, travelTime: 1.0, thresholdAdjustment: 0.0)

    init(config: DribbleOrPassConfig, trainingMode: TrainingMode = .solo, plan: [DribbleOrPassRepPlan] = DribbleOrPassScenarioGenerator.generatePlan()) {
        self.config = config
        self.trainingMode = trainingMode
        self.plan = plan
        updateInstructions()
    }

    /// Single write path for ``phase`` so `waitingForNextRep` cannot regress into mid-rep states (e.g. late `onCueHide`).
    private func commitPhase(_ newPhase: DribbleOrPassPhase) {
        if case .waitingForNextRep = phase {
            switch newPhase {
            case .armedScanning, .blockComplete, .waitingForNextRep:
                break
            default:
                print("[INVALID TRANSITION] waitingForNextRep → \(newPhase)")
                assertionFailure("[INVALID TRANSITION] waitingForNextRep → \(newPhase)")
                return
            }
        }
        phase = newPhase
        updateInstructions()
    }

    private func updateInstructions() {
        switch phase {
        case .waitingForNextRep:
            instructionTitle = "Waiting for coach…"
            if trainingMode == .partner {
                instructionSubtitle = ""
            } else {
                instructionSubtitle = "Keep moving. Check both shoulders."
            }
        case .armedScanning:
            instructionTitle = "Scan freely"
            if trainingMode == .partner {
                instructionSubtitle = ""
            } else {
                instructionSubtitle = "Scan before expected arrival."
            }
        case .beepedAwaitingPass:
            instructionTitle = "Ball is coming"
            instructionSubtitle = trainingMode == .partner
                ? ""
                : "Coach: press PASS at the strike."
        case .cueRevealing:
            instructionTitle = "Decide now"
            instructionSubtitle = "If forward space is open → dribble.\nIf not → pass."
        case .cueVisible:
            instructionTitle = "Swipe now"
            instructionSubtitle = "Swipe your decision as the ball arrives."
        case .awaitingExitLog:
            instructionTitle = "Great anticipation"
            instructionSubtitle = "Waiting for coach swipe log…"
        case .blockComplete:
            instructionTitle = "Block complete."
            instructionSubtitle = ""
        }
    }

    func onNextRep(repIndex: Int) {
        guard phase == .waitingForNextRep else { return }
        guard repIndex >= 0, repIndex < plan.count else {
            if repIndex >= plan.count {
                commitPhase(.blockComplete)
            }
            return
        }
        currentRepIndex = repIndex
        passTriggeredAt = nil
        passTriggeredByRep[repIndex] = nil
        directionLoggedByRep[repIndex] = nil
        revealedGates = []
        cancelTimers()

        let delay = UnifiedScanToBeepTiming.randomDelaySeconds()
        #if DEBUG
        UnifiedScanToBeepTiming.logSchedule(
            activity: "dribbleOrPass",
            delaySeconds: delay,
            difficulty: config.difficulty,
            loopLevel: config.curriculumLoopLevel,
            model: .unified
        )
        #endif
        let endsAt = Date().addingTimeInterval(delay)
        commitPhase(.armedScanning(repIndex: repIndex, endsAt: endsAt))

        scanTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex) }
        }
        RunLoop.main.add(scanTimer!, forMode: .common)
    }

    func onBeepFire(repIndex: Int) {
        guard case .armedScanning(let r, _) = phase, r == repIndex else { return }
        scanTimer?.invalidate()
        scanTimer = nil
        commitPhase(.beepedAwaitingPass(repIndex: repIndex))
    }

    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        switch phase {
        case .beepedAwaitingPass(let r) where r == repIndex:
            break
        case .armedScanning(let r, _) where r == repIndex:
            break
        default:
            return
        }
        passTriggeredAt = timestamp
        passTriggeredByRep[repIndex] = timestamp
        #if DEBUG
        DecisionSpeedDebugLog.logEngineRepLive(activity: .dribbleOrPass, repIndex: repIndex, passEmbeddedStored: timestamp)
        #endif
        cancelTimers()
        _ = plan[repIndex]
        let gates: [Gate] = [.up, .down, .left, .right]

        switch config.revealStyle {
        case .simultaneous:
            revealedGates = Set(gates)
            commitPhase(.cueRevealing(repIndex: repIndex, revealedGates: revealedGates))
            transitionToCueVisible(repIndex: repIndex)
        case .twoStage:
            let shuffled = gates.shuffled()
            let firstTwo = Set(shuffled.prefix(2))
            revealedGates = firstTwo
            commitPhase(.cueRevealing(repIndex: repIndex, revealedGates: revealedGates))
            let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.revealedGates = Set(gates)
                    self.commitPhase(.cueRevealing(repIndex: repIndex, revealedGates: self.revealedGates))
                    self.transitionToCueVisible(repIndex: repIndex)
                }
            }
            RunLoop.main.add(t, forMode: .common)
            revealTimers.append(t)
        case .sequential:
            let spacing = config.revealSpacingSeconds * sessionAdaptiveDifficulty.cueDuration
            let order = gates.shuffled()
            revealedGates = []
            commitPhase(.cueRevealing(repIndex: repIndex, revealedGates: []))
            for (i, gateToReveal) in order.enumerated() {
                let gate = gateToReveal
                let t = Timer.scheduledTimer(withTimeInterval: Double(i) * spacing, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.revealedGates.insert(gate)
                        self.commitPhase(.cueRevealing(repIndex: repIndex, revealedGates: self.revealedGates))
                        if self.revealedGates.count == 4 {
                            self.transitionToCueVisible(repIndex: repIndex)
                        }
                    }
                }
                RunLoop.main.add(t, forMode: .common)
                revealTimers.append(t)
            }
        }
    }

    private func transitionToCueVisible(repIndex: Int) {
        cancelRevealTimers()
        revealedGates = [.up, .down, .left, .right]
        let duration = config.cueVisibleSeconds * sessionAdaptiveDifficulty.cueDuration
        let endsAt = Date().addingTimeInterval(duration)
        cueTimingDebugVisibleAt = Date()
        let revealNote: String
        switch config.revealStyle {
        case .simultaneous:
            revealNote = "reveal=simultaneous"
        case .twoStage:
            revealNote = "reveal=twoStage +0.25s stagger before cueVisible"
        case .sequential:
            let spacing = config.revealSpacingSeconds * sessionAdaptiveDifficulty.cueDuration
            revealNote = "reveal=sequential spacing=\(String(format: "%.3f", spacing))s"
        }
        CueTimingDebugLog.logVisible(
            activity: "dribbleOrPass",
            repIndex: repIndex,
            configuredWindowSeconds: duration,
            note: "\(revealNote); phase=cueVisible (greens fixed window)"
        )
        commitPhase(.cueVisible(repIndex: repIndex, endsAt: endsAt))

        cueHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onCueHide(repIndex: repIndex) }
        }
        RunLoop.main.add(cueHideTimer!, forMode: .common)
    }

    private func onCueHide(repIndex: Int) {
        guard case .cueVisible(let r, _) = phase, r == repIndex else {
            cueHideTimer?.invalidate()
            cueHideTimer = nil
            return
        }
        if let v = cueTimingDebugVisibleAt {
            let hiddenAt = Date()
            CueTimingDebugLog.logHidden(
                activity: "dribbleOrPass",
                repIndex: repIndex,
                visibleAt: v,
                hiddenAt: hiddenAt,
                reason: "cue_hide_timer"
            )
            cueTimingDebugVisibleAt = nil
        }
        cueHideTimer?.invalidate()
        cueHideTimer = nil
        revealedGates = []
        commitPhase(.awaitingExitLog(repIndex: repIndex))
    }

    private func cancelRevealTimers() {
        for t in revealTimers { t.invalidate() }
        revealTimers = []
    }

    private func cancelTimers() {
        scanTimer?.invalidate()
        scanTimer = nil
        cancelRevealTimers()
        cueHideTimer?.invalidate()
        cueHideTimer = nil
    }

    /// Clears the finished block and returns to the first rep’s waiting state (same config/mode). Used by “Run It Back” on the display.
    func restartBlockFromBeginning() {
        cancelTimers()
        cueTimingDebugVisibleAt = nil
        currentRepIndex = 0
        passTriggeredAt = nil
        passTriggeredByRep.removeAll()
        directionLoggedByRep.removeAll()
        pendingFirstTouchByRep.removeAll()
        repResults.removeAll()
        repDecisions.removeAll()
        revealedGates = []
        adaptiveState = AdaptiveState()
        sessionAdaptiveDifficulty = DifficultySettings(cueDuration: 1.0, travelTime: 1.0, thresholdAdjustment: 0.0)
        CurrentSessionStore.shared.resetDecisionTimingCalibrationForNewDrillBlock(
            activityId: ActivityKind.dribbleOrPass.sessionActivityActivityId
        )
        commitPhase(.waitingForNextRep)
    }

    /// Partner transport restored without block reset: drop mid-rep timers/state; same `currentRepIndex`; coach sends `nextRep` again.
    func partnerSoftAbandonCurrentRepAwaitCoachRedo(blockRepCount: Int) {
        guard trainingMode == .partner else { return }
        cancelTimers()
        cueTimingDebugVisibleAt = nil
        let safeRepIndex = max(0, min(currentRepIndex, blockRepCount - 1))
        currentRepIndex = safeRepIndex
        let k = safeRepIndex
        passTriggeredAt = nil
        passTriggeredByRep[k] = nil
        directionLoggedByRep[k] = nil
        pendingFirstTouchByRep.removeValue(forKey: k)
        revealedGates = []
        commitPhase(.waitingForNextRep)
    }

    /// After iOS background: align with coordinator snapshot so a fresh `StateObject` engine does not fall back to rep 0.
    func partnerForegroundResumeAlignRepIndex(blockRepCount: Int, authoritativeRepIndex: Int) {
        guard trainingMode == .partner else { return }
        if case .blockComplete = phase { return }
        let safe = max(0, min(authoritativeRepIndex, blockRepCount - 1))
        if currentRepIndex == safe, case .waitingForNextRep = phase { return }
        cancelTimers()
        cueTimingDebugVisibleAt = nil
        currentRepIndex = safe
        let k = safe
        passTriggeredAt = nil
        passTriggeredByRep[k] = nil
        directionLoggedByRep[k] = nil
        pendingFirstTouchByRep.removeValue(forKey: k)
        revealedGates = []
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

    /// After foreground: reschedule scan / cue-hide timers; recover staggered reveal by jumping to full cue window.
    func synchronizeTimersAfterEnteringForeground() {
        let now = Date()
        switch phase {
        case .armedScanning(let repIndex, let endsAt):
            if now >= endsAt {
                onBeepFire(repIndex: repIndex)
            } else {
                let remaining = max(0.01, endsAt.timeIntervalSince(now))
                scanTimer?.invalidate()
                scanTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex) }
                }
                if let t = scanTimer { RunLoop.main.add(t, forMode: .common) }
            }
        case .cueVisible(let repIndex, let endsAt):
            if now >= endsAt {
                onCueHide(repIndex: repIndex)
            } else {
                let remaining = max(0.01, endsAt.timeIntervalSince(now))
                cueHideTimer?.invalidate()
                cueHideTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { self?.onCueHide(repIndex: repIndex) }
                }
                if let t = cueHideTimer { RunLoop.main.add(t, forMode: .common) }
            }
        case .cueRevealing(let repIndex, _):
            transitionToCueVisible(repIndex: repIndex)
        default:
            break
        }
    }

    /// Max reaction time (trigger → confirmation); reps above this are discarded.
    private static let maxReactionTimeSeconds: TimeInterval = 2.0

    /// Returns reaction time in seconds when rep was saved; nil when discarded.
    func onExitLogged(repIndex: Int, gate: Gate, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        if case .waitingForNextRep = phase {
            return nil
        }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri): rIdx = ri
        case .cueVisible(let ri, _):
            rIdx = ri
            if ri == repIndex, let v = cueTimingDebugVisibleAt {
                CueTimingDebugLog.logHidden(
                    activity: "dribbleOrPass",
                    repIndex: repIndex,
                    visibleAt: v,
                    hiddenAt: Date(),
                    reason: "exit_logged"
                )
                cueTimingDebugVisibleAt = nil
            }
        case .cueRevealing(let ri, _): rIdx = ri
        default: return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            passTriggeredAt = nil
            pendingFirstTouchByRep[repIndex] = nil
            cancelTimers()
            if repIndex + 1 >= plan.count { commitPhase(.blockComplete) } else { commitPhase(.waitingForNextRep) }
            return nil
        }

        let p = plan[repIndex]
        let decisionQuality = DribbleOrPassDecisionRules.quality(plan: p, chosen: gate)
        let correct = DribbleOrPassDecisionRules.countsAsCorrect(decisionQuality)
        let forwardLaneOpen = p.up == .open || p.up == .teammate
        let pending = pendingFirstTouchByRep[repIndex]
        pendingFirstTouchByRep[repIndex] = nil
        let expectedArrivalTime = triggerTime.addingTimeInterval(travelTimeSeconds)
        let decisionWindowSeconds = expectedArrivalTime.timeIntervalSince(timestamp)
        let score = adaptiveSessionScore(including: decisionWindowSeconds, isCorrect: correct)
        let speed = classifyDecisionSpeed(windowSeconds: decisionWindowSeconds, score: score)
        directionLoggedByRep[repIndex] = timestamp
        repDecisions.append(
            RepDecision(
                repIndex: repIndex,
                direction: gate,
                isCorrect: correct,
                decisionWindowSeconds: decisionWindowSeconds,
                bucket: DecisionTimingModel.speedBucket(forDecisionWindow: decisionWindowSeconds, activity: .dribbleOrPass, score: score)
            )
        )
        applyAdaptiveAfterRep(wasCorrect: correct, decisionWindow: decisionWindowSeconds)
        CurrentSessionStore.shared.recordDecisionTimingCalibrationSample(
            decisionWindowSeconds: decisionWindowSeconds,
            activityId: ActivityKind.dribbleOrPass.sessionActivityActivityId
        )
        print("[DecisionWindowDebug] repIndex=\(repIndex) passTS=\(triggerTime.timeIntervalSince1970) expectedArrivalTS=\(expectedArrivalTime.timeIntervalSince1970) decisionTS=\(timestamp.timeIntervalSince1970) decisionWindowSeconds=\(decisionWindowSeconds)")
        #if DEBUG
        let engineWallEntry = Date()
        DecisionSpeedDebugLog.logScoredRep(
            activity: .dribbleOrPass,
            repIndex: repIndex,
            passTimestamp: triggerTime,
            directionLogTimestamp: timestamp,
            rawDeltaSeconds: reactionTimeSeconds,
            difficulty: config.difficulty,
            engineEntryWallTime: engineWallEntry
        )
        #endif
        let decisionPoints = dribbleOrPassDecisionPoints(plan: p, chosenGate: gate)
        let timingBonus = dribbleOrPassTimingBonus(speed)
        let result = DribbleOrPassRepResult(
            repIndex: repIndex,
            correct: correct,
            decisionQuality: decisionQuality,
            forwardLaneOpen: forwardLaneOpen,
            decisionTime: reactionTimeSeconds,
            decisionSpeed: speed,
            expectedGate: p.expectedCorrectGate,
            chosenGate: gate,
            decisionPoints: decisionPoints,
            timingBonus: timingBonus,
            firstTouchGate: pending?.gate
        )
        repResults.append(result)
        passTriggeredAt = nil

        cancelTimers()
        if repIndex + 1 >= plan.count {
            commitPhase(.blockComplete)
        } else {
            commitPhase(.waitingForNextRep)
        }
        return reactionTimeSeconds
    }

    /// Coach ✕ — still required for human override when direction-only logging is wrong or disputed (base `correct` is from `onExitLogged`).
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        if case .waitingForNextRep = phase {
            return nil
        }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri): rIdx = ri
        case .cueVisible(let ri, _):
            rIdx = ri
            if ri == repIndex, let v = cueTimingDebugVisibleAt {
                CueTimingDebugLog.logHidden(
                    activity: "dribbleOrPass",
                    repIndex: repIndex,
                    visibleAt: v,
                    hiddenAt: Date(),
                    reason: "incorrect_before_timer"
                )
                cueTimingDebugVisibleAt = nil
            }
        case .cueRevealing(let ri, _): rIdx = ri
        default: return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            passTriggeredAt = nil
            pendingFirstTouchByRep[repIndex] = nil
            cancelTimers()
            if repIndex + 1 >= plan.count { commitPhase(.blockComplete) } else { commitPhase(.waitingForNextRep) }
            return nil
        }

        let p = plan[repIndex]
        pendingFirstTouchByRep[repIndex] = nil
        let expectedArrivalTime = triggerTime.addingTimeInterval(travelTimeSeconds)
        let decisionWindowSeconds = expectedArrivalTime.timeIntervalSince(timestamp)
        applyAdaptiveAfterRep(wasCorrect: false, decisionWindow: decisionWindowSeconds)
        CurrentSessionStore.shared.recordDecisionTimingCalibrationSample(
            decisionWindowSeconds: decisionWindowSeconds,
            activityId: ActivityKind.dribbleOrPass.sessionActivityActivityId
        )
        let score = adaptiveSessionScore(including: decisionWindowSeconds, isCorrect: false)
        let speed = classifyDecisionSpeed(windowSeconds: decisionWindowSeconds, score: score)
        print("[DecisionWindowDebug] repIndex=\(repIndex) passTS=\(triggerTime.timeIntervalSince1970) expectedArrivalTS=\(expectedArrivalTime.timeIntervalSince1970) decisionTS=\(timestamp.timeIntervalSince1970) decisionWindowSeconds=\(decisionWindowSeconds)")
        #if DEBUG
        let engineWallEntryIncorrect = Date()
        DecisionSpeedDebugLog.logScoredRep(
            activity: .dribbleOrPass,
            repIndex: repIndex,
            passTimestamp: triggerTime,
            directionLogTimestamp: timestamp,
            rawDeltaSeconds: reactionTimeSeconds,
            difficulty: config.difficulty,
            engineEntryWallTime: engineWallEntryIncorrect
        )
        #endif
        let forwardLaneOpen = p.up == .open || p.up == .teammate
        let result = DribbleOrPassRepResult(
            repIndex: repIndex,
            correct: false,
            decisionQuality: .incorrect,
            forwardLaneOpen: forwardLaneOpen,
            decisionTime: reactionTimeSeconds,
            decisionSpeed: speed,
            expectedGate: p.expectedCorrectGate,
            chosenGate: .down,
            decisionPoints: 0,
            timingBonus: 0,
            firstTouchGate: nil
        )
        repResults.append(result)
        passTriggeredAt = nil

        cancelTimers()
        if repIndex + 1 >= plan.count {
            commitPhase(.blockComplete)
        } else {
            commitPhase(.waitingForNextRep)
        }
        return reactionTimeSeconds
    }

    /// Wire: `firstTouchLogged` — optional early direction; merged into `DribbleOrPassRepResult` on exit. See `CoachRemoteDecisionModelMIGRATION.md`.
    func onFirstTouchLogged(repIndex: Int, gate: Gate, timestamp: Date) {
        guard repIndex >= 0, repIndex < plan.count else { return }
        pendingFirstTouchByRep[repIndex] = (gate, timestamp)
    }

    var currentPlan: DribbleOrPassRepPlan? {
        guard currentRepIndex >= 0, currentRepIndex < plan.count else { return nil }
        return plan[currentRepIndex]
    }

    deinit { cancelTimers() }

    private var travelTimeSeconds: Double {
        let base = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
        return CurrentSessionStore.shared.calibratedBallTravelSeconds(
            baseNominal: base,
            activityId: ActivityKind.dribbleOrPass.sessionActivityActivityId
        )
    }

    private func applyAdaptiveAfterRep(wasCorrect: Bool, decisionWindow: Double) {
        updateAdaptiveState(state: &adaptiveState, wasCorrect: wasCorrect, decisionWindow: decisionWindow)
        sessionAdaptiveDifficulty = adjustDifficulty(state: &adaptiveState, current: sessionAdaptiveDifficulty)
    }

    private func adaptiveSessionScore(including newWindow: Double, isCorrect: Bool) -> Int {
        let existingWindows = repDecisions.map(\.decisionWindowSeconds)
        let windows = existingWindows + [newWindow]
        let existingCorrect = repDecisions.filter(\.isCorrect).count
        let correct = existingCorrect + (isCorrect ? 1 : 0)
        let total = windows.count
        guard total > 0 else { return 70 }
        let accuracy = Double(correct) / Double(total)
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: windows, activity: .dribbleOrPass)
    }
}

// MARK: - Partner relay reconnect checkpoint (no scoring impact)

extension DribbleOrPassEngine: PartnerRelayCheckpointEmitting {
    func partnerRelayCheckpointPayload(activityId: String, relaySessionId: String?) -> PartnerRelayCheckpointPayload {
        let rep: Int
        let phaseToken: String
        switch phase {
        case .waitingForNextRep:
            rep = repResults.count
            phaseToken = "waitingForNextRep"
        case .blockComplete:
            rep = plan.count
            phaseToken = "blockComplete"
        case .armedScanning(let r, _):
            rep = r
            phaseToken = "armedScanning"
        case .beepedAwaitingPass(let r):
            rep = r
            phaseToken = "beepedAwaitingPass"
        case .cueRevealing(let r, _):
            rep = r
            phaseToken = "cueRevealing"
        case .cueVisible(let r, _):
            rep = r
            phaseToken = "cueVisible"
        case .awaitingExitLog(let r):
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
