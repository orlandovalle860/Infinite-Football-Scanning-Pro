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

    private let config: TwoMinuteTestConfig
    private let plan: [RepPlan]
    private var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    private var startedAtForCurrentRep: Date?
    private var infoShownAtForCurrentRep: Date?
    private var infoHiddenAtForCurrentRep: Date?
    private var scanDelayTimer: Timer?
    private var ballHideTimer: Timer?

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
        startedAtForCurrentRep = Date()
        infoShownAtForCurrentRep = nil
        infoHiddenAtForCurrentRep = nil
        cancelTimers()

        let delay = Double.random(in: config.scanDelayRange)
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
        infoShownAtForCurrentRep = timestamp
        ballHideTimer?.invalidate()
        let duration = config.ballVisibleSeconds
        let endsAt = Date().addingTimeInterval(duration)
        phase = .ballVisible(repIndex: repIndex, ballGate: ballGate, endsAt: endsAt)

        ballHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.transitionToAwaitingExitLog(repIndex: repIndex, ballGate: ballGate) }
        }
        RunLoop.main.add(ballHideTimer!, forMode: .common)
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
        case .ballVisible(let ri, _, _):
            rIdx = ri
            if ri != repIndex { return nil }
            ballHideTimer?.invalidate()
            ballHideTimer = nil
            infoHiddenAtForCurrentRep = Date()
        default:
            return nil
        }
        guard let ri = rIdx, ri == repIndex else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            passTriggeredAt = nil
            if repIndex + 1 >= plan.count { phase = .complete } else { phase = .waitingForNextRep }
            return nil
        }

        let p = plan[repIndex]
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

    /// Called when coach taps ✕ (incorrect decision). Records rep as incorrect (exitedGate = wrong direction). Returns reaction time in seconds when saved; nil when discarded.
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        var ballGate: Gate?
        switch phase {
        case .awaitingExitLog(let ri, let g): if ri == repIndex { ballGate = g }
        case .ballVisible(let ri, let g, _): if ri == repIndex { ballGate = g; ballHideTimer?.invalidate(); ballHideTimer = nil; infoHiddenAtForCurrentRep = Date() }
        default: break
        }
        guard ballGate != nil else { return nil }
        guard let triggerTime = passTriggeredAt else { return nil }

        let reactionTimeSeconds = timestamp.timeIntervalSince(triggerTime)
        if reactionTimeSeconds > Self.maxReactionTimeSeconds {
            passTriggeredAt = nil
            if repIndex + 1 >= plan.count { phase = .complete } else { phase = .waitingForNextRep }
            return nil
        }

        let p = plan[repIndex]
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
}
