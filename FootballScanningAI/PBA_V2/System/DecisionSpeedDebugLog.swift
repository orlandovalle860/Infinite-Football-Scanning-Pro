//
//  DecisionSpeedDebugLog.swift
//  FootballScanningAI
//
//  DEBUG-only: full chain from coach send → relay → display → engine → bucket.
//  Bucketing uses ONLY embedded timestamps from messages (coach `Date()` at send); relay/main-queue delay is NOT added to rawDelta.
//

import Foundation

#if DEBUG
enum DecisionSpeedDebugLog {
    private static var chainSeq: Int = 0
    private static func nextSeq() -> Int {
        chainSeq += 1
        return chainSeq
    }

    // MARK: - Coach (outbound)

    /// Coach remote: `embeddedTimestamp` is the same `Date()` passed into `RemoteService.sendPassTriggered` / wire payload (handler runs synchronously with `CoachRemoteFeedbackTap` action — see `CoachRemoteButtonFeedback.swift`).
    static func logCoachPassSend(activity: ActivityKind, repIndex: Int, embeddedTimestamp: Date) {
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=COACH_PASS_SEND activity=\(activity.rawValue) rep=\(repIndex) passEmbeddedTS=\(ts(embeddedTimestamp)) NOTE=embedded_is_Date_in_button_action_same_runLoop_as_touch_not_UITouch_timestamp")
    }

    static func logCoachExitSend(activity: ActivityKind, repIndex: Int, gate: Gate, embeddedTimestamp: Date) {
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=COACH_DIR_SEND activity=\(activity.rawValue) rep=\(repIndex) gate=\(gate.rawValue) directionEmbeddedTS=\(ts(embeddedTimestamp)) NOTE=embedded_is_Date_immediately_before_sendExitLogged_same_as_wire")
    }

    static func logCoachIncorrectSend(activity: ActivityKind, repIndex: Int, embeddedTimestamp: Date) {
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=COACH_INCORRECT_SEND activity=\(activity.rawValue) rep=\(repIndex) incorrectEmbeddedTS=\(ts(embeddedTimestamp)) NOTE=same_clock_as_exitLogged")
    }

    // MARK: - Display (relay ingress)

    /// Display: message delivered on main after `WebSocketRemoteTransport.deliverTwoMinuteMessage` async; `embeddedTimestamp` is decoded from JSON (coach clock instant).
    static func logDisplayRelayIngress(activity: ActivityKind, kind: String, repIndex: Int, embeddedTimestamp: Date, displayReceiveWallTime: Date) {
        let lag = displayReceiveWallTime.timeIntervalSince(embeddedTimestamp)
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=DISPLAY_RELAY_INGRESS activity=\(activity.rawValue) kind=\(kind) rep=\(repIndex) embeddedTS=\(ts(embeddedTimestamp)) displayReceiveWallTS=\(ts(displayReceiveWallTime)) receiveLagAfterEmbedded=\(fmt(lag))s NOTE=relay_mainAsync_lag_NOT_in_rawDelta")
    }

    /// Display: immediately before `engine.onPassTrigger` / apply pass.
    static func logDisplayBeforeEnginePass(activity: ActivityKind, repIndex: Int, embeddedPass: Date, displayWallBeforeEngine: Date) {
        let d = displayWallBeforeEngine.timeIntervalSince(embeddedPass)
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=DISPLAY_BEFORE_ENGINE_PASS activity=\(activity.rawValue) rep=\(repIndex) embeddedPassTS=\(ts(embeddedPass)) displayWallBeforeEngine=\(ts(displayWallBeforeEngine)) delayAfterEmbedded=\(fmt(d))s NOTE=delay_NOT_in_rawDelta")
    }

    /// Display: immediately before `engine.onExitLogged` / `onIncorrectDecision` (direction or ✕ processed on main).
    static func logDisplayBeforeEngineExit(activity: ActivityKind, repIndex: Int, embeddedDirection: Date, displayWallBeforeEngine: Date, kind: String) {
        let d = displayWallBeforeEngine.timeIntervalSince(embeddedDirection)
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=DISPLAY_BEFORE_ENGINE_EXIT kind=\(kind) activity=\(activity.rawValue) rep=\(repIndex) embeddedDirectionTS=\(ts(embeddedDirection)) displayWallBeforeEngine=\(ts(displayWallBeforeEngine)) delayAfterEmbedded=\(fmt(d))s NOTE=delay_NOT_in_rawDelta")
    }

    // MARK: - Engine (bucket path)

    /// Engine: `passTriggeredAt` set; rep is live for direction logging (after successful `onPassTrigger`).
    static func logEngineRepLive(activity: ActivityKind, repIndex: Int, passEmbeddedStored: Date) {
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=ENGINE_REP_LIVE activity=\(activity.rawValue) rep=\(repIndex) passTriggeredAt_set=\(ts(passEmbeddedStored))")
    }

    /// Solo/wall display: pass time is `Date()` at display tap (not coach-embedded).
    static func logSoloDisplayPassTrigger(activity: ActivityKind, repIndex: Int, displayWallPassTS: Date) {
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=SOLO_DISPLAY_PASS activity=\(activity.rawValue) rep=\(repIndex) passTS=\(ts(displayWallPassTS)) NOTE=display_Date_at_tap")
    }

