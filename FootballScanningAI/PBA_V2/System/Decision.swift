//
//  Decision.swift
//  FootballScanningAI
//
//  PBA V2 — Per-rep decision record: reaction time (trigger → confirmation), direction, correct.
//

import Foundation

/// Direction of the player's decision for analytics. Matches Gate.rawValue or "incorrect".
enum DecisionDirection: String, Codable, CaseIterable {
    case up
    case down
    case left
    case right
    /// When coach tapped ✕ (incorrect decision).
    case incorrect
}

/// One decision (one rep). Persisted to Supabase `decisions` table.
struct Decision: Codable {
    let id: UUID
    let sessionId: UUID
    /// Nil when not signed in; Supabase accepts null for player_id.
    let playerId: UUID?
    /// Activity name (e.g. rawValue of ActivityKind) for analytics.
    let activityName: String
    let stimulusType: String
    let decisionDirection: String
    let reactionTimeMs: Int
    let correct: Bool
    let createdAt: Date

    init(id: UUID = UUID(), sessionId: UUID, playerId: UUID?, activityName: String, stimulusType: String, decisionDirection: String, reactionTimeMs: Int, correct: Bool, createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.playerId = playerId
        self.activityName = activityName
        self.stimulusType = stimulusType
        self.decisionDirection = decisionDirection
        self.reactionTimeMs = reactionTimeMs
        self.correct = correct
        self.createdAt = createdAt
    }
}

extension Gate {
    var decisionDirectionRaw: String { rawValue }
}
