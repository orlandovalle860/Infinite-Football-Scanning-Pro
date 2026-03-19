//
//  AwayFromPressureModels.swift
//  FootballScanningAI
//
//  PBA V2 — Block log for Playing Away From Pressure.
//  Decision timing = trigger → coach directional input (when coach taps direction or ✕). No separate first-touch logging required.
//

import Foundation

struct AwayFromPressureRepLog: Codable {
    let repIndex: Int
    let pressureGate: Gate
    /// Direction coach logged (player's decision). Nil when coach tapped ✕ (incorrect).
    let exitedGate: Gate?
    let startedAt: Date
    let markerShownAt: Date
    let markerHiddenAt: Date
    let passTriggeredAt: Date?
    let exitLoggedAt: Date
    /// Optional: set when coach logs first touch direction (for correction-rate etc.). Not used for decision timing.
    let firstTouchGate: Gate?
    /// Optional: when first touch was logged. Not used for decision timing (timing = trigger → coach direction).
    let firstTouchLoggedAt: Date?

    init(repIndex: Int, pressureGate: Gate, exitedGate: Gate?, startedAt: Date, markerShownAt: Date, markerHiddenAt: Date, passTriggeredAt: Date?, exitLoggedAt: Date, firstTouchGate: Gate? = nil, firstTouchLoggedAt: Date? = nil) {
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
        exitedGate = try c.decodeIfPresent(Gate.self, forKey: .exitedGate)
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
        try c.encodeIfPresent(exitedGate, forKey: .exitedGate)
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

    /// Decision time = coach directional input − trigger. No first-touch logging required (see MEASUREMENT_MODEL.md).
    var decisionTimeSeconds: Double? {
        guard let pt = passTriggeredAt else { return nil }
        return exitLoggedAt.timeIntervalSince(pt)
    }

    /// Correct if logged direction matched the correct escape (opposite of pressure).
    var correct: Bool { exitedGate == pressureGate.opposite }

    /// Late correction: first touch was wrong but exit was correct. Optional metric; requires first touch logged.
    var lateCorrection: Bool {
        guard let ft = firstTouchGate, let ex = exitedGate else { return false }
        let correctGate = pressureGate.opposite
        return ft != correctGate && ex == correctGate
    }
}
