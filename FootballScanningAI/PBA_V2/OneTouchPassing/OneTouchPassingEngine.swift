//
//  OneTouchPassingEngine.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: scan → CHECK cue (0.6s) → awaiting pass → reveal green/red → cue visible → exit log.
//

import Foundation
import Combine

enum RepDecisionBucket: String, Codable, Hashable {
    case fast
    case medium
    case slow
}

struct RepDecision: Codable, Hashable {
    let repIndex: Int
    let direction: Gate
    let isCorrect: Bool
    let decisionWindowSeconds: Double
    let bucket: RepDecisionBucket
}

enum OneTouchPassingPhase: Equatable {
    case waitingForNextRep
    case armedScanning(repIndex: Int, endsAt: Date)
    case showingCheck(repIndex: Int)
    case awaitingPassTrigger(repIndex: Int)
    case cueRevealing(repIndex: Int, revealedGates: Set<Gate>)
    case cueVisible(repIndex: Int, endsAt: Date)
    case awaitingExitLog(repIndex: Int)
    case blockComplete
}

final class OneTouchPassingEngine: ObservableObject {
    @Published private(set) var phase: OneTouchPassingPhase = .waitingForNextRep
    @Published private(set) var repResults: [OneTouchRepResult] = []
    @Published var instructionTitle: String = ""
    @Published var instructionSubtitle: String = ""
    @Published private(set) var revealedGates: Set<Gate> = []
    @Published private(set) var showCheckCue: Bool = false
    @Published private(set) var repDecisions: [RepDecision] = []

    private let config: OneTouchPassingConfig
    private let trainingMode: TrainingMode
    private let plan: [OneTouchRepPlan]
    private var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    private var scanTimer: Timer?
    private var checkEndTimer: Timer?
    private var revealTimers: [Timer] = []
    private var cueHideTimer: Timer?
    /// [CueTiming-Debug] anchor when `cueVisible` phase starts (full greens + timer).
    private var cueTimingDebugVisibleAt: Date?
    private var passTriggeredByRep: [Int: Date] = [:]
    private var directionLoggedByRep: [Int: Date] = [:]
    private var adaptiveState = AdaptiveState()
    private var sessionAdaptiveDifficulty = DifficultySettings(cueDuration: 1.0, travelTime: 1.0, thresholdAdjustment: 0.0)

    init(config: OneTouchPassingConfig, trainingMode: TrainingMode = .solo, plan: [OneTouchRepPlan] = OneTouchPassingScenarioGenerator.generatePlan()) {
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
                instructionSubtitle = "Scan the field."
            }
        case .armedScanning:
            instructionTitle = "Scan freely"
            if trainingMode == .partner {
                instructionSubtitle = "\(ActivityInstructionData.partnerPlayerBeepLine)\n\(ActivityInstructionData.timingLine)\nCHECK is coming."
            } else {
                instructionSubtitle = "Scan multiple options early.\nCHECK is coming."
            }
        case .showingCheck:
            instructionTitle = "CHECK"
            instructionSubtitle = trainingMode == .partner ? ActivityInstructionData.timingLine : "Ball is coming…"
        case .awaitingPassTrigger:
            instructionTitle = "Ball is coming…"
            instructionSubtitle = trainingMode == .partner
                ? ActivityInstructionData.partnerCoachPassTimingLine
                : "Coach: press PASS at the strike."
        case .cueRevealing:
            instructionTitle = "Decide now"
            instructionSubtitle = "Decide before expected arrival."
        case .cueVisible:
            instructionTitle = "Swipe now"
            instructionSubtitle = "Swipe immediately on contact."
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
        currentRepIndex = repIndex
        guard repIndex >= 0, repIndex < plan.count else {
            if repIndex >= plan.count {
                phase = .blockComplete
                updateInstructions()
            }
            return
        }
        passTriggeredAt = nil
        passTriggeredByRep[repIndex] = nil
        directionLoggedByRep[repIndex] = nil
        revealedGates = []
        showCheckCue = false
        cancelTimers()

