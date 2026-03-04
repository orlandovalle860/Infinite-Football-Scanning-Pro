//
//  TwoMinuteModels.swift
//  FootballScanningAI
//
//  PBA V2 — RepLog and Multipeer message types.
//

import Foundation

/// One completed rep: star gate, exited gate, timestamps.
struct RepLog: Codable {
    let repIndex: Int
    let starGate: Gate
    let exitedGate: Gate
    let startedAt: Date
    let infoShownAt: Date
    let infoHiddenAt: Date
    let passTriggeredAt: Date?
    let exitLoggedAt: Date

    var correct: Bool { starGate == exitedGate }

    static func from(
        repIndex: Int,
        starGate: Gate,
        exitedGate: Gate,
        startedAt: Date,
        infoShownAt: Date,
        infoHiddenAt: Date,
        passTriggeredAt: Date?,
        exitLoggedAt: Date
    ) -> RepLog {
        RepLog(
            repIndex: repIndex,
            starGate: starGate,
            exitedGate: exitedGate,
            startedAt: startedAt,
            infoShownAt: infoShownAt,
            infoHiddenAt: infoHiddenAt,
            passTriggeredAt: passTriggeredAt,
            exitLoggedAt: exitLoggedAt
        )
    }
}

// MARK: - Multipeer messages (payload prefix pba2:)

enum TwoMinuteMessage: Codable {
    case nextRep(repIndex: Int)
    case passTriggered(repIndex: Int, timestamp: Date)
    case exitLogged(repIndex: Int, gate: Gate, timestamp: Date)
    case firstTouchLogged(repIndex: Int, gate: Gate, timestamp: Date)

    enum CodingKeys: String, CodingKey {
        case kind
        case repIndex
        case gate
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "nextRep":
            self = .nextRep(repIndex: try c.decode(Int.self, forKey: .repIndex))
        case "passTriggered":
            self = .passTriggered(repIndex: try c.decode(Int.self, forKey: .repIndex), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "exitLogged":
            self = .exitLogged(repIndex: try c.decode(Int.self, forKey: .repIndex), gate: try c.decode(Gate.self, forKey: .gate), timestamp: try c.decode(Date.self, forKey: .timestamp))
        case "firstTouchLogged":
            self = .firstTouchLogged(repIndex: try c.decode(Int.self, forKey: .repIndex), gate: try c.decode(Gate.self, forKey: .gate), timestamp: try c.decode(Date.self, forKey: .timestamp))
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
        }
    }
}
