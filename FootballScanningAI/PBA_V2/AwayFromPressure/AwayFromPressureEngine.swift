//
//  AwayFromPressureEngine.swift
//  FootballScanningAI
//
//  PBA V2 — State machine: nextRep → scan → beep → passTriggered shows danger zone → exitLogged.
//

import Foundation
import Combine

enum AwayFromPressurePhase: Equatable {
    case waitingForNextRep
    case armedScanning(repIndex: Int, pressureGate: Gate, endsAt: Date)
    case beepedAwaitingPass(repIndex: Int, pressureGate: Gate)
    case markerVisible(repIndex: Int, pressureGate: Gate, endsAt: Date)
    case awaitingExitLog(repIndex: Int, pressureGate: Gate)
    case blockComplete
}

final class AwayFromPressureEngine: ObservableObject {
    @Published private(set) var phase: AwayFromPressurePhase = .waitingForNextRep
    @Published private(set) var repLogs: [AwayFromPressureRepLog] = []
    @Published var instructionTitle: String = ""
    @Published var instructionSubtitle: String = ""

    private let config: AwayFromPressureConfig
    private let plan: [AwayFromPressureRepPlan]
    private var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    private var startedAtForCurrentRep: Date?
    /// Optional early direction (wire: `firstTouchLogged`) before exit; keyed by repIndex. See `CoachRemoteDecisionModelMIGRATION.md`.
    private var pendingFirstTouchByRep: [Int: (gate: Gate, timestamp: Date)] = [:]
    private var markerShownAtForCurrentRep: Date?
    private var markerHiddenAtForCurrentRep: Date?
    private var scanDelayTimer: Timer?
    private var markerHideTimer: Timer?

