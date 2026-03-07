//
//  TwoMinuteCriticalScanEngine.swift
//  FootballScanningAI
//
//  PBA V2 — State machine for iPad. nextRep → scan window → beep → passTriggered shows star → exitLogged.
//

import Foundation
import Combine

enum CriticalScanPhase: Equatable {
    case waitingForNextRep
    case armedScanning(repIndex: Int, starGate: Gate, endsAt: Date)
    case beepedAwaitingPass(repIndex: Int, starGate: Gate)
    case starVisible(repIndex: Int, starGate: Gate, endsAt: Date)
    case awaitingExitLog(repIndex: Int, starGate: Gate)
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
    private var starHideTimer: Timer?

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
        phase = .armedScanning(repIndex: repIndex, starGate: p.starGate, endsAt: endsAt)

        // Single fire path (asyncAfter) to avoid Timer/asyncAfter race; Timer kept as backup.
        scanDelayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex, starGate: p.starGate) }
        }
        RunLoop.main.add(scanDelayTimer!, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.onBeepFire(repIndex: repIndex, starGate: p.starGate)
        }
    }

    /// Max seconds before beep we still accept PASS (show ball) when in armedScanning.
    private static let earlyPassWindow: TimeInterval = 3.0

    func onBeepFire(repIndex: Int, starGate: Gate) {
        guard case .armedScanning(let r, _, _) = phase, r == repIndex else { return }
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        phase = .beepedAwaitingPass(repIndex: repIndex, starGate: starGate)
    }

    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        let starGate: Gate
        switch phase {
        case .beepedAwaitingPass(let rIdx, let g):
            guard rIdx == repIndex else { return }
            starGate = g
        case .armedScanning(let rIdx, let g, let endsAt):
            guard rIdx == repIndex else { return }
            guard endsAt.timeIntervalSinceNow <= Self.earlyPassWindow else { return }
            starGate = g
            cancelTimers()
        default:
            return
        }

        passTriggeredAt = timestamp
        infoShownAtForCurrentRep = timestamp
        starHideTimer?.invalidate()
        let duration = config.starVisibleSeconds
        let endsAt = Date().addingTimeInterval(duration)
        phase = .starVisible(repIndex: repIndex, starGate: starGate, endsAt: endsAt)

        starHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.transitionToAwaitingExitLog(repIndex: repIndex, starGate: starGate) }
        }
        RunLoop.main.add(starHideTimer!, forMode: .common)
    }

    func onExitLogged(repIndex: Int, gate: Gate, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri, _):
            rIdx = ri
        case .starVisible(let ri, _, _):
            rIdx = ri
            if ri != repIndex { return }
            starHideTimer?.invalidate()
            starHideTimer = nil
            infoHiddenAtForCurrentRep = Date()
        default:
            return
        }
        guard let ri = rIdx, ri == repIndex else { return }

        let p = plan[repIndex]
        let startedAt = startedAtForCurrentRep ?? Date()
        let infoShownAt = infoShownAtForCurrentRep ?? startedAt
        let infoHiddenAt = infoHiddenAtForCurrentRep ?? Date()
        let log = RepLog.from(
            repIndex: repIndex,
            starGate: p.starGate,
            exitedGate: gate,
            startedAt: startedAt,
            infoShownAt: infoShownAt,
            infoHiddenAt: infoHiddenAt,
            passTriggeredAt: passTriggeredAt,
            exitLoggedAt: timestamp
        )
        repLogs.append(log)

        if repIndex + 1 >= plan.count {
            phase = .complete
        } else {
            phase = .waitingForNextRep
        }
    }

    private func transitionToAwaitingExitLog(repIndex: Int, starGate: Gate) {
        starHideTimer?.invalidate()
        starHideTimer = nil
        infoHiddenAtForCurrentRep = Date()
        phase = .awaitingExitLog(repIndex: repIndex, starGate: starGate)
    }

    private func cancelTimers() {
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        starHideTimer?.invalidate()
        starHideTimer = nil
    }

    /// Call when app enters background so timers don't fire late when returning.
    func applicationDidEnterBackground() {
        cancelTimers()
    }

    deinit {
        cancelTimers()
    }
}
