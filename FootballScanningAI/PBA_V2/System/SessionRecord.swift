//
//  SessionRecord.swift
//  FootballScanningAI
//
//  PBA V2 — Persisted session for progress (2-min test, Away From Pressure, etc.).
//

import Foundation

enum ActivityKind: String, Codable, Hashable, Identifiable {
    case twoMinuteTest
    case awayFromPressure
    case dribbleOrPass
    case oneTouchPassing
    public var id: String { rawValue }
}

enum GridSize: String, Codable {
    case fiveByFive
    case sevenBySeven
}

enum SpeedBucket: String, Codable {
    case fast
    case medium
    case slow
}

/// Profile label for 2-minute test (stored with SessionRecord; nil for training blocks).
enum PlayerProfile: String, Codable {
    case latePlanner = "Late Planner"
    case predictable = "Predictable"
    case safePlayer = "Safe Player"
    case gameReady = "Game Ready"
}

struct SessionRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let activity: ActivityKind
    let gridSize: GridSize
    let difficulty: TestDifficulty
    let reps: Int
    let correct: Int
    let forwardCorrect: Int?
    let speedBucket: SpeedBucket?
    let bias: String?
    let avgLatency: Double?
    /// Non-nil for .twoMinuteTest; nil for training blocks.
    let profile: PlayerProfile?
    /// Player this session belongs to; nil for legacy records (pre–player support).
    let playerId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, date, activity, gridSize, difficulty, reps, correct
        case forwardCorrect, speedBucket, bias, avgLatency, profile, playerId
    }

    init(id: UUID, date: Date, activity: ActivityKind, gridSize: GridSize, difficulty: TestDifficulty, reps: Int, correct: Int, forwardCorrect: Int?, speedBucket: SpeedBucket?, bias: String?, avgLatency: Double?, profile: PlayerProfile?, playerId: UUID? = nil) {
        self.id = id
        self.date = date
        self.activity = activity
        self.gridSize = gridSize
        self.difficulty = difficulty
        self.reps = reps
        self.correct = correct
        self.forwardCorrect = forwardCorrect
        self.speedBucket = speedBucket
        self.bias = bias
        self.avgLatency = avgLatency
        self.profile = profile
        self.playerId = playerId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        activity = try c.decode(ActivityKind.self, forKey: .activity)
        gridSize = try c.decode(GridSize.self, forKey: .gridSize)
        difficulty = try c.decode(TestDifficulty.self, forKey: .difficulty)
        reps = try c.decode(Int.self, forKey: .reps)
        correct = try c.decode(Int.self, forKey: .correct)
        forwardCorrect = try c.decodeIfPresent(Int.self, forKey: .forwardCorrect)
        speedBucket = try c.decodeIfPresent(SpeedBucket.self, forKey: .speedBucket)
        bias = try c.decodeIfPresent(String.self, forKey: .bias)
        avgLatency = try c.decodeIfPresent(Double.self, forKey: .avgLatency)
        profile = try c.decodeIfPresent(PlayerProfile.self, forKey: .profile)
        playerId = try c.decodeIfPresent(UUID.self, forKey: .playerId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(activity, forKey: .activity)
        try c.encode(gridSize, forKey: .gridSize)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(reps, forKey: .reps)
        try c.encode(correct, forKey: .correct)
        try c.encodeIfPresent(forwardCorrect, forKey: .forwardCorrect)
        try c.encodeIfPresent(speedBucket, forKey: .speedBucket)
        try c.encodeIfPresent(bias, forKey: .bias)
        try c.encodeIfPresent(avgLatency, forKey: .avgLatency)
        try c.encodeIfPresent(profile, forKey: .profile)
        try c.encodeIfPresent(playerId, forKey: .playerId)
    }
}
