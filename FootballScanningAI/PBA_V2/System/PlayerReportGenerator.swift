//
//  PlayerReportGenerator.swift
//  FootballScanningAI
//
//  PBA V2 — Translates training data into coaching feedback: decision style, strength, needs improvement, recommendation.
//

import Foundation

/// Content for the Player Report screen. Generated from 2-minute test result and/or training blocks.
struct PlayerReportContent {
    let decisionStyle: String
    let strength: String
    let needsImprovement: String
    let trainingRecommendation: String
}

enum PlayerReportGenerator {
    /// Build report from 2-minute test result (e.g. right after test).
    static func report(from testResult: TwoMinuteTestResult) -> PlayerReportContent {
        let type = TwoMinutePlayerType.determinePlayerType(
            correct: testResult.correctCount,
            total: testResult.totalReps,
            fast: testResult.fastCount,
            medium: testResult.mediumCount,
            slow: testResult.slowCount
        )
        let (activity, focus) = TwoMinuteRecommendedNext.recommendedNext(
            for: type,
            slow: testResult.slowCount,
            correct: testResult.correctCount,
            total: testResult.totalReps,
            bias: testResult.biasDirection
        )
        let strength = strengthFromTwoMinute(type: type, correct: testResult.correctCount, total: testResult.totalReps)
        let needsImprovement = needsImprovementFromTwoMinute(type: type, slow: testResult.slowCount, bias: testResult.biasDirection)
        let trainingRec = "Practice \(activityDisplayName(activity)) to \(focus)."
        return PlayerReportContent(
            decisionStyle: type.title,
            strength: strength,
            needsImprovement: needsImprovement,
            trainingRecommendation: trainingRec
        )
    }

    /// Build report from training data (progress store, last blocks, optional last AFP session).
    static func report(
        progressStore: ProgressStore,
        playerId: UUID?,
        last5: [SessionRecord],
        lastAFPSessionResult: SessionResult? = nil,
        decisionConsistency: DecisionConsistencyLabel? = nil
    ) -> PlayerReportContent {
        let decisionScore = DashboardDecisionScore.score(from: last5)
        let consistencyLabel = DashboardConsistency.label(from: last5)
        let status = DashboardDecisionScore.status(score: decisionScore, consistencyLabel: consistencyLabel)
        let decisionStyle = decisionStyleLabel(from: status)

        let hasCompletedTest = progressStore.last(.twoMinuteTest, playerId: playerId) != nil
        let rec = TrainingRecommendation.recommend(
            progressStore: progressStore,
            playerId: playerId,
            last5: last5,
            hasCompletedInitialTest: hasCompletedTest,
            lastAFPSessionResult: lastAFPSessionResult,
            decisionConsistency: decisionConsistency
        )

        let strength = strengthFromTraining(
            status: status,
            last5: last5,
            lastAFPSessionResult: lastAFPSessionResult
        )
        let needsImprovement = needsImprovementFromTraining(
            last5: last5,
            lastAFPSessionResult: lastAFPSessionResult,
            recommendation: rec
        )
        let trainingRec: String
        if rec.activity == .twoMinuteTest {
            trainingRec = "Take the 2-Minute Test to see your baseline."
        } else {
            trainingRec = "Practice \(activityDisplayName(rec.activity)) to \(rec.focusLine)."
        }
        return PlayerReportContent(
            decisionStyle: decisionStyle,
            strength: strength,
            needsImprovement: needsImprovement,
            trainingRecommendation: trainingRec
        )
    }

    // MARK: - 2-minute helpers

    private static func strengthFromTwoMinute(type: PlayerType, correct: Int, total: Int) -> String {
        switch type {
        case .playmaker:
            return "You choose the correct option under pressure and decide early."
        case .anticipator:
            return "You choose the correct option under pressure and read pressure early."
        case .scanner:
            return "You often choose the correct option when you have time to scan."
        case .reactor:
            if total > 0 && Double(correct) / Double(total) >= 0.5 {
                return "You're finding the right option when you see it."
            }
            return "You're building awareness of pressure and the opposite direction."
        }
    }

    private static func needsImprovementFromTwoMinute(type: PlayerType, slow: Int, bias: Gate?) -> String {
        if bias != nil {
            return "You're favoring one side—scan the whole field."
        }
        switch type {
        case .playmaker:
            return "Keep the standard and use the whole field."
        case .anticipator:
            return "Your decisions can arrive slightly late sometimes—commit sooner."
        case .scanner:
            return "Your decisions arrive slightly late—decide earlier before expected arrival."
        case .reactor:
            return "Your decisions arrive late—scan earlier and commit before receiving."
        }
    }

    // MARK: - Training helpers

    private static func decisionStyleLabel(from status: PlayerStatus) -> String {
        switch status {
        case .beginner: return "Reactor"
        case .developing: return "Scanner"
        case .playmaker: return "Playmaker"
        case .elite: return "Game Reader"
        }
    }

    private static func strengthFromTraining(
        status: PlayerStatus,
        last5: [SessionRecord],
        lastAFPSessionResult: SessionResult?
    ) -> String {
        let speed = TrainingRecommendation.decisionSpeed(from: last5)
        let hasFirstTouchIssues = TrainingRecommendation.hasFirstTouchIssues(lastAFPSessionResult)

        switch status {
        case .elite:
            return "You choose the correct option under pressure and stay consistent."
        case .playmaker:
            if speed == .fast {
                return "You choose the correct option under pressure and decide early."
            }
            return "You choose the correct option under pressure."
        case .developing:
            if !hasFirstTouchIssues, let match = lastAFPSessionResult?.firstTouchMatchCount, match >= 8 {
                return "Your first action often matches your decision."
            }
            return "You're finding the right option more often."
        case .beginner:
            return "You're building accuracy and awareness."
        }
    }

    private static func needsImprovementFromTraining(
        last5: [SessionRecord],
        lastAFPSessionResult: SessionResult?,
        recommendation: TrainingRecommendationResult
    ) -> String {
        let speed = TrainingRecommendation.decisionSpeed(from: last5)
        let bias = TrainingRecommendation.biasType(from: last5)
        let hasFirstTouchIssues = TrainingRecommendation.hasFirstTouchIssues(lastAFPSessionResult)

        if hasFirstTouchIssues {
            if (lastAFPSessionResult?.firstTouchTowardPressureCount ?? 0) >= 3 {
                return "You're turning into pressure too often—scan earlier."
            }
            if (lastAFPSessionResult?.firstTouchHesitantCount ?? 0) >= 3 {
                return "You're hesitating between options—commit to your decision."
            }
            return "Your first action is often late or off—decide earlier before expected arrival."
        }
        if speed == .slow {
            return "Your decisions arrive slightly late."
        }
        if bias == .leftRight {
            return "You're favoring one side—scan the whole field."
        }
        if let reason = recommendation.reason, reason.contains("accuracy") || reason.contains("Build") {
            return "Focus on reading pressure and choosing the opposite direction on first decision."
        }
        if let reason = recommendation.reason, reason.contains("earlier") || reason.contains("Decide") {
            return "Your decisions can arrive slightly late—decide earlier."
        }
        return recommendation.coachTip
    }

    private static func activityDisplayName(_ activity: ActivityKind) -> String {
        switch activity {
        case .twoMinuteTest: return "the 2-Minute Test"
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        }
    }
}
