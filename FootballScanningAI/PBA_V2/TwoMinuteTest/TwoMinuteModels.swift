//
//  TwoMinuteModels.swift
//  FootballScanningAI
//
//  PBA V2 — RepLog and relay message types.
//
//  **Compatibility:** `TwoMinuteMessage` `kind` strings (`firstTouchLogged`, `incorrectDecision`, …) are
//  part of the on-wire protocol — see `CoachRemoteDecisionModelMIGRATION.md` before renaming.
//

import Foundation

/// One completed rep: ball gate, exited gate, timestamps.
struct RepLog: Codable {
    let repIndex: Int
    let ballGate: Gate
    let exitedGate: Gate
    let startedAt: Date
    let infoShownAt: Date
    let infoHiddenAt: Date
    let passTriggeredAt: Date?
    let exitLoggedAt: Date

    var correct: Bool { ballGate == exitedGate }

    static func from(
        repIndex: Int,
        ballGate: Gate,
        exitedGate: Gate,
        startedAt: Date,
        infoShownAt: Date,
        infoHiddenAt: Date,
        passTriggeredAt: Date?,
        exitLoggedAt: Date
    ) -> RepLog {
        RepLog(
            repIndex: repIndex,
            ballGate: ballGate,
            exitedGate: exitedGate,
            startedAt: startedAt,
            infoShownAt: infoShownAt,
            infoHiddenAt: infoHiddenAt,
            passTriggeredAt: passTriggeredAt,
            exitLoggedAt: exitLoggedAt
        )
    }
}

// MARK: - Multipeer / relay messages (payload prefix pba2:)

/// Partner session messages. **Do not rename cases** without a protocol migration — JSON `kind` must stay backward compatible.
enum TwoMinuteMessage: Codable {
    case nextRep(repIndex: Int)
    case repStarted(repIndex: Int, timestamp: Date)
    /// Display → coach signal that the iPad's pre-beep random delay has elapsed
    /// and the beep has fired. Until this arrives, the coach's PASS button stays
    /// in `.waitingBeep` so the user cannot tap PASS before the display enters
    /// its decision window. Prevents the "early pass is silently dropped by the
    /// display-side hard gate → rep discarded → recovery path swallows the rep"
    /// cascade that was causing skipped reps during normal (non-spam) play.
    case beepArmed(repIndex: Int, timestamp: Date)
    case passTriggered(repIndex: Int, timestamp: Date)
    case exitLogged(repIndex: Int, gate: Gate, timestamp: Date)
    /// Legacy wire name: optional early action before exit (DOP/AFP). TODO: rename to `firstDecisionLogged` with dual-decode.
    case firstTouchLogged(repIndex: Int, gate: Gate, timestamp: Date)
    /// Coach ✕ when the rep was wrong and logging a direction would misrepresent the player. Still required — see migration doc.
    case incorrectDecision(repIndex: Int, timestamp: Date)
    /// Coach device: notifies display that this session is paired so the pairing code can be hidden.
    case coachPaired(sessionId: UUID)
    /// Display device: notifies coach that session ended so UI can reset immediately.
    case sessionEnded(timestamp: Date)
    /// Either device: the **whole** partner training run ended (explicit hub end / Leave with end session). Peers must tear down relay and clear pairing so the next activity gets a fresh join code.
    case partnerTrainingEnded(timestamp: Date)
    /// After reconnect: minimal drill snapshot so coach can compare rep/phase (does not change scores).
    case partnerSessionCheckpoint(sourceRole: String, activityId: String, repIndex: Int, phaseToken: String, relaySessionId: String?, timestamp: Date)
    /// Coach-driven pass-tempo calibration taps (partner mode).
    case calibrationPassTapped(timestamp: Date)
    case calibrationArrivalTapped(timestamp: Date)
    case calibrationFinished(averageTravelTimeSeconds: Double?)
    /// Coach → display: open the partner display flow for this activity (relay / Multipeer). Wire kind: `sessionStarted`.
    case sessionStarted(activityId: String, totalReps: Int, timestamp: Date)
    /// Coach → display: discard finished block, reset rep 0, dismiss results; same session / connection. Wire kind: `startNextBlock`.
    case startNextBlock(timestamp: Date)

