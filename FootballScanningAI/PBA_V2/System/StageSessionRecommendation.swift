//
//  StageSessionRecommendation.swift
//  FootballScanningAI
//
//  PBA V2 — After progression evaluation: deterministic next-session prescription for the coach.
//

import Foundation

/// Focus tag for the next live activity (not the in-app mode name).
enum StageRecommendationFocus: String, Codable, Equatable {
    case clarity
    case speed
    case constraint
}

/// Next-session recommendation after a scored block (runs only from `addSessionResult` after progression).
struct StageSessionRecommendation: Codable, Equatable {
    /// Session that produced this recommendation (for summary UI).
    let tiedSessionId: UUID
    var stage: PlayerProgressStage
    /// Short drill prescription.
    var activity: String
    var focusTag: StageRecommendationFocus
    var message: String
}

enum StageSessionRecommendationEngine {

    /// Builds recommendation using the session just saved and the player’s stage **after** progression evaluation.
    static func make(didAdvance: Bool, stageAfterProgression: PlayerProgressStage, result: SessionResult) -> StageSessionRecommendation {
        let accuracy = result.totalReps > 0 ? Double(result.correctCount) / Double(result.totalReps) : 0
        let decisionScore = result.decisionTotalScore
            ?? Double(result.estimatedDecisionSpeedScore ?? Int((accuracy * 100).rounded()))
        let decisionWindow = result.avgDecisionTime

        let rec: StageSessionRecommendation
        if didAdvance {
            rec = baseline(afterAdvanceTo: stageAfterProgression, tiedSessionId: result.id)
        } else {
            let focus = weaknessFocus(accuracy: accuracy, averageDecisionWindow: decisionWindow)
            rec = variation(stage: stageAfterProgression, focus: focus, tiedSessionId: result.id)
        }

        let wStr = decisionWindow.map { String(format: "%.4f", $0) } ?? "nil"
        print("[RecommendationDebug] stage=\(stageAfterProgression.rawValue) score=\(decisionScore) accuracy=\(accuracy) decisionWindow=\(wStr) focus=\(rec.focusTag.rawValue) activity=\(rec.activity)")

        return rec
    }

    // MARK: - Weakness (deterministic)

    static func weaknessFocus(accuracy: Double, averageDecisionWindow: Double?) -> StageRecommendationFocus {
        if accuracy < 0.70 { return .clarity }
        let w = averageDecisionWindow ?? 0
        if w <= 0 { return .speed }
        return .constraint
    }

    // MARK: - Baseline (advanced to next stage)

    private static func baseline(afterAdvanceTo stage: PlayerProgressStage, tiedSessionId: UUID) -> StageSessionRecommendation {
        switch stage {
        case .awayFromPressure:
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .awayFromPressure,
                activity: "3v1 in wide space",
                focusTag: .clarity,
                message: "Start with Playing Away From Pressure — 3v1 in wide space so the first read is obvious."
            )
        case .dribbleOrPass:
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .dribbleOrPass,
                activity: "Obvious forward vs safe",
                focusTag: .clarity,
                message: "Unlocked: Dribble or Pass. Next session — obvious forward vs safe in open play."
            )
        case .oneTouchPassing:
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .oneTouchPassing,
                activity: "Fewer options (2 gates)",
                focusTag: .clarity,
                message: "Unlocked: One-Touch Passing. Next session — two gates, clean tempo."
            )
        }
    }

    // MARK: - Variation (stayed in stage)

    private static func variation(stage: PlayerProgressStage, focus: StageRecommendationFocus, tiedSessionId: UUID) -> StageSessionRecommendation {
        switch (stage, focus) {
        case (.awayFromPressure, .clarity):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .awayFromPressure,
                activity: "3v1 in wide space",
                focusTag: .clarity,
                message: "Stay in Playing Away From Pressure — simplify the picture (3v1, wide space) until reads stay clean."
            )
        case (.awayFromPressure, .speed):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .awayFromPressure,
                activity: "Immediate pressure constraint",
                focusTag: .speed,
                message: "You're improving. Stay in Away From Pressure — focus on escaping earlier."
            )
        case (.awayFromPressure, .constraint):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .awayFromPressure,
                activity: "2v2 tight grid",
                focusTag: .constraint,
                message: "Stay in Playing Away From Pressure — use a 2v2 tight grid to sharpen decisions in tight space."
            )

        case (.dribbleOrPass, .clarity):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .dribbleOrPass,
                activity: "Obvious forward vs safe",
                focusTag: .clarity,
                message: "Stay in Dribble or Pass — make forward vs safe obvious before expected arrival."
            )
        case (.dribbleOrPass, .speed):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .dribbleOrPass,
                activity: "1-touch rule when possible",
                focusTag: .speed,
                message: "Good decisions. Now speed it up — play faster when forward is available."
            )
        case (.dribbleOrPass, .constraint):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .dribbleOrPass,
                activity: "Defender closes faster",
                focusTag: .constraint,
                message: "Stay in Dribble or Pass — have the defender close faster so you must commit sooner."
            )

        case (.oneTouchPassing, .clarity):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .oneTouchPassing,
                activity: "Fewer options (2 gates)",
                focusTag: .clarity,
                message: "Stay in One-Touch Passing — narrow to two gates until every pass is crisp."
            )
        case (.oneTouchPassing, .speed):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .oneTouchPassing,
                activity: "Reduced time window",
                focusTag: .speed,
                message: "Stay in One-Touch Passing — shrink the decision window while keeping accuracy."
            )
        case (.oneTouchPassing, .constraint):
            return StageSessionRecommendation(
                tiedSessionId: tiedSessionId,
                stage: .oneTouchPassing,
                activity: "More targets + distractions",
                focusTag: .constraint,
                message: "Sharp. Now handle more complexity — more options, same speed."
            )
        }
    }
}
