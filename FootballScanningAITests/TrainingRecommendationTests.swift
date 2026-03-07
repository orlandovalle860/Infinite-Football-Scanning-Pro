//
//  TrainingRecommendationTests.swift
//  FootballScanningAITests
//
//  Unit tests for TrainingRecommendation.recommendedActivity and defaultActivity.
//

import Testing
@tes
table import InfiniteFootballScanningPro

struct TrainingRecommendationTests {

    // MARK: - Default activity by level

    @Test func defaultActivity_starter_returnsAwayFromPressure() {
        let result = TrainingRecommendation.defaultActivity(for: .starter)
        #expect(result == .awayFromPressure)
    }

    @Test func defaultActivity_safePlayer_returnsDribbleOrPass() {
        let result = TrainingRecommendation.defaultActivity(for: .safePlayer)
        #expect(result == .dribbleOrPass)
    }

    @Test func defaultActivity_forwardThinker_returnsDribbleOrPass() {
        let result = TrainingRecommendation.defaultActivity(for: .forwardThinker)
        #expect(result == .dribbleOrPass)
    }

    @Test func defaultActivity_playmaker_returnsOneTouchPassing() {
        let result = TrainingRecommendation.defaultActivity(for: .playmaker)
        #expect(result == .oneTouchPassing)
    }

    @Test func defaultActivity_elite_returnsTwoMinuteTest() {
        let result = TrainingRecommendation.defaultActivity(for: .elite)
        #expect(result == .twoMinuteTest)
    }

    // MARK: - Slow timing override

    @Test func recommendedActivity_slowOverride_returnsAwayFromPressure() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .playmaker,
            decisionSpeed: .slow,
            bias: nil,
            consistency: .steady
        )
        #expect(result == .awayFromPressure)
    }

    @Test func recommendedActivity_slowOverride_eliteLevel_returnsAwayFromPressure() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .elite,
            decisionSpeed: .slow,
            bias: nil,
            consistency: .steady
        )
        #expect(result == .awayFromPressure)
    }

    // MARK: - Bias overrides

    @Test func recommendedActivity_leftRightBias_dribbleOrPassDefault_returnsAwayFromPressure() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .forwardThinker,
            decisionSpeed: .medium,
            bias: .leftRight,
            consistency: .steady
        )
        #expect(result == .awayFromPressure)
    }

    /// Backward/safe bias is not yet measured; when present it has no override (level default is used).
    @Test func recommendedActivity_backwardSafeBias_noOverride_returnsLevelDefault() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .playmaker,
            decisionSpeed: .medium,
            bias: .backwardSafe,
            consistency: .steady
        )
        #expect(result == .oneTouchPassing)
    }

    @Test func recommendedActivity_noBias_playmaker_returnsOneTouchPassing() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .playmaker,
            decisionSpeed: .medium,
            bias: nil,
            consistency: .steady
        )
        #expect(result == .oneTouchPassing)
    }

    // MARK: - Consistency override (streaky = keep level default)

    @Test func recommendedActivity_streaky_playmaker_returnsOneTouchPassing() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .playmaker,
            decisionSpeed: .medium,
            bias: nil,
            consistency: .streaky
        )
        #expect(result == .oneTouchPassing)
    }

    @Test func recommendedActivity_streaky_forwardThinker_returnsDribbleOrPass() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .forwardThinker,
            decisionSpeed: .medium,
            bias: nil,
            consistency: .streaky
        )
        #expect(result == .dribbleOrPass)
    }

    @Test func recommendedActivity_streaky_afterBiasOverride_resetsToLevelDefault() {
        // Without streaky: forwardThinker + leftRight -> awayFromPressure. With streaky: stay at level default -> dribbleOrPass.
        let result = TrainingRecommendation.recommendedActivity(
            level: .forwardThinker,
            decisionSpeed: .medium,
            bias: .leftRight,
            consistency: .streaky
        )
        #expect(result == .dribbleOrPass)
    }

    // MARK: - Order: slow wins over bias

    @Test func recommendedActivity_slowAndBias_returnsAwayFromPressure() {
        let result = TrainingRecommendation.recommendedActivity(
            level: .playmaker,
            decisionSpeed: .slow,
            bias: .backwardSafe,
            consistency: .steady
        )
        #expect(result == .awayFromPressure)
    }
}
