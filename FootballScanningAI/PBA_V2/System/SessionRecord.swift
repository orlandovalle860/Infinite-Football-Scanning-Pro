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
    /// Snake_case id for session_activities.activity_id (e.g. "two_minute_test", "dribble_or_pass").
    var sessionActivityActivityId: String {
        switch self {
        case .twoMinuteTest: return "two_minute_test"
        case .awayFromPressure: return "away_from_pressure"
        case .dribbleOrPass: return "dribble_or_pass"
        case .oneTouchPassing: return "one_touch_passing"
        }
    }

    /// Inverse of ``sessionActivityActivityId`` for relay `sessionStarted` payloads.
    static func fromSessionActivityId(_ id: String) -> ActivityKind? {
        switch id {
        case "two_minute_test": return .twoMinuteTest
        case "away_from_pressure": return .awayFromPressure
        case "dribble_or_pass": return .dribbleOrPass
        case "one_touch_passing": return .oneTouchPassing
        default: return nil
        }
    }

    /// User-facing activity label (display only; not used for routing or persistence).
    var displayName: String {
        switch self {
        case .dribbleOrPass: return "Dribble or Pass"
        case .twoMinuteTest: return "Meet the Ball"
        case .awayFromPressure: return "Away from Pressure"
        case .oneTouchPassing: return "One Touch Passing"
        }
    }

    /// Session summary breakdown label — same as ``displayName`` (single source of truth).
    var sessionSummaryDisplayName: String { displayName }

    /// Short subtitle for activity picker tiles and home cards.
    var activityPickerSubtitle: String {
        switch self {
        case .twoMinuteTest: return "Move early, arrive prepared"
        case .dribbleOrPass: return "Read space or play early"
        case .awayFromPressure: return "Find the safe side"
        case .oneTouchPassing: return "Play fast, scan early"
        }
    }

    /// SF Symbol for activity picker tiles.
    var activityPickerIcon: String {
        switch self {
        case .twoMinuteTest: return "figure.run"
        case .dribbleOrPass: return "arrow.triangle.branch"
        case .awayFromPressure: return "shield.lefthalf.filled"
        case .oneTouchPassing: return "bolt.fill"
        }
    }

    static let sessionSummaryDisplayOrder: [ActivityKind] = [
        .dribbleOrPass,
        .twoMinuteTest,
        .awayFromPressure,
        .oneTouchPassing
    ]

    /// Optional one-line cue shown at session start (display only).
    var sessionStartCue: ActivitySessionStartCueContent? {
        switch self {
        case .twoMinuteTest:
            return ActivitySessionStartCueContent(
                leadingText: "Meet the",
                inlineVisual: .imageAsset("SoccerBall"),
                trailingText: "with your first touch"
            )
        case .awayFromPressure:
            return ActivitySessionStartCueContent(
                leadingText: "Move away from the defender",
                inlineVisual: .awayFromPressureDefenderLane
            )
        case .dribbleOrPass:
            return ActivitySessionStartCueContent(
                leadingText: "Open space: dribble • teammate: pass",
                inlineVisual: .dribbleOrPassTeammateLane
            )
        case .oneTouchPassing:
            return ActivitySessionStartCueContent(
                leadingText: "Play quickly with one touch"
            )
        }
    }
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
    /// Actual number of decisions completed in this block (e.g. 10 for 2-min test, 12 for training). Used for accurate tracking when block sizes vary.
    let decisionsCompleted: Int
    let correct: Int
    let forwardCorrect: Int?
    let speedBucket: SpeedBucket?
    let bias: String?
    let avgLatency: Double?
    /// Non-nil for .twoMinuteTest; nil for training blocks.
    let profile: PlayerProfile?
    /// Player this session belongs to; nil for legacy records (pre–player support).
    let playerId: UUID?
    /// True after this session has been successfully uploaded to Supabase; false when saved only locally (e.g. offline).
    let synced: Bool
    /// Decision Speed Score (0–100) for this session; stored in sessions table for analytics / progress.
    let decisionSpeedScore: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, activity, gridSize, difficulty, reps, decisionsCompleted
        case correct, forwardCorrect, speedBucket, bias, avgLatency, profile, playerId, synced, decisionSpeedScore
    }

    init(id: UUID, date: Date, activity: ActivityKind, gridSize: GridSize, difficulty: TestDifficulty, reps: Int, decisionsCompleted: Int, correct: Int, forwardCorrect: Int?, speedBucket: SpeedBucket?, bias: String?, avgLatency: Double?, profile: PlayerProfile?, playerId: UUID? = nil, synced: Bool = false, decisionSpeedScore: Int? = nil) {
        self.id = id
        self.date = date
        self.activity = activity
        self.gridSize = gridSize
        self.difficulty = difficulty
        self.reps = reps
        self.decisionsCompleted = decisionsCompleted
        self.correct = correct
        self.forwardCorrect = forwardCorrect
        self.speedBucket = speedBucket
        self.bias = bias
        self.avgLatency = avgLatency
        self.profile = profile
        self.playerId = playerId
        self.synced = synced
        self.decisionSpeedScore = decisionSpeedScore
    }

    /// Returns a copy with the given synced value (used after successful upload).
    func with(synced: Bool) -> SessionRecord {
        SessionRecord(id: id, date: date, activity: activity, gridSize: gridSize, difficulty: difficulty, reps: reps, decisionsCompleted: decisionsCompleted, correct: correct, forwardCorrect: forwardCorrect, speedBucket: speedBucket, bias: bias, avgLatency: avgLatency, profile: profile, playerId: playerId, synced: synced, decisionSpeedScore: decisionSpeedScore)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        activity = try c.decode(ActivityKind.self, forKey: .activity)
        gridSize = try c.decode(GridSize.self, forKey: .gridSize)
        difficulty = try c.decode(TestDifficulty.self, forKey: .difficulty)
        reps = try c.decode(Int.self, forKey: .reps)
        decisionsCompleted = try c.decodeIfPresent(Int.self, forKey: .decisionsCompleted) ?? reps
        correct = try c.decode(Int.self, forKey: .correct)
        forwardCorrect = try c.decodeIfPresent(Int.self, forKey: .forwardCorrect)
        speedBucket = try c.decodeIfPresent(SpeedBucket.self, forKey: .speedBucket)
        bias = try c.decodeIfPresent(String.self, forKey: .bias)
        avgLatency = try c.decodeIfPresent(Double.self, forKey: .avgLatency)
        profile = try c.decodeIfPresent(PlayerProfile.self, forKey: .profile)
        playerId = try c.decodeIfPresent(UUID.self, forKey: .playerId)
        // Default false so legacy sessions (no key) and offline/new sessions are uploaded on launch.
        synced = try c.decodeIfPresent(Bool.self, forKey: .synced) ?? false
        decisionSpeedScore = try c.decodeIfPresent(Int.self, forKey: .decisionSpeedScore)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(activity, forKey: .activity)
        try c.encode(gridSize, forKey: .gridSize)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(reps, forKey: .reps)
        try c.encode(decisionsCompleted, forKey: .decisionsCompleted)
        try c.encode(correct, forKey: .correct)
        try c.encodeIfPresent(forwardCorrect, forKey: .forwardCorrect)
        try c.encodeIfPresent(speedBucket, forKey: .speedBucket)
        try c.encodeIfPresent(bias, forKey: .bias)
        try c.encodeIfPresent(avgLatency, forKey: .avgLatency)
        try c.encodeIfPresent(profile, forKey: .profile)
        try c.encodeIfPresent(playerId, forKey: .playerId)
        try c.encode(synced, forKey: .synced)
        try c.encodeIfPresent(decisionSpeedScore, forKey: .decisionSpeedScore)
    }
}
