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
    @Published private(set) var phase: AwayFromPressurePhase = .waitingForNextRep {
        didSet {
            print("[PHASE] \(oldValue) → \(phase) [repIndex=\(currentRepIndex)]")
        }
    }
    @Published private(set) var repLogs: [AwayFromPressureRepLog] = []
    @Published var instructionTitle: String = ""
    @Published var instructionSubtitle: String = ""
    @Published private(set) var repDecisions: [RepDecision] = []

    private let config: AwayFromPressureConfig
    private let trainingMode: TrainingMode
    private let plan: [AwayFromPressureRepPlan]
    private(set) var currentRepIndex: Int = 0
    private var passTriggeredAt: Date?
    private var startedAtForCurrentRep: Date?
    /// Optional early direction (wire: `firstTouchLogged`) before exit; keyed by repIndex. See `CoachRemoteDecisionModelMIGRATION.md`.
    private var pendingFirstTouchByRep: [Int: (gate: Gate, timestamp: Date)] = [:]
    private var markerShownAtForCurrentRep: Date?
    private var markerHiddenAtForCurrentRep: Date?
    private var scanDelayTimer: Timer?
    private var markerHideTimer: Timer?
    /// [CueTiming-Debug] anchor for wedge visibility window (PASS → marker hide).
    private var cueTimingDebugVisibleAt: Date?
    private var passTriggeredByRep: [Int: Date] = [:]
    private var directionLoggedByRep: [Int: Date] = [:]
    private var adaptiveState = AdaptiveState()
    private var sessionAdaptiveDifficulty = DifficultySettings(cueDuration: 1.0, travelTime: 1.0, thresholdAdjustment: 0.0)

    init(config: AwayFromPressureConfig, trainingMode: TrainingMode = .solo, plan: [AwayFromPressureRepPlan] = AwayFromPressureRepPlanner.generatePlan()) {
        self.config = config
        self.trainingMode = trainingMode
        self.plan = plan
        updateInstructions()
    }

    private func commitPhase(_ newPhase: AwayFromPressurePhase) {
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
            instructionTitle = "Scan"
            if trainingMode == .partner {
                instructionSubtitle = ""
            } else {
                instructionSubtitle = "Scan for pressure.\nIdentify the safest space."
            }
        case .beepedAwaitingPass:
            instructionTitle = "Ball is coming"
            instructionSubtitle = trainingMode == .partner
                ? ""
                : "Coach: press PASS at the strike."
        case .markerVisible:
            instructionTitle = "Swipe now"
            instructionSubtitle = "Swipe away from pressure as the ball arrives."
        case .awaitingExitLog:
            instructionTitle = "Great anticipation"
            instructionSubtitle = "Coach logs your swipe direction (opposite the red = correct)."
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
                commitPhase(.blockComplete)
            }
            return
        }

        let p = plan[repIndex]
        passTriggeredAt = nil
        passTriggeredByRep[repIndex] = nil
        directionLoggedByRep[repIndex] = nil
        startedAtForCurrentRep = Date()
        markerShownAtForCurrentRep = nil
        markerHiddenAtForCurrentRep = nil
        cancelTimers()

        let delay = UnifiedScanToBeepTiming.randomDelaySeconds()
        #if DEBUG
        UnifiedScanToBeepTiming.logSchedule(
            activity: "awayFromPressure",
            delaySeconds: delay,
            difficulty: config.difficulty,
            loopLevel: config.curriculumLoopLevel,
            model: .unified
        )
        #endif
        let endsAt = Date().addingTimeInterval(delay)
        commitPhase(.armedScanning(repIndex: repIndex, pressureGate: p.pressureGate, endsAt: endsAt))

        scanDelayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex, pressureGate: p.pressureGate) }
        }
        RunLoop.main.add(scanDelayTimer!, forMode: .common)
    }

    func onBeepFire(repIndex: Int, pressureGate: Gate) {
        guard case .armedScanning(let r, _, _) = phase, r == repIndex else { return }
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        commitPhase(.beepedAwaitingPass(repIndex: repIndex, pressureGate: pressureGate))
    }

    func onPassTrigger(repIndex: Int, timestamp: Date) {
        guard repIndex == currentRepIndex else { return }
        let pressureGate: Gate
        switch phase {
        case .beepedAwaitingPass(let rIdx, let g) where rIdx == repIndex:
            pressureGate = g
        case .armedScanning(let rIdx, let g, _) where rIdx == repIndex:
            scanDelayTimer?.invalidate()
            scanDelayTimer = nil
            pressureGate = g
        default:
            return
        }

        passTriggeredAt = timestamp
        passTriggeredByRep[repIndex] = timestamp
        markerShownAtForCurrentRep = timestamp
        #if DEBUG
        DecisionSpeedDebugLog.logEngineRepLive(activity: .awayFromPressure, repIndex: repIndex, passEmbeddedStored: timestamp)
        #endif
        markerHideTimer?.invalidate()
        let duration = config.markerVisibleSeconds * sessionAdaptiveDifficulty.travelTime
        let endsAt = Date().addingTimeInterval(duration)
        cueTimingDebugVisibleAt = Date()
        CueTimingDebugLog.logVisible(
            activity: "awayFromPressure",
            repIndex: repIndex,
            configuredWindowSeconds: duration,
            note: "PASS→markerVisible wedge reveal anim 0.22s in DangerZoneOverlay separate from timer"
        )
        commitPhase(.markerVisible(repIndex: repIndex, pressureGate: pressureGate, endsAt: endsAt))

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
        if case .waitingForNextRep = phase {
            return nil
        }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri, _):
            rIdx = ri
        case .markerVisible(let ri, _, _):
            rIdx = ri
            if ri != repIndex { return nil }
            CueTimingDebugLog.logHidden(
                activity: "awayFromPressure",
                repIndex: repIndex,
                visibleAt: cueTimingDebugVisibleAt,
                hiddenAt: Date(),
                reason: "exit_logged_before_timer"
            )
            cueTimingDebugVisibleAt = nil
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
            cancelTimers()
            if repIndex + 1 >= plan.count { commitPhase(.blockComplete) } else { commitPhase(.waitingForNextRep) }
            return nil
        }

        #if DEBUG
        let engineWallEntry = Date()
        DecisionSpeedDebugLog.logScoredRep(
            activity: .awayFromPressure,
            repIndex: repIndex,
            passTimestamp: triggerTime,
            directionLogTimestamp: timestamp,
            rawDeltaSeconds: reactionTimeSeconds,
            difficulty: config.difficulty,
            visualRevealTimestamp: markerShownAtForCurrentRep,
            engineEntryWallTime: engineWallEntry
        )
        #endif

        let p = plan[repIndex]
        let expectedArrivalTime = triggerTime.addingTimeInterval(travelTimeSeconds)
        let decisionWindowSeconds = expectedArrivalTime.timeIntervalSince(timestamp)
        let score = adaptiveSessionScore(including: decisionWindowSeconds, isCorrect: gate == p.pressureGate.opposite)
        directionLoggedByRep[repIndex] = timestamp
        repDecisions.append(
            RepDecision(
                repIndex: repIndex,
                direction: gate,
                isCorrect: gate == p.pressureGate.opposite,
                decisionWindowSeconds: decisionWindowSeconds,
                bucket: Self.bucket(for: decisionWindowSeconds, score: score)
            )
        )
        applyAdaptiveAfterRep(wasCorrect: gate == p.pressureGate.opposite, decisionWindow: decisionWindowSeconds)
        CurrentSessionStore.shared.recordDecisionTimingCalibrationSample(
            decisionWindowSeconds: decisionWindowSeconds,
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
        )
        print("[DecisionWindowDebug] repIndex=\(repIndex) passTS=\(triggerTime.timeIntervalSince1970) expectedArrivalTS=\(expectedArrivalTime.timeIntervalSince1970) decisionTS=\(timestamp.timeIntervalSince1970) decisionWindowSeconds=\(decisionWindowSeconds)")
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

        cancelTimers()
        if repIndex + 1 >= plan.count {
            commitPhase(.blockComplete)
        } else {
            commitPhase(.waitingForNextRep)
        }
        return reactionTimeSeconds
    }

    /// Coach ✕ — `exitedGate` nil; required when marking wrong without a direction. See `CoachRemoteDecisionModelMIGRATION.md`.
    func onIncorrectDecision(repIndex: Int, timestamp: Date) -> Double? {
        guard repIndex == currentRepIndex else { return nil }
        if case .waitingForNextRep = phase {
            return nil
        }
        var rIdx: Int?
        switch phase {
        case .awaitingExitLog(let ri, _):
            rIdx = ri
        case .markerVisible(let ri, _, _):
            rIdx = ri
            if ri != repIndex { return nil }
            CueTimingDebugLog.logHidden(
                activity: "awayFromPressure",
                repIndex: repIndex,
                visibleAt: cueTimingDebugVisibleAt,
                hiddenAt: Date(),
                reason: "incorrect_before_timer"
            )
            cueTimingDebugVisibleAt = nil
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
            cancelTimers()
            if repIndex + 1 >= plan.count { commitPhase(.blockComplete) } else { commitPhase(.waitingForNextRep) }
            return nil
        }

        #if DEBUG
        let engineWallEntryIncorrect = Date()
        DecisionSpeedDebugLog.logScoredRep(
            activity: .awayFromPressure,
            repIndex: repIndex,
            passTimestamp: triggerTime,
            directionLogTimestamp: timestamp,
            rawDeltaSeconds: reactionTimeSeconds,
            difficulty: config.difficulty,
            visualRevealTimestamp: markerShownAtForCurrentRep,
            engineEntryWallTime: engineWallEntryIncorrect
        )
        #endif

        let p = plan[repIndex]
        let expectedArrivalTimeIncorrect = triggerTime.addingTimeInterval(travelTimeSeconds)
        let decisionWindowSecondsIncorrect = expectedArrivalTimeIncorrect.timeIntervalSince(timestamp)
        applyAdaptiveAfterRep(wasCorrect: false, decisionWindow: decisionWindowSecondsIncorrect)
        CurrentSessionStore.shared.recordDecisionTimingCalibrationSample(
            decisionWindowSeconds: decisionWindowSecondsIncorrect,
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
        )
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

        cancelTimers()
        if repIndex + 1 >= plan.count {
            commitPhase(.blockComplete)
        } else {
            commitPhase(.waitingForNextRep)
        }
        return reactionTimeSeconds
    }

    /// Wire: `firstTouchLogged` — optional early action before exit. Cached until `onExitLogged` merges into the rep log.
    func onFirstTouchLogged(repIndex: Int, gate: Gate, timestamp: Date) {
        guard repIndex >= 0, repIndex < plan.count else { return }
        pendingFirstTouchByRep[repIndex] = (gate, timestamp)
    }

    private func transitionToAwaitingExitLog(repIndex: Int, pressureGate: Gate) {
        guard case .markerVisible(let r, let g, _) = phase, r == repIndex, g == pressureGate else {
            markerHideTimer?.invalidate()
            markerHideTimer = nil
            return
        }
        CueTimingDebugLog.logHidden(
            activity: "awayFromPressure",
            repIndex: repIndex,
            visibleAt: cueTimingDebugVisibleAt,
            hiddenAt: Date(),
            reason: "marker_hide_timer"
        )
        cueTimingDebugVisibleAt = nil
        markerHideTimer?.invalidate()
        markerHideTimer = nil
        markerHiddenAtForCurrentRep = Date()
        commitPhase(.awaitingExitLog(repIndex: repIndex, pressureGate: pressureGate))
    }

    private func cancelTimers() {
        scanDelayTimer?.invalidate()
        scanDelayTimer = nil
        markerHideTimer?.invalidate()
        markerHideTimer = nil
    }

    /// Clears the finished block and returns to the first rep’s waiting state (same config/mode). Used by “Run It Back” on the display.
    func restartBlockFromBeginning() {
        cancelTimers()
        cueTimingDebugVisibleAt = nil
        currentRepIndex = 0
        passTriggeredAt = nil
        startedAtForCurrentRep = nil
        markerShownAtForCurrentRep = nil
        markerHiddenAtForCurrentRep = nil
        passTriggeredByRep.removeAll()
        directionLoggedByRep.removeAll()
        pendingFirstTouchByRep.removeAll()
        repLogs.removeAll()
        repDecisions.removeAll()
        adaptiveState = AdaptiveState()
        sessionAdaptiveDifficulty = DifficultySettings(cueDuration: 1.0, travelTime: 1.0, thresholdAdjustment: 0.0)
        CurrentSessionStore.shared.resetDecisionTimingCalibrationForNewDrillBlock(
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
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
        startedAtForCurrentRep = nil
        markerShownAtForCurrentRep = nil
        markerHiddenAtForCurrentRep = nil
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
        startedAtForCurrentRep = nil
        markerShownAtForCurrentRep = nil
        markerHiddenAtForCurrentRep = nil
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

    /// After foreground: reschedule scan / marker-hide timers from phase deadlines.
    func synchronizeTimersAfterEnteringForeground() {
        let now = Date()
        switch phase {
        case .armedScanning(let repIndex, let pressureGate, let endsAt):
            if now >= endsAt {
                onBeepFire(repIndex: repIndex, pressureGate: pressureGate)
            } else {
                let remaining = max(0.01, endsAt.timeIntervalSince(now))
                scanDelayTimer?.invalidate()
                scanDelayTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { self?.onBeepFire(repIndex: repIndex, pressureGate: pressureGate) }
                }
                if let t = scanDelayTimer { RunLoop.main.add(t, forMode: .common) }
            }
        case .markerVisible(let repIndex, let pressureGate, let endsAt):
            if now >= endsAt {
                transitionToAwaitingExitLog(repIndex: repIndex, pressureGate: pressureGate)
            } else {
                let remaining = max(0.01, endsAt.timeIntervalSince(now))
                markerHideTimer?.invalidate()
                markerHideTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async { self?.transitionToAwaitingExitLog(repIndex: repIndex, pressureGate: pressureGate) }
                }
                if let t = markerHideTimer { RunLoop.main.add(t, forMode: .common) }
            }
        default:
            break
        }
    }

    deinit {
        cancelTimers()
    }

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
        let speedValues = repDecisions.map { Self.speedScoreValue(for: $0.decisionWindowSeconds, score: summaryScoreBaseline) }
        let avgSpeedScore = speedValues.reduce(0, +) / Double(speedValues.count)
        let weighted = (accuracyComponent * 0.70) + (avgSpeedScore * 0.30)
        let score = Int((weighted * 100).rounded())
        return (score, summary.accuracy, summary.avgTime)
    }

    private var travelTimeSeconds: Double {
        let base = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
        return CurrentSessionStore.shared.calibratedBallTravelSeconds(
            baseNominal: base,
            activityId: ActivityKind.awayFromPressure.sessionActivityActivityId
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
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: windows, activity: .awayFromPressure)
    }

    private static func bucket(for decisionWindowSeconds: Double, score: Int) -> RepDecisionBucket {
        DecisionTimingModel.speedBucket(forDecisionWindow: decisionWindowSeconds, activity: .awayFromPressure, score: score)
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

extension AwayFromPressureEngine: PartnerRelayCheckpointEmitting {
    func partnerRelayCheckpointPayload(activityId: String, relaySessionId: String?) -> PartnerRelayCheckpointPayload {
        let rep: Int
        let phaseToken: String
        switch phase {
        case .waitingForNextRep:
            rep = repLogs.count
            phaseToken = "waitingForNextRep"
        case .blockComplete:
            rep = plan.count
            phaseToken = "blockComplete"
        case .armedScanning(let r, _, _):
            rep = r
            phaseToken = "armedScanning"
        case .beepedAwaitingPass(let r, _):
            rep = r
            phaseToken = "beepedAwaitingPass"
        case .markerVisible(let r, _, _):
            rep = r
            phaseToken = "markerVisible"
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