        let delay = UnifiedScanToBeepTiming.randomDelaySeconds()
        #if DEBUG
        UnifiedScanToBeepTiming.logSchedule(
            activity: "oneTouchPassing",
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
            DispatchQueue.main.async { self?.onCheckFire(repIndex: repIndex) }
        }
        RunLoop.main.add(scanTimer!, forMode: .common)
    }

    private func onCheckFire(repIndex: Int) {
        guard case .armedScanning(let r, _) = phase, r == repIndex else { return }
        scanTimer?.invalidate()
        scanTimer = nil
        showCheckCue = true
        phase = .showingCheck(repIndex: repIndex)
        updateInstructions()

        checkEndTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.showCheckCue = false
                self.phase = .awaitingPassTrigger(repIndex: repIndex)
                self.updateInstructions()
            }
        }
        RunLoop.main.add(checkEndTimer!, forMode: .common)
    }

    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        guard case .awaitingPassTrigger(let r) = phase, r == repIndex else { return }
        passTriggeredAt = timestamp
        passTriggeredByRep[repIndex] = timestamp
        #if DEBUG
        DecisionSpeedDebugLog.logEngineRepLive(activity: .oneTouchPassing, repIndex: repIndex, passEmbeddedStored: timestamp)
        #endif
        cancelTimers()
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
            let spacing = config.revealSpacingSeconds * sessionAdaptiveDifficulty.cueDuration
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
            activity: "oneTouchPassing",
            repIndex: repIndex,
            configuredWindowSeconds: duration,
            note: "\(revealNote); phase=cueVisible (greens fixed window); CHECK cue 0.6s is separate earlier"
        )
        phase = .cueVisible(repIndex: repIndex, endsAt: endsAt)
        updateInstructions()

        cueHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onCueHide(repIndex: repIndex) }
        }
        RunLoop.main.add(cueHideTimer!, forMode: .common)
    }

    private func onCueHide(repIndex: Int) {
        guard case .cueVisible(let currentRep, _) = phase, currentRep == repIndex else { return }
        if let v = cueTimingDebugVisibleAt {
            let hiddenAt = Date()
            CueTimingDebugLog.logHidden(
                activity: "oneTouchPassing",
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
        checkEndTimer?.invalidate()
        checkEndTimer = nil
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
        case .cueVisible(let ri, _):
            rIdx = ri
            if ri == repIndex, let v = cueTimingDebugVisibleAt {
                CueTimingDebugLog.logHidden(
                    activity: "oneTouchPassing",
                    repIndex: repIndex,
                    visibleAt: v,
                    hiddenAt: Date(),
                    reason: "exit_logged"
                )
                cueTimingDebugVisibleAt = nil
            }
            cueHideTimer?.invalidate()
            cueHideTimer = nil
        case .cueRevealing(let ri, _): rIdx = ri
        default: return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            print("ERROR: Rep cannot complete without exitLogged")
            passTriggeredAt = nil
            return nil
        }

        let p = plan[repIndex]
        let correct = p.greenDirections.contains(gate)
        let expectedArrivalTime = triggerTime.addingTimeInterval(travelTimeSeconds)
        let decisionWindowSeconds = expectedArrivalTime.timeIntervalSince(timestamp)
        let score = adaptiveSessionScore(including: decisionWindowSeconds, isCorrect: correct)
        let speed: DecisionSpeed
        switch DecisionTimingModel.speedBucket(forDecisionWindow: decisionWindowSeconds, activity: .oneTouchPassing, score: score) {
        case .fast: speed = .fast
        case .medium: speed = .medium
        case .slow: speed = .slow
        }
        directionLoggedByRep[repIndex] = timestamp
        repDecisions.append(
            RepDecision(
                repIndex: repIndex,
                direction: gate,
                isCorrect: correct,
                decisionWindowSeconds: decisionWindowSeconds,
                bucket: Self.bucket(for: decisionWindowSeconds, score: score)
            )
        )
        applyAdaptiveAfterRep(wasCorrect: correct, decisionWindow: decisionWindowSeconds)
        print("[DecisionWindowDebug] repIndex=\(repIndex) passTS=\(triggerTime.timeIntervalSince1970) expectedArrivalTS=\(expectedArrivalTime.timeIntervalSince1970) decisionTS=\(timestamp.timeIntervalSince1970) decisionWindowSeconds=\(decisionWindowSeconds)")
        #if DEBUG
        let engineWallEntry = Date()
        DecisionSpeedDebugLog.logScoredRep(
            activity: .oneTouchPassing,
            repIndex: repIndex,
            passTimestamp: triggerTime,
            directionLogTimestamp: timestamp,
            rawDeltaSeconds: reactionTimeSeconds,
            difficulty: config.difficulty,
            engineEntryWallTime: engineWallEntry
        )
        #endif
        let result = OneTouchRepResult(
            repIndex: repIndex,
            correct: correct,
            chosenGate: gate,
            decisionTime: reactionTimeSeconds,
            decisionSpeed: speed,
            greenDirections: p.greenDirections
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

    /// Coach ✕ is not allowed to complete One-Touch reps; rep must end via exitLogged direction.
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri): rIdx = ri
        case .cueVisible(let ri, _):
            rIdx = ri
            if ri == repIndex, let v = cueTimingDebugVisibleAt {
                CueTimingDebugLog.logHidden(
                    activity: "oneTouchPassing",
                    repIndex: repIndex,
                    visibleAt: v,
                    hiddenAt: Date(),
                    reason: "incorrect_before_timer"
                )
                cueTimingDebugVisibleAt = nil
            }
            cueHideTimer?.invalidate()
            cueHideTimer = nil
        case .cueRevealing(let ri, _): rIdx = ri
        default: return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            print("ERROR: Rep cannot complete without exitLogged")
            passTriggeredAt = nil
            return nil
        }

        _ = reactionTimeSeconds
        print("ERROR: Rep cannot complete without exitLogged")
        return nil
    }

    var currentPlan: OneTouchRepPlan? {
        guard currentRepIndex >= 0, currentRepIndex < plan.count else { return nil }
        return plan[currentRepIndex]
    }

    deinit { cancelTimers() }

    func decisionSummary() -> (
        total: Int,
        correct: Int,
        accuracy: Double,
        avgTime: Double,
        fastCount: Int,
        mediumCount: Int,
        slowCount: Int
    ) {
        let total = repDecisions.count
        let correct = repDecisions.filter(\.isCorrect).count
        let avgTime = total > 0 ? repDecisions.map(\.decisionWindowSeconds).reduce(0, +) / Double(total) : 0
        let accuracy = total > 0 ? Double(correct) / Double(total) : 0
        let fastCount = repDecisions.filter { $0.bucket == .fast }.count
        let mediumCount = repDecisions.filter { $0.bucket == .medium }.count
        let slowCount = repDecisions.filter { $0.bucket == .slow }.count
        return (total, correct, accuracy, avgTime, fastCount, mediumCount, slowCount)
    }

    func computeDecisionScore() -> (score: Int, accuracy: Double, avgTime: Double) {
        let summary = decisionSummary()
        guard summary.total > 0 else { return (0, 0, 0) }

        let accuracyComponent = summary.accuracy
        let summaryScoreBaseline = Int((accuracyComponent * 100).rounded())
        let speedValues = repDecisions.map { decision in
            Self.speedScoreValue(for: decision.decisionWindowSeconds, score: summaryScoreBaseline)
        }
        let avgSpeedScore = speedValues.reduce(0, +) / Double(speedValues.count)
        let weighted = (accuracyComponent * 0.70) + (avgSpeedScore * 0.30)
        let score = Int((weighted * 100).rounded())
        return (score, summary.accuracy, summary.avgTime)
    }

    private var travelTimeSeconds: Double {
        CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
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
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: windows, activity: .oneTouchPassing)
    }

    private static func bucket(for decisionWindowSeconds: Double, score: Int) -> RepDecisionBucket {
        DecisionTimingModel.speedBucket(forDecisionWindow: decisionWindowSeconds, activity: .oneTouchPassing, score: score)
    }

    private static func speedScoreValue(for decisionWindowSeconds: Double, score: Int) -> Double {
        switch bucket(for: decisionWindowSeconds, score: score) {
        case .fast: return 1.0
        case .medium: return 0.85
        case .slow: return 0.4
        }
    }
}

// MARK: - Partner relay reconnect checkpoint (no scoring impact)

extension OneTouchPassingEngine: PartnerRelayCheckpointEmitting {
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
        case .showingCheck(let r):
            rep = r
            phaseToken = "showingCheck"
        case .awaitingPassTrigger(let r):
            rep = r
            phaseToken = "awaitingPassTrigger"
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
