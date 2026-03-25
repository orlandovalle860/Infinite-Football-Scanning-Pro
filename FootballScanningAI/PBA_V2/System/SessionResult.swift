//
//  SessionResult.swift
//  FootballScanningAI
//
//  PBA V2 — Coach/parent session summary: one block or 2-min test. Stored per player profile.
//  `firstTouch*` property names are legacy; see `CoachRemoteDecisionModelMIGRATION.md`.
//

import Foundation

/// Speed counts for a block (fast/medium/slow).
struct SessionSpeedCounts: Codable, Equatable, Hashable {
    var fast: Int
    var medium: Int
    var slow: Int
}

/// Single session result for Session Summary and share report. Saved to active profile.
struct SessionResult: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let playerID: UUID
    let activityType: ActivityKind
    let correctCount: Int
    let totalReps: Int
    let speedCounts: SessionSpeedCounts
    let avgDecisionTime: Double?
    let biasDirection: Gate?
    let directionCounts: [Gate: Int]
    let firstTouchCounts: [Gate: Int]?
    let firstTouchMatchCount: Int?  // optional early action matched intended direction (legacy field name)
    /// AFP: reps where early action was toward pressure (wrong direction).
    let firstTouchTowardPressureCount: Int?
    /// AFP: reps where early action was sideways/neutral (hesitating).
    let firstTouchHesitantCount: Int?
    let lateAdjustments: Int?
    let notes: String?
    let difficulty: TestDifficulty?
    /// Dribble or Pass: total of (decision points + timing bonus) across reps. Max 60.
    let decisionTotalScore: Double?
    /// Forward Intent: reps where player chose forward (when available). Used with forwardOpportunityCount.
    let forwardChoiceCount: Int?
    /// Forward Intent: reps where a forward option was available.
    let forwardOpportunityCount: Int?
    /// Pre-Receive Decision Rate: reps where decisionTime < threshold AND early action == correct direction.
    let preReceiveDecisionCount: Int?
    /// Standard deviation of decision times within the session (seconds). Lower = more consistent. Optional for backward compatibility.
    let decisionTimeStdDev: Double?

    init(id: UUID = UUID(), date: Date = Date(), playerID: UUID, activityType: ActivityKind, correctCount: Int, totalReps: Int, speedCounts: SessionSpeedCounts, avgDecisionTime: Double? = nil, biasDirection: Gate? = nil, directionCounts: [Gate: Int] = [:], firstTouchCounts: [Gate: Int]? = nil, firstTouchMatchCount: Int? = nil, firstTouchTowardPressureCount: Int? = nil, firstTouchHesitantCount: Int? = nil, lateAdjustments: Int? = nil, notes: String? = nil, difficulty: TestDifficulty? = nil, decisionTotalScore: Double? = nil, forwardChoiceCount: Int? = nil, forwardOpportunityCount: Int? = nil, preReceiveDecisionCount: Int? = nil, decisionTimeStdDev: Double? = nil) {
        self.id = id
        self.date = date
        self.playerID = playerID
        self.activityType = activityType
        self.correctCount = correctCount
        self.totalReps = totalReps
        self.speedCounts = speedCounts
        self.avgDecisionTime = avgDecisionTime
        self.biasDirection = biasDirection
        self.directionCounts = directionCounts
        self.firstTouchCounts = firstTouchCounts
        self.firstTouchMatchCount = firstTouchMatchCount
        self.firstTouchTowardPressureCount = firstTouchTowardPressureCount
        self.firstTouchHesitantCount = firstTouchHesitantCount
        self.lateAdjustments = lateAdjustments
        self.notes = notes
        self.difficulty = difficulty
        self.decisionTotalScore = decisionTotalScore
        self.forwardChoiceCount = forwardChoiceCount
        self.forwardOpportunityCount = forwardOpportunityCount
        self.preReceiveDecisionCount = preReceiveDecisionCount
        self.decisionTimeStdDev = decisionTimeStdDev
    }
}

