//
//  AwayFromPressureModels.swift
//  FootballScanningAI
//
//  PBA V2 — Block log entry for Playing Away From Pressure (pressure gate, exited gate, correct = opposite).
//

import Foundation

struct AwayFromPressureRepLog: Codable {
    let repIndex: Int
    let pressureGate: Gate
    let exitedGate: Gate
    let startedAt: Date
    let markerShownAt: Date
    let markerHiddenAt: Date
    let passTriggeredAt: Date?
    let exitLoggedAt: Date
    /// Set when coach logs first touch direction (or Skip leaves nil).
    let firstTouchGate: Gate?
    /// When coach logs first touch, timestamp used for decision timing (first-touch timing); nil when skipped.
    let firstTouchLoggedAt: Date?

    init(repIndex: Int, pressureGate: Gate, exitedGate: Gate, startedAt: Date, markerShownAt: Date, markerHiddenAt: Date, passTriggeredAt: Date?, exitLoggedAt: Date, firstTouchGate: Gate? = nil, firstTouchLoggedAt: Date? = nil) {
        self.repIndex = repIndex
        self.pressureGate = pressureGate
        self.exitedGate = exitedGate
        self.startedAt = startedAt
        self.markerShownAt = markerShownAt
        self.markerHiddenAt = markerHiddenAt
        self.passTriggeredAt = passTriggeredAt
        self.exitLoggedAt = exitLoggedAt
        self.firstTouchGate = firstTouchGate
        self.firstTouchLoggedAt = firstTouchLoggedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repIndex = try c.decode(Int.self, forKey: .repIndex)
        pressureGate = try c.decode(Gate.self, forKey: .pressureGate)
        exitedGate = try c.decode(Gate.self, forKey: .exitedGate)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        markerShownAt = try c.decode(Date.self, forKey: .markerShownAt)
        markerHiddenAt = try c.decode(Date.self, forKey: .markerHiddenAt)
        passTriggeredAt = try c.decodeIfPresent(Date.self, forKey: .passTriggeredAt)
        exitLoggedAt = try c.decode(Date.self, forKey: .exitLoggedAt)
        firstTouchGate = try c.decodeIfPresent(Gate.self, forKey: .firstTouchGate)
        firstTouchLoggedAt = try c.decodeIfPresent(Date.self, forKey: .firstTouchLoggedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(repIndex, forKey: .repIndex)
        try c.encode(pressureGate, forKey: .pressureGate)
        try c.encode(exitedGate, forKey: .exitedGate)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(markerShownAt, forKey: .markerShownAt)
        try c.encode(markerHiddenAt, forKey: .markerHiddenAt)
        try c.encodeIfPresent(passTriggeredAt, forKey: .passTriggeredAt)
        try c.encode(exitLoggedAt, forKey: .exitLoggedAt)
        try c.encodeIfPresent(firstTouchGate, forKey: .firstTouchGate)
        try c.encodeIfPresent(firstTouchLoggedAt, forKey: .firstTouchLoggedAt)
    }

    enum CodingKeys: String, CodingKey {
        case repIndex, pressureGate, exitedGate, startedAt, markerShownAt, markerHiddenAt, passTriggeredAt, exitLoggedAt, firstTouchGate, firstTouchLoggedAt
    }

    /// Decision time for this rep: first-touch timing when logged, else exit timing (fallback).
    var decisionTimeSeconds: Double? {
        guard let pt = passTriggeredAt else { return nil }
        if let ft = firstTouchLoggedAt {
            return ft.timeIntervalSince(pt)
        }
        return exitLoggedAt.timeIntervalSince(pt)
    }

    var correct: Bool { exitedGate == pressureGate.opposite }

    /// Late correction: first touch was wrong but exit was correct.
    var lateCorrection: Bool {
        guard let ft = firstTouchGate else { return false }
        let correctGate = pressureGate.opposite
        return ft != correctGate && exitedGate == correctGate
    }
}
