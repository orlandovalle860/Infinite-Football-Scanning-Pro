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
    private let plan: [DribbleOrPassRepPlan]
    private var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    /// First-touch can be logged before exit; keyed by repIndex.
    private var pendingFirstTouchByRep: [Int: (gate: Gate, timestamp: Date)] = [:]
    private var scanTimer: Timer?
    private var revealTimers: [Timer] = []
    private var cueHideTimer: Timer?

    init(config: DribbleOrPassConfig, plan: [DribbleOrPassRepPlan] = DribbleOrPassScenarioGenerator.generatePlan()) {
        self.config = config
        self.plan = plan
        updateInstructions()
    }

    private func updateInstructions() {
        switch phase {
        case .waitingForNextRep:
            instructionTitle = "Waiting for coach…"
            instructionSubtitle = "Keep moving. Check both shoulders."
        case .armedScanning:
            instructionTitle = "Scan freely"
            instructionSubtitle = "Beep is coming."
        case .beepedAwaitingPass:
            instructionTitle = "Ball is coming"
            instructionSubtitle = "Coach: press PASS at the strike."
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
        cancelTimers()

        let delay = config.scanWindowSeconds
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

    func onExitLogged(repIndex: Int, gate: Gate, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri): rIdx = ri
        case .cueVisible(let ri, _): rIdx = ri
        case .cueRevealing(let ri, _): rIdx = ri
        default: return
        }
        guard let ri = rIdx, ri == repIndex else { return }

        let p = plan[repIndex]
        let correct = (gate == p.expectedCorrectGate)
        let passTime = passTriggeredAt ?? Date()
        let pending = pendingFirstTouchByRep[repIndex]
        let decisionTime: Double
        let firstTouchGate: Gate?
        if let first = pending {
            decisionTime = first.timestamp.timeIntervalSince(passTime)
            firstTouchGate = first.gate
        } else {
            decisionTime = timestamp.timeIntervalSince(passTime)
            firstTouchGate = nil
        }
        pendingFirstTouchByRep[repIndex] = nil
        let speed = TimingThresholds.dribblePassDecisionSpeed(for: decisionTime)
        let decisionPoints = dribbleOrPassDecisionPoints(plan: p, chosenGate: gate)
        let timingBonus = dribbleOrPassTimingBonus(speed)
        let result = DribbleOrPassRepResult(
            repIndex: repIndex,
            correct: correct,
            decisionTime: decisionTime,
            decisionSpeed: speed,
            expectedGate: p.expectedCorrectGate,
            chosenGate: gate,
            decisionPoints: decisionPoints,
            timingBonus: timingBonus,
            firstTouchGate: firstTouchGate
        )
        repResults.append(result)

        if repIndex + 1 >= plan.count {
            phase = .blockComplete
        } else {
            phase = .waitingForNextRep
        }
        updateInstructions()
    }

    /// Called when coach logs first touch (before or after exit). If before exit, cached and applied when exit is logged.
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