// MARK: - Codable (optional forward fields for backward compatibility)
extension SessionResult {
    enum CodingKeys: String, CodingKey {
        case id, date, playerID, activityType, correctCount, totalReps, speedCounts, avgDecisionTime
        case biasDirection, directionCounts, firstTouchCounts, firstTouchMatchCount
        case firstTouchTowardPressureCount, firstTouchHesitantCount, lateAdjustments, notes, difficulty
        case decisionTotalScore, forwardChoiceCount, forwardOpportunityCount, preReceiveDecisionCount, decisionTimeStdDev
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        playerID = try c.decode(UUID.self, forKey: .playerID)
        activityType = try c.decode(ActivityKind.self, forKey: .activityType)
        correctCount = try c.decode(Int.self, forKey: .correctCount)
        totalReps = try c.decode(Int.self, forKey: .totalReps)
        speedCounts = try c.decode(SessionSpeedCounts.self, forKey: .speedCounts)
        avgDecisionTime = try c.decodeIfPresent(Double.self, forKey: .avgDecisionTime)
        biasDirection = try c.decodeIfPresent(Gate.self, forKey: .biasDirection)
        directionCounts = try c.decode([Gate: Int].self, forKey: .directionCounts)
        firstTouchCounts = try c.decodeIfPresent([Gate: Int].self, forKey: .firstTouchCounts)
        firstTouchMatchCount = try c.decodeIfPresent(Int.self, forKey: .firstTouchMatchCount)
        firstTouchTowardPressureCount = try c.decodeIfPresent(Int.self, forKey: .firstTouchTowardPressureCount)
        firstTouchHesitantCount = try c.decodeIfPresent(Int.self, forKey: .firstTouchHesitantCount)
        lateAdjustments = try c.decodeIfPresent(Int.self, forKey: .lateAdjustments)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        difficulty = try c.decodeIfPresent(TestDifficulty.self, forKey: .difficulty)
        decisionTotalScore = try c.decodeIfPresent(Double.self, forKey: .decisionTotalScore)
        forwardChoiceCount = try c.decodeIfPresent(Int.self, forKey: .forwardChoiceCount)
        forwardOpportunityCount = try c.decodeIfPresent(Int.self, forKey: .forwardOpportunityCount)
        preReceiveDecisionCount = try c.decodeIfPresent(Int.self, forKey: .preReceiveDecisionCount)
        decisionTimeStdDev = try c.decodeIfPresent(Double.self, forKey: .decisionTimeStdDev)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(playerID, forKey: .playerID)
        try c.encode(activityType, forKey: .activityType)
        try c.encode(correctCount, forKey: .correctCount)
        try c.encode(totalReps, forKey: .totalReps)
        try c.encode(speedCounts, forKey: .speedCounts)
        try c.encodeIfPresent(avgDecisionTime, forKey: .avgDecisionTime)
        try c.encodeIfPresent(biasDirection, forKey: .biasDirection)
        try c.encode(directionCounts, forKey: .directionCounts)
        try c.encodeIfPresent(firstTouchCounts, forKey: .firstTouchCounts)
        try c.encodeIfPresent(firstTouchMatchCount, forKey: .firstTouchMatchCount)
        try c.encodeIfPresent(firstTouchTowardPressureCount, forKey: .firstTouchTowardPressureCount)
        try c.encodeIfPresent(firstTouchHesitantCount, forKey: .firstTouchHesitantCount)
        try c.encodeIfPresent(lateAdjustments, forKey: .lateAdjustments)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(difficulty, forKey: .difficulty)
        try c.encodeIfPresent(decisionTotalScore, forKey: .decisionTotalScore)
        try c.encodeIfPresent(forwardChoiceCount, forKey: .forwardChoiceCount)
        try c.encodeIfPresent(forwardOpportunityCount, forKey: .forwardOpportunityCount)
        try c.encodeIfPresent(preReceiveDecisionCount, forKey: .preReceiveDecisionCount)
        try c.encodeIfPresent(decisionTimeStdDev, forKey: .decisionTimeStdDev)
    }
}

// MARK: - Decision time variation (for consistency metric)

extension SessionResult {
    /// Standard deviation of a non-empty array of decision times. Returns nil if count < 2.
    static func standardDeviation(of times: [Double]) -> Double? {
        guard times.count >= 2 else { return nil }
        let mean = times.reduce(0, +) / Double(times.count)
        let variance = times.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(times.count)
        return variance >= 0 ? sqrt(variance) : nil
    }

    /// Decision Speed Score (0–100) from aggregate avg time + correctness; matches stored session score when timing is uniform across reps.
    /// Use with `DecisionSpeedBand.band(forScore:curve:)` so labels align with the session score.
    var estimatedDecisionSpeedScore: Int? {
        guard totalReps > 0 else { return nil }
        let ms = Int((avgDecisionTime ?? 1.0) * 1000)
        let reactionTimesMs = [Int](repeating: ms, count: totalReps)
        let correct = (0..<correctCount).map { _ in true } + (0..<(totalReps - correctCount)).map { _ in false }
        switch activityType {
        case .dribbleOrPass:
            return DecisionSpeedScore.dribbleOrPassSessionScore(reactionTimesMs: reactionTimesMs, correct: correct)
        case .oneTouchPassing:
            return DecisionSpeedScore.oneTouchSessionScore(reactionTimesMs: reactionTimesMs, correct: correct)
        case .awayFromPressure, .twoMinuteTest:
            return DecisionSpeedScore.sessionScore(reactionTimesMs: reactionTimesMs, correct: correct)
        }
    }
}
