//
//  TwoMinuteRepPlan.swift
//  FootballScanningAI
//
//  PBA V2 — Gate (Middle Up/Down/Left/Right) and RepPlan for 2-Minute Critical Scan.
//

import Foundation

/// One of four positions (same as Dribble or Pass: Middle Up, Down, Left, Right).
enum Gate: String, Codable, CaseIterable, Hashable {
    case up
    case down
    case left
    case right
}

extension Gate {
    /// Opposite gate (for Away From Pressure: correct exit is opposite pressure).
    var opposite: Gate {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    /// Screen-edge names for wedge / gate clarity logging (top, bottom, left, right).
    var wedgeClaritySideLabel: String {
        switch self {
        case .up: return "top"
        case .down: return "bottom"
        case .left: return "left"
        case .right: return "right"
        }
    }
}

/// Plan for one rep: which gate shows the ball.
struct RepPlan: Codable {
    let repIndex: Int
    let ballGate: Gate

    var soloStimulusFingerprint: String { ballGate.rawValue }
    var soloStimulusDebugLabel: String { "ball=\(ballGate.rawValue)" }
}