    init(config: AwayFromPressureConfig, plan: [AwayFromPressureRepPlan] = AwayFromPressureRepPlanner.generatePlan()) {
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
            instructionTitle = "Scan"
            instructionSubtitle = "Be ready to turn away from pressure."
        case .beepedAwaitingPass:
            instructionTitle = "Ball is coming"
            instructionSubtitle = "Coach: press PASS at the strike."
        case .markerVisible:
            instructionTitle = "Turn away from pressure"
            instructionSubtitle = "Move opposite the red — into space."
        case .awaitingExitLog:
            instructionTitle = "Waiting for coach"
            instructionSubtitle = "They log your turn (opposite the red = correct)."
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

        let p = plan[repIndex]
        passTriggeredAt = nil
        startedAtForCurrentRep = Date()
        markerShownAtForCurrentRep = nil
        markerHiddenAtForCurrentRep = nil
        cancelTimers()

        let delay = Double.random(in: config.scanDelayRange)
        let endsAt = Date().addingTimeInterval(delay)
        phase = .armedScanning(repIndex: repIndex, pressureGate: p.pressureGate, endsAt: endsAt)
        updateInstructions()

        scanDelayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex, pressureGate: p.pressureGate) }
        }
        RunLoop.main.add(scanDelayTimer!, forMode: .common)
    }

    func onBeepFire(repIndex: Int, pressureGate: Gate) {
        guard case .armedScanning(let r, _, _) = phase, r == repIndex else { return }
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        phase = .beepedAwaitingPass(repIndex: repIndex, pressureGate: pressureGate)
        updateInstructions()
    }

    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        guard case .beepedAwaitingPass(let rIdx, let pressureGate) = phase, rIdx == repIndex else { return }

        passTriggeredAt = timestamp
        markerShownAtForCurrentRep = timestamp
        markerHideTimer?.invalidate()
        let duration = config.markerVisibleSeconds
        let endsAt = Date().addingTimeInterval(duration)
        phase = .markerVisible(repIndex: repIndex, pressureGate: pressureGate, endsAt: endsAt)
        updateInstructions()

        markerHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.transitionToAwaitingExitLog(repIndex: repIndex, pressureGate: pressureGate) }
        }
        RunLoop.main.add(markerHideTimer!, forMode: .common)
    }

    /// Max reaction time (trigger → confirmation); reps above this are discarded.
    private static let maxReactionTimeSeconds: TimeInterval = 2.0

    /// Returns reaction time in seconds when rep was saved; nil when discarded.
    func onExitLogged(repIndex: Int, gate: Gate, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri, _):
            rIdx = ri
        case .markerVisible(let ri, _, _):
            rIdx = ri
            if ri != repIndex { return nil }
            markerHideTimer?.invalidate()
            markerHideTimer = nil
            markerHiddenAtForCurrentRep = Date()
        default:
            return nil
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
        let startedAt = startedAtForCurrentRep ?? Date()
        let markerShownAt = markerShownAtForCurrentRep ?? startedAt
        let markerHiddenAt = markerHiddenAtForCurrentRep ?? Date()
        let pending = pendingFirstTouchByRep[repIndex]
        let log = AwayFromPressureRepLog(
            repIndex: repIndex,
            pressureGate: p.pressureGate,
            exitedGate: gate,
            startedAt: startedAt,
            markerShownAt: markerShownAt,
            markerHiddenAt: markerHiddenAt,
            passTriggeredAt: passTriggeredAt,
            exitLoggedAt: timestamp,
            firstTouchGate: pending?.gate,
            firstTouchLoggedAt: pending?.timestamp
        )
        repLogs.append(log)
        pendingFirstTouchByRep[repIndex] = nil
        passTriggeredAt = nil

        if repIndex + 1 >= plan.count {
            phase = .blockComplete
        } else {
            phase = .waitingForNextRep
        }
        updateInstructions()
        return reactionTimeSeconds
    }

    /// Coach ✕ — `exitedGate` nil; required when marking wrong without a direction. See `CoachRemoteDecisionModelMIGRATION.md`.
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri, _):
            rIdx = ri
        case .markerVisible(let ri, _, _):
            rIdx = ri
            if ri != repIndex { return nil }
            markerHideTimer?.invalidate()
            markerHideTimer = nil
            markerHiddenAtForCurrentRep = Date()
        default:
            return nil
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
        let startedAt = startedAtForCurrentRep ?? Date()
        let markerShownAt = markerShownAtForCurrentRep ?? startedAt
        let markerHiddenAt = markerHiddenAtForCurrentRep ?? Date()
        let log = AwayFromPressureRepLog(
            repIndex: repIndex,
            pressureGate: p.pressureGate,
            exitedGate: nil,
            startedAt: startedAt,
            markerShownAt: markerShownAt,
            markerHiddenAt: markerHiddenAt,
            passTriggeredAt: passTriggeredAt,
            exitLoggedAt: timestamp,
            firstTouchGate: nil,
            firstTouchLoggedAt: nil
        )
        repLogs.append(log)
        passTriggeredAt = nil

        if repIndex + 1 >= plan.count {
            phase = .blockComplete
        } else {
            phase = .waitingForNextRep
        }
        updateInstructions()
        return reactionTimeSeconds
    }

    /// Wire: `firstTouchLogged` — optional early action before exit. Cached until `onExitLogged` merges into the rep log.
    func onFirstTouchLogged(repIndex: Int, gate: Gate, timestamp: Date) {
        guard repIndex >= 0, repIndex < plan.count else { return }
        pendingFirstTouchByRep[repIndex] = (gate, timestamp)
    }

    private func transitionToAwaitingExitLog(repIndex: Int, pressureGate: Gate) {
        markerHideTimer?.invalidate()
        markerHideTimer = nil
        markerHiddenAtForCurrentRep = Date()
        phase = .awaitingExitLog(repIndex: repIndex, pressureGate: pressureGate)
        updateInstructions()
    }

    private func cancelTimers() {
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        markerHideTimer?.invalidate()
        markerHideTimer = nil
    }

    /// Call when app enters background so timers don't fire late when returning.
    func applicationDidEnterBackground() {
        cancelTimers()
    }

    deinit {
        cancelTimers()
    }
}
