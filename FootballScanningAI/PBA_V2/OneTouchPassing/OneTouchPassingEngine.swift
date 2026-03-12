//
//  OneTouchPassingEngine.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: scan → CHECK cue (0.6s) → awaiting pass → reveal green/red → cue visible → exit log.
//

import Foundation
import Combine

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

    private let config: OneTouchPassingConfig
    private let plan: [OneTouchRepPlan]
    private var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    private var scanTimer: Timer?
    private var checkEndTimer: Timer?
    private var revealTimers: [Timer] = []
    private var cueHideTimer: Timer?

    init(config: OneTouchPassingConfig, plan: [OneTouchRepPlan] = OneTouchPassingScenarioGenerator.generatePlan()) {
        self.config = config
        self.plan = plan
        updateInstructions()
    }

    private func updateInstructions() {
        switch phase {
        case .waitingForNextRep:
            instructionTitle = "Waiting for coach…"
            instructionSubtitle = "Scan the field."
        case .armedScanning:
            instructionTitle = "Scan freely"
            instructionSubtitle = "CHECK is coming."
        case .showingCheck:
            instructionTitle = "CHECK"
            instructionSubtitle = "Ball is coming…"
        case .awaitingPassTrigger:
            instructionTitle = "Ball is coming…"
            instructionSubtitle = "Coach: press PASS at the strike."
        case .cueRevealing:
            instructionTitle = "Decide now"
            instructionSubtitle = "Pass to any green."
        case .cueVisible:
            instructionTitle = "Decide now"
            instructionSubtitle = "Pass to any green."
        case .awaitingExitLog:
            instructionTitle = "Play the rep"
            instructionSubtitle = "Waiting for coach log…"
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
        revealedGates = []
        showCheckCue = false
        cancelTimers()

        let delay = config.randomCheckDelay()
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
        case .cueVisible(let ri, _): rIdx = ri
        case .cueRevealing(let ri, _): rIdx = ri
        default: return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            passTriggeredAt = nil
            if repIndex + 1 >= plan.count { phase = .blockComplete } else { phase = .waitingForNextRep }
            updateInstructions()
            return nil
        }

        let p = plan[repIndex]
        let correct = p.greenDirections.contains(gate)
        let speed = classifyDecisionSpeed(reactionTimeSeconds)
        let result = OneTouchRepResult(
            repIndex: repIndex,
            correct: correct,
            chosenGate: gate,
            decisionTime: reactionTimeSeconds,
            decisionSpeed: speed
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

    /// Called when coach taps ✕ (incorrect decision). Records rep as incorrect. Returns reaction time in seconds when saved; nil when discarded.
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
            if repIndex + 1 >= plan.count { phase = .blockComplete } else { phase = .waitingForNextRep }
            updateInstructions()
            return nil
        }

        let speed = classifyDecisionSpeed(reactionTimeSeconds)
        let result = OneTouchRepResult(
            repIndex: repIndex,
            correct: false,
            chosenGate: .down,
            decisionTime: reactionTimeSeconds,
            decisionSpeed: speed
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

    var currentPlan: OneTouchRepPlan? {
        guard currentRepIndex >= 0, currentRepIndex < plan.count else { return nil }
        return plan[currentRepIndex]
    }

    deinit { cancelTimers() }
}