    static func logSoloDisplayExitTrigger(activity: ActivityKind, repIndex: Int, gate: Gate, displayWallExitTS: Date) {
        print("[DecisionSpeedDebug] seq=\(nextSeq()) chain=SOLO_DISPLAY_EXIT activity=\(activity.rawValue) rep=\(repIndex) gate=\(gate.rawValue) exitTS=\(ts(displayWallExitTS)) NOTE=display_Date_at_tap")
    }

    /// Per-rep log when a rep is committed. `rawDeltaSeconds` = directionLogTimestamp − passTimestamp (engine); **network and main-queue delivery are not added** — only embedded coach timestamps.
    static func logScoredRep(
        activity: ActivityKind,
        repIndex: Int,
        passTimestamp: Date?,
        directionLogTimestamp: Date,
        rawDeltaSeconds: Double,
        difficulty: TestDifficulty?,
        visualRevealTimestamp: Date? = nil,
        triggerAnchor: String = "passTriggeredAt",
        engineEntryWallTime: Date
    ) {
        let travel = DecisionTimingModel.expectedBallTravelTime(activity: activity, difficulty: difficulty)
        let passForArrival = passTimestamp ?? directionLogTimestamp
        let expectedArrival = passForArrival.addingTimeInterval(travel)
        let window = DecisionTimingModel.decisionWindow(
            rawRepInterval: rawDeltaSeconds,
            activity: activity,
            difficulty: difficulty
        )
        let bucket = TimingThresholds.speedBucket(for: rawDeltaSeconds, activity: activity)
        let thr = thresholdSummary(activity: activity)
        let processingLagAfterEmbeddedDirection = engineEntryWallTime.timeIntervalSince(directionLogTimestamp)

        var line = """
        [DecisionSpeedDebug] seq=\(nextSeq()) chain=ENGINE_BUCKET activity=\(activity.rawValue) rep=\(repIndex) triggerAnchor=\(triggerAnchor) \
        passTS=\(ts(passTimestamp)) directionEmbeddedTS=\(ts(directionLogTimestamp)) \
        rawDeltaSeconds_FOR_BUCKET=\(fmt(rawDeltaSeconds)) \
        engineEntryWallTS=\(ts(engineEntryWallTime)) processingLagAfterDirectionEmbedded=\(fmt(processingLagAfterEmbeddedDirection))s \
        expectedBallTravel=\(fmt(travel)) expectedArrivalTS=\(ts(expectedArrival)) decisionWindow=\(fmt(window)) \
        thresholds=\(thr) finalBucket=\(bucket.rawValue)
        """
        if let v = visualRevealTimestamp {
            line += " visualRevealTS=\(ts(v))"
        }
        line += " NOTE=rawDelta_uses_only_embedded_pass_and_direction_timestamps_processingLag_NOT_in_bucket"
        print(line.replacingOccurrences(of: "\n", with: " "))
    }

    /// Away From Pressure block summary: per-rep buckets + average (headline uses dominant bucket; see `[UniversalSummaryBucket-Debug]`).
    static func logAwayFromPressureAggregate(logs: [AwayFromPressureRepLog], difficulty: TestDifficulty?) {
        let times = logs.compactMap(\.decisionTimeSeconds)
        guard !times.isEmpty else { return }
        let avg = times.reduce(0, +) / Double(times.count)
        var f = 0, m = 0, s = 0
        for t in times {
            switch TimingThresholds.pressureSpeedBucket(for: t) {
            case .fast: f += 1
            case .medium: m += 1
            case .slow: s += 1
            }
        }
        let res = UniversalBlockSummaryHeadline.resolve(fast: f, medium: m, slow: s)
        let headline = res.bucket
        let tie = res.tieBreakApplied
        print("[DecisionSpeedDebug] seq=\(nextSeq()) aggregate=AFP_block_summary difficulty=\(difficulty?.rawValue ?? "nil") repCount=\(times.count) avgRawDeltaSeconds=\(fmt(avg)) headlineBucketFromDominant=\(headline.rawValue) tieBreak=\(tie ? "worse_wins" : "none") NOTE=headline_matches_UniversalBlockSummaryHeadline")
        for log in logs {
            guard let t = log.decisionTimeSeconds else { continue }
            let b = TimingThresholds.pressureSpeedBucket(for: t)
            print("[DecisionSpeedDebug] aggregateRep repIndex=\(log.repIndex) rawDelta=\(fmt(t)) bucket=\(b.rawValue)")
        }
    }

    private static func ts(_ d: Date?) -> String {
        guard let d else { return "nil" }
        return String(format: "%.4f", d.timeIntervalSince1970)
    }

    private static func fmt(_ x: Double) -> String { String(format: "%.4f", x) }

    private static func thresholdSummary(activity: ActivityKind) -> String {
        switch activity {
        case .awayFromPressure:
            return "AFP_fast_lt_\(TimingThresholds.pressureFast)_medium_to_\(TimingThresholds.pressureMediumUpper)"
        case .dribbleOrPass:
            return "DOP_fast_lt_\(TimingThresholds.dribblePassFast)_medium_to_\(TimingThresholds.dribblePassMediumUpper)"
        case .oneTouchPassing:
            return "OTP_fast_lt_\(TimingThresholds.oneTouchFast)_medium_to_\(TimingThresholds.oneTouchMediumUpper)"
        case .twoMinuteTest:
            return "2MT_fast_lt_\(TimingThresholds.twoMinuteFast)_medium_lt_\(TimingThresholds.twoMinuteMediumUpper)"
        }
    }
}
#endif