    enum CodingKeys: String, CodingKey {
        case kind
        case repIndex
        case gate
        case timestamp
        case sessionId
        case sourceRole
        case activityId
        case phaseToken
        case relaySessionId
        case averageTravelTimeSeconds
        case totalReps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "nextRep":
            self = .nextRep(repIndex: try c.decode(Int.self, forKey: .repIndex))
        case "repStarted":
            self = .repStarted(repIndex: try c.decode(Int.self, forKey: .repIndex), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "beepArmed":
            self = .beepArmed(repIndex: try c.decode(Int.self, forKey: .repIndex), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "passTriggered":
            self = .passTriggered(repIndex: try c.decode(Int.self, forKey: .repIndex), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "exitLogged":
            self = .exitLogged(repIndex: try c.decode(Int.self, forKey: .repIndex), gate: try c.decode(Gate.self, forKey: .gate), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "firstTouchLogged":
            self = .firstTouchLogged(repIndex: try c.decode(Int.self, forKey: .repIndex), gate: try c.decode(Gate.self, forKey: .gate), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "incorrectDecision":
            self = .incorrectDecision(repIndex: try c.decode(Int.self, forKey: .repIndex), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "coachPaired":
            self = .coachPaired(sessionId: try c.decode(UUID.self, forKey: .sessionId))
        case "sessionEnded":
            self = .sessionEnded(timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "partnerTrainingEnded":
            self = .partnerTrainingEnded(timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "partnerSessionCheckpoint":
            self = .partnerSessionCheckpoint(
                sourceRole: try c.decode(String.self, forKey: .sourceRole),
                activityId: try c.decode(String.self, forKey: .activityId),
                repIndex: try c.decode(Int.self, forKey: .repIndex),
                phaseToken: try c.decode(String.self, forKey: .phaseToken),
                relaySessionId: try c.decodeIfPresent(String.self, forKey: .relaySessionId),
                timestamp: try c.decode(Date.self, forKey: .timestamp)
            )
        case "calibrationPassTapped":
            self = .calibrationPassTapped(timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "calibrationArrivalTapped":
            self = .calibrationArrivalTapped(timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "calibrationFinished":
            self = .calibrationFinished(averageTravelTimeSeconds: try c.decodeIfPresent(Double.self, forKey: .averageTravelTimeSeconds))
        case "sessionStarted":
            self = .sessionStarted(
                activityId: try c.decode(String.self, forKey: .activityId),
                totalReps: try c.decode(Int.self, forKey: .totalReps),
                timestamp: try c.decode(Date.self, forKey: .timestamp)
            )
        case "startNextBlock":
            self = .startNextBlock(timestamp: try c.decode(Date.self, forKey: .timestamp))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown kind: \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .nextRep(let repIndex):
            try c.encode("nextRep", forKey: .kind)
            try c.encode(repIndex, forKey: .repIndex)
        case .repStarted(let repIndex, let timestamp):
            try c.encode("repStarted", forKey: .kind)
            try c.encode(repIndex, forKey: .repIndex)
            try c.encode(timestamp, forKey: .timestamp)
        case .beepArmed(let repIndex, let timestamp):
            try c.encode("beepArmed", forKey: .kind)
            try c.encode(repIndex, forKey: .repIndex)
            try c.encode(timestamp, forKey: .timestamp)
        case .passTriggered(let repIndex, let timestamp):
            try c.encode("passTriggered", forKey: .kind)
            try c.encode(repIndex, forKey: .repIndex)
            try c.encode(timestamp, forKey: .timestamp)
        case .exitLogged(let repIndex, let gate, let timestamp):
            try c.encode("exitLogged", forKey: .kind)
            try c.encode(repIndex, forKey: .repIndex)
            try c.encode(gate, forKey: .gate)
            try c.encode(timestamp, forKey: .timestamp)
        case .firstTouchLogged(let repIndex, let gate, let timestamp):
            try c.encode("firstTouchLogged", forKey: .kind)
            try c.encode(repIndex, forKey: .repIndex)
            try c.encode(gate, forKey: .gate)
            try c.encode(timestamp, forKey: .timestamp)
        case .incorrectDecision(let repIndex, let timestamp):
            try c.encode("incorrectDecision", forKey: .kind)
            try c.encode(repIndex, forKey: .repIndex)
            try c.encode(timestamp, forKey: .timestamp)
        case .coachPaired(let sessionId):
            try c.encode("coachPaired", forKey: .kind)
            try c.encode(sessionId, forKey: .sessionId)
        case .sessionEnded(let timestamp):
            try c.encode("sessionEnded", forKey: .kind)
            try c.encode(timestamp, forKey: .timestamp)
        case .partnerTrainingEnded(let timestamp):
            try c.encode("partnerTrainingEnded", forKey: .kind)
            try c.encode(timestamp, forKey: .timestamp)
        case .partnerSessionCheckpoint(let sourceRole, let activityId, let repIndex, let phaseToken, let relaySessionId, let timestamp):
            try c.encode("partnerSessionCheckpoint", forKey: .kind)
            try c.encode(sourceRole, forKey: .sourceRole)
            try c.encode(activityId, forKey: .activityId)
            try c.encode(repIndex, forKey: .repIndex)
            try c.encode(phaseToken, forKey: .phaseToken)
            try c.encodeIfPresent(relaySessionId, forKey: .relaySessionId)
            try c.encode(timestamp, forKey: .timestamp)
        case .calibrationPassTapped(let timestamp):
            try c.encode("calibrationPassTapped", forKey: .kind)
            try c.encode(timestamp, forKey: .timestamp)
        case .calibrationArrivalTapped(let timestamp):
            try c.encode("calibrationArrivalTapped", forKey: .kind)
            try c.encode(timestamp, forKey: .timestamp)
        case .calibrationFinished(let averageTravelTimeSeconds):
            try c.encode("calibrationFinished", forKey: .kind)
            try c.encodeIfPresent(averageTravelTimeSeconds, forKey: .averageTravelTimeSeconds)
        case .sessionStarted(let activityId, let totalReps, let timestamp):
            try c.encode("sessionStarted", forKey: .kind)
            try c.encode(activityId, forKey: .activityId)
            try c.encode(totalReps, forKey: .totalReps)
            try c.encode(timestamp, forKey: .timestamp)
        case .startNextBlock(let timestamp):
            try c.encode("startNextBlock", forKey: .kind)
            try c.encode(timestamp, forKey: .timestamp)
        }
    }
}

extension TwoMinuteMessage {
    /// Rep-flow messages from coach that must not be applied while session countdown (3–2–1) is visible.
    var isDrillInteractionFromCoach: Bool {
        switch self {
        case .nextRep, .passTriggered, .exitLogged, .firstTouchLogged, .incorrectDecision:
            return true
        case .repStarted, .beepArmed, .coachPaired, .sessionEnded, .partnerTrainingEnded, .partnerSessionCheckpoint, .calibrationPassTapped, .calibrationArrivalTapped, .calibrationFinished, .sessionStarted, .startNextBlock:
            return false
        }
    }
}

/// While ``SessionCountdownModifier`` suppresses coach drill messages, `nextRep` is **queued** instead of dropped so the
/// first tap after pairing still starts the rep once “Go” finishes (otherwise the beep/timer never arms).
enum PartnerCountdownCoachMessagePolicy {
    /// Returns `true` if the message must not be applied to the engine yet (countdown overlay is blocking drill traffic).
    ///
    /// The latest `nextRep` index is stored in `pendingNextRepIndex` so it can be flushed when the overlay dismisses.
    static func shouldDeferWhileCountdown(
        msg: TwoMinuteMessage,
        isBlockingDrillMessagesFromCoach: Bool,
        pendingNextRepIndex: inout Int?
    ) -> Bool {
        guard isBlockingDrillMessagesFromCoach, msg.isDrillInteractionFromCoach else { return false }
        if case .nextRep(let idx) = msg {
            pendingNextRepIndex = idx
        }
        return true
    }
}
