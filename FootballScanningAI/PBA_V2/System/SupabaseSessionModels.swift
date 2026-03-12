//
//  SupabaseSessionModels.swift
//  FootballScanningAI
//
//  DTOs for saving training blocks to Supabase: one session per block, decisions linked by session_id.
//

import Foundation

/// One decision within a block (one rep). Used to build rows for the `decisions` table.
struct TrainingDecisionRecord {
    let repIndex: Int
    let correct: Bool
    /// Decision time in seconds; nil if not measured.
    let decisionTimeSeconds: Double?
    /// Chosen direction for analytics: "up", "down", "left", "right".
    let chosenDirection: String

    /// From Away From Pressure rep log.
    static func from(_ log: AwayFromPressureRepLog) -> TrainingDecisionRecord {
        TrainingDecisionRecord(
            repIndex: log.repIndex,
            correct: log.correct,
            decisionTimeSeconds: log.decisionTimeSeconds,
            chosenDirection: log.exitedGate?.rawValue ?? "incorrect"
        )
    }

    /// From Dribble or Pass rep result.
    static func from(_ result: DribbleOrPassRepResult) -> TrainingDecisionRecord {
        TrainingDecisionRecord(
            repIndex: result.repIndex,
            correct: result.correct,
            decisionTimeSeconds: result.decisionTime,
            chosenDirection: result.chosenGate.rawValue
        )
    }

    /// From One-Touch Passing rep result.
    static func from(_ result: OneTouchRepResult) -> TrainingDecisionRecord {
        TrainingDecisionRecord(
            repIndex: result.repIndex,
            correct: result.correct,
            decisionTimeSeconds: result.decisionTime,
            chosenDirection: result.chosenGate.rawValue
        )
    }

    /// From 2-Minute Test rep log.
    static func from(_ log: RepLog) -> TrainingDecisionRecord {
        TrainingDecisionRecord(
            repIndex: log.repIndex,
            correct: log.correct,
            decisionTimeSeconds: log.passTriggeredAt.map { log.exitLoggedAt.timeIntervalSince($0) },
            chosenDirection: log.exitedGate.rawValue
        )
    }
}
