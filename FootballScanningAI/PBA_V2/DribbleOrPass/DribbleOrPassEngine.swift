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
    @Published private(set) var phase: DribbleOrPassPhase = .waitingForNextRep
    @Published private(set) var repResults: [DribbleOrPassRepResult] = []
    @Published var instructionTitle: String = ""
    @Published var instructionSubtitle: String = ""
    @Published private(set) var revealedGates: Set<Gate> = []

    private let config: DribbleOrPassConfig
    private let trainingMode: TrainingMode
    private let plan: [DribbleOrPassRepPlan]
    private var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    /// First-touch can be logged before exit; keyed by repIndex.
    private var pendingFirstTouchByRep: [Int: (gate: Gate, timestamp: Date)] = [:]
    private var scanTimer: Timer?
    private var revealTimers: [Timer] = []
    private var cueHideTimer: Timer?

    init(config: DribbleOrPassConfig, trainingMode: TrainingMode = .solo, plan: [DribbleOrPassRepPlan] = DribbleOrPassScenarioGenerator.generatePlan()) {
        self.config = config
        self.trainingMode = trainingMode
        self.plan = plan
        updateInstructions()
    }

    private func updateInstructions() {
        switch phase {
        case .waitingForNextRep:
            instructionTitle = "Waiting for coach…"
            if trainingMode == .partner {
                instructionSubtitle = "\(ActivityInstructionData.partnerCoachSetupLine)\n\(ActivityInstructionData.partnerCoachBallLine)"
            } else {
                instructionSubtitle = "Keep moving. Check both shoulders."
            }
        case .armedScanning:
            instructionTitle = "Scan freely"
            if trainingMode == .partner {
                instructionSubtitle = "\(ActivityInstructionData.partnerPlayerBeepLine)\n\(ActivityInstructionData.timingLine)"
            } else {
                instructionSubtitle = "Beep is coming."
            }
        case .beepedAwaitingPass:
            instructionTitle = "Ball is coming"
            instructionSubtitle = trainingMode == .partner
                ? ActivityInstructionData.partnerCoachPassTimingLine
                : "Coach: press PASS at the strike."
        case .cueRevealing:
            instructionTitle = "Decide now"
            instructionSubtitle = "Green = pass, Clear = dribble."
        case .cueVisible:
            instructionTitle = "Decide now"
            instructionSubtitle = "Green = pass, Clear = dribble."
        case .awaitingExitLog:
            instructionTitle = "Play the rep"
            instructionSubtitle = "Waiting for coach log…"
        case .blockComplete:
            instructionTitle = "Block complete."
            instructionSubtitle = ""
        }
    }

    func onNextRep(repIndex: Int) {
        guard phase != .blockComplete else { return }
        guard repIndex >= 0, repIndex < plan.count else {
            if repIndex >= plan.count {
                phase = .blockComplete
                updateInstructions()
            }
            return
        }
        // Ignore stale rep indices, but allow same/newer indices to resync if coach and display drift.
        guard repIndex >= currentRepIndex else { return }
        currentRepIndex = repIndex
        passTriggeredAt = nil
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
        phase = .armedScanning(repIndex: repIndex, endsAt: endsAt)
        updateInstructions()

        scanTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex) }
        }
        RunLoop.main.add(scanTimer!, forMode: .common)
    }

    func onBeepFire(repIndex: Int) {
        guard case .armedScanning(let r, _) = phase, r == repIndex else { return }
        scanTimer?.invalidate()
        scanTimer = nil
        phase = .beepedAwaitingPass(repIndex: repIndex)
        updateInstructions()
    }

    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        guard case .beepedAwaitingPass(let r) = phase, r == repIndex else { return }
        passTriggeredAt = timestamp
        #if DEBUG
        DecisionSpeedDebugLog.logEngineRepLive(activity: .dribbleOrPass, repIndex: repIndex, passEmbeddedStored: timestamp)
        #endif
        cancelTimers()
        _ = plan[repIndex]
        let gates: [Gate] = [.up, .down, .left, .right]

        switch config.revealStyle {
        case .simultaneous:
            revealedGates = Set(gates)
            phase = .cueRevealing(repIndex: repIndex, revealedGates: revealedGates)
            updateInstructions()
            transitionToCueVisible(repIndex: repIndex)
        case .twoStage:
            let shuffled = gates.shuffled()
            let firstTwo = Set(shuffled.prefix(2))
            revealedGates = firstTwo
            phase = .cueRevealing(repIndex: repIndex, revealedGates: revealedGates)
            updateInstructions()
            let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.revealedGates = Set(gates)
                    self.phase = .cueRevealing(repIndex: repIndex, revealedGates: self.revealedGates)
                    self.updateInstructions()
                    self.transitionToCueVisible(repIndex: repIndex)
                }
            }
            RunLoop.main.add(t, forMode: .common)
            revealTimers.append(t)
        case .sequential:
            let spacing = config.revealSpacingSeconds
            let order = gates.shuffled()
            revealedGates = []
            phase = .cueRevealing(repIndex: repIndex, revealedGates: [])
            updateInstructions()
            for (i, gateToReveal) in order.enumerated() {
                let gate = gateToReveal
                let t = Timer.scheduledTimer(withTimeInterval: Double(i) * spacing, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.revealedGates.insert(gate)
                        self.phase = .cueRevealing(repIndex: repIndex, revealedGates: self.revealedGates)
                        self.updateInstructions()
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
        let duration = config.cueVisibleSeconds
        let endsAt = Date().addingTimeInterval(duration)
        phase = .cueVisible(repIndex: repIndex, endsAt: endsAt)
        updateInstructions()

        cueHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onCueHide(repIndex: repIndex) }
        }
        RunLoop.main.add(cueHideTimer!, forMode: .common)
    }

    private func onCueHide(repIndex: Int) {
        cueHideTimer?.invalidate()
        cueHideTimer = nil
        revealedGates = []
        phase = .awaitingExitLog(repIndex: repIndex)
        updateInstructions()
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

    /// Call when app enters background so timers don't fire late when returning.
    func applicationDidEnterBackground() {
        cancelTimers()
    }

    /// Max reaction time (trigger → confirmation); reps above this are discarded.
    private static let maxReactionTimeSeconds: TimeInterval = 2.0

    /// Returns reaction time in seconds when rep was saved; nil when discarded.
    func onExitLogged(repIndex: Int, gate: Gate, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri): rIdx = ri
        case .cueVisible(let ri, _): rIdx = ri
        case .cueRevealing(let ri, _): rIdx = ri
        default: return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            passTriggeredAt = nil
            pendingFirstTouchByRep[repIndex] = nil
            if repIndex + 1 >= plan.count { phase = .blockComplete } else { phase = .waitingForNextRep }
            updateInstructions()
            return nil
        }

        let p = plan[repIndex]
        let correct = (gate == p.expectedCorrectGate)
        let pending = pendingFirstTouchByRep[repIndex]
        pendingFirstTouchByRep[repIndex] = nil
        let speed = TimingThresholds.dribblePassDecisionSpeed(for: reactionTimeSeconds)
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

        if repIndex + 1 >= plan.count {
            phase = .blockComplete
        } else {
            phase = .waitingForNextRep
        }
        updateInstructions()
        return reactionTimeSeconds
    }

    /// Coach ✕ — still required for human override when direction-only logging is wrong or disputed (base `correct` is from `onExitLogged`).
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri): rIdx = ri
        case .cueVisible(let ri, _): rIdx = ri
        case .cueRevealing(let ri, _): rIdx = ri
        default: return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            passTriggeredAt = nil
            pendingFirstTouchByRep[repIndex] = nil
            if repIndex + 1 >= plan.count { phase = .blockComplete } else { phase = .waitingForNextRep }
            updateInstructions()
            return nil
        }

        let p = plan[repIndex]
        pendingFirstTouchByRep[repIndex] = nil
        let speed = TimingThresholds.dribblePassDecisionSpeed(for: reactionTimeSeconds)
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
        let result = DribbleOrPassRepResult(
            repIndex: repIndex,
            correct: false,
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

        if repIndex + 1 >= plan.count {
            phase = .blockComplete
        } else {
            phase = .waitingForNextRep
        }
        updateInstructions()
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
}
