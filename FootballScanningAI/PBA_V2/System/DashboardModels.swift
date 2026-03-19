//
//  DashboardModels.swift
//  FootballScanningAI
//
//  PBA V2 — Daily target, consistency, decision score, status levels for Start Page.
//

import Foundation

// Training activities: .awayFromPressure, .dribbleOrPass, .oneTouchPassing (12-rep blocks).

// MARK: - Daily Target

struct DailyTargetState {
    static let targetBlocksPerDay = 3
    private static let dateKey = "pba_daily_date"
    private static let countKey = "pba_daily_blocks"

    static func completedBlocksToday(playerId: UUID?) -> Int {
        let key = playerId.map { "\(countKey)_\($0.uuidString)" } ?? countKey
        let dateKey = playerId.map { "\(self.dateKey)_\($0.uuidString)" } ?? self.dateKey
        let today = dateKeyString(Date())
        if let stored = UserDefaults.standard.string(forKey: dateKey), stored == today {
            return UserDefaults.standard.integer(forKey: key)
        }
        return 0
    }

    static func incrementToday(playerId: UUID?) {
        let key = playerId.map { "\(countKey)_\($0.uuidString)" } ?? countKey
        let dateKey = playerId.map { "\(self.dateKey)_\($0.uuidString)" } ?? self.dateKey
        let today = dateKeyString(Date())
        if let stored = UserDefaults.standard.string(forKey: dateKey), stored != today {
            UserDefaults.standard.set(0, forKey: key)
        }
        UserDefaults.standard.set(today, forKey: dateKey)
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }

    private static func dateKeyString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

// MARK: - Daily Decision Goal (36 decisions per day = 3 blocks of 12)

/// Tracks daily decisions completed per player. Stored in UserDefaults under key namespace `pba_daily_progress`.
/// Each time a decision occurs in any activity, the counter is incremented (via ProgressStore.add(record) → addDecisions(record.reps)).
/// The counter resets automatically when the calendar date changes (on next add or when read: past date returns 0).
struct DailyDecisionProgress {
    static let goalPerDay = 36
    private static let dateKeyPrefix = "pba_daily_progress_date"
    private static let countKeyPrefix = "pba_daily_progress"

    /// Decisions completed today for the given player (nil = legacy/unselected). Returns 0 when the stored date is not today (automatic reset).
    static func decisionsCompletedToday(playerId: UUID?) -> Int {
        let dateKey = playerId.map { "\(dateKeyPrefix)_\($0.uuidString)" } ?? dateKeyPrefix
        let countKey = playerId.map { "\(countKeyPrefix)_\($0.uuidString)" } ?? countKeyPrefix
        let today = dateKeyString(Date())
        if let stored = UserDefaults.standard.string(forKey: dateKey), stored == today {
            return UserDefaults.standard.integer(forKey: countKey)
        }
        return 0
    }

    /// Increment today’s decision counter. Called when decisions are recorded (e.g. ProgressStore.add adds record.reps). Resets count to 0 when the calendar date has changed.
    static func addDecisions(_ count: Int, playerId: UUID?) {
        let dateKey = playerId.map { "\(dateKeyPrefix)_\($0.uuidString)" } ?? dateKeyPrefix
        let countKey = playerId.map { "\(countKeyPrefix)_\($0.uuidString)" } ?? countKeyPrefix
        let today = dateKeyString(Date())
        if let stored = UserDefaults.standard.string(forKey: dateKey), stored != today {
            UserDefaults.standard.set(0, forKey: countKey)
        }
        UserDefaults.standard.set(today, forKey: dateKey)
        let current = UserDefaults.standard.integer(forKey: countKey)
        UserDefaults.standard.set(current + count, forKey: countKey)
    }

    /// Remove stored daily progress for a player (e.g. when profile is deleted).
    static func clearForPlayer(_ id: UUID) {
        UserDefaults.standard.removeObject(forKey: "\(dateKeyPrefix)_\(id.uuidString)")
        UserDefaults.standard.removeObject(forKey: "\(countKeyPrefix)_\(id.uuidString)")
    }

    private static func dateKeyString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

// MARK: - Decision Consistency (within-session variation of decision speed)

/// Within-session stability of decision speed. Lower variation = higher consistency.
enum DecisionConsistencyLabel: String {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    /// From session result: use decisionTimeStdDev when available; otherwise infer from speed bucket distribution.
    static func from(session: SessionResult?) -> DecisionConsistencyLabel? {
        guard let s = session, s.totalReps > 0 else { return nil }
        if let stdDev = s.decisionTimeStdDev {
            if stdDev < 0.20 { return .high }
            if stdDev < 0.45 { return .medium }
            return .low
        }
        let (f, m, sl) = (s.speedCounts.fast, s.speedCounts.medium, s.speedCounts.slow)
        let total = f + m + sl
        guard total > 0 else { return nil }
        let maxInOne = max(f, m, sl)
        if Double(maxInOne) >= Double(total) * 0.83 { return .high }
        if Double(maxInOne) >= Double(total) * 0.58 { return .medium }
        return .low
    }
}

// MARK: - Consistency (from last 5 blocks)

enum ConsistencyLabel: String {
    case steady = "Steady"
    case improving = "Improving"
    case streaky = "Streaky"
}

enum DashboardConsistency {
    /// Uses last 5 training blocks (any activity) for overall; or pass activity-specific list for advancement.
    static func consistencyScore(from last5: [SessionRecord]) -> Int {
        guard last5.count >= 2 else { return 0 }
        let corrects = last5.map(\.correct)
        let speeds = last5.compactMap(\.speedBucket)

        let rangeCorrect = (corrects.max() ?? 0) - (corrects.min() ?? 0)
        let accuracyPoints: Int
        if rangeCorrect <= 1 { accuracyPoints = 40 }
        else if rangeCorrect <= 3 { accuracyPoints = 30 }
        else if rangeCorrect <= 5 { accuracyPoints = 20 }
        else { accuracyPoints = 10 }

        let speedValues = speeds.map { s -> Int in
            switch s {
            case .fast: return 3
            case .medium: return 2
            case .slow: return 1
            }
        }
        let rangeSpeed = (speedValues.max() ?? 0) - (speedValues.min() ?? 0)
        let timingPoints: Int
        if rangeSpeed == 0 { timingPoints = 30 }
        else if rangeSpeed == 1 { timingPoints = 20 }
        else { timingPoints = 10 }

        let badBlocks = corrects.filter { $0 <= 5 }.count
        let penalty = min(30, badBlocks * 10)

        return max(0, min(100, accuracyPoints + timingPoints - penalty))
    }

    static func label(from last5: [SessionRecord]) -> ConsistencyLabel {
        let score = consistencyScore(from: last5)
        if score >= PBARecommendationConfig.consistencySteadyMin { return .steady }
        if score >= PBARecommendationConfig.consistencyImprovingMin { return .improving }
        return .streaky
    }
}

// MARK: - Player Level (development stages from decision score)

/// Player level for Home snapshot: translates decision score (0–100) into simple development stages.
enum PlayerDevelopmentLevel: String {
    case rookie = "Rookie"           // 0–40
    case explorer = "Explorer"        // 40–60
    case playmaker = "Playmaker"      // 60–75
    case fieldGeneral = "Field General" // 75–90
    case elite = "Elite"              // 90+

    static func level(fromScore score: Int) -> PlayerDevelopmentLevel {
        switch score {
        case 90...: return .elite
        case 75..<90: return .fieldGeneral
        case 60..<75: return .playmaker
        case 40..<60: return .explorer
        default: return .rookie
        }
    }
}

// MARK: - Decision Score (0–100) + Status

enum PlayerStatus: String {
    case beginner = "Beginner"
    case developing = "Developing"
    case playmaker = "Playmaker"
    case elite = "Elite"
}

enum DashboardDecisionScore {
    /// v2: Accuracy 60 pts max + Decision speed 40 pts max (from avg decision time). Bias not in score; show as insight only.
    /// From last 3 training blocks; uses actual avgLatency when available, else speed-bucket fallback.
    static func score(from sessions: [SessionRecord]) -> Int {
        let list = Array(sessions.prefix(3))
        guard !list.isEmpty else { return 0 }
        let accuracySum = list.map { accuracyPoints($0) }.reduce(0, +)
        let speedSum = list.map { speedPoints($0) }.reduce(0, +)
        let n = Double(list.count)
        return max(0, min(100, Int(round((accuracySum + speedSum) / n))))
    }

    /// Accuracy: 60 points max. correct/decisionsCompleted * 60.
    private static func accuracyPoints(_ session: SessionRecord) -> Double {
        let total = max(1, session.decisionsCompleted)
        return Double(session.correct) / Double(total) * 60.0
    }

    /// Decision speed: 40 points max. Uses avgLatency (seconds): 0.75s = 40, 1.35s = 0, linear. When avgLatency nil, fallback to speedBucket for backward compatibility.
    private static func speedPoints(_ session: SessionRecord) -> Double {
        if let avg = session.avgLatency {
            // 40 pts at 0.75s and below, 0 pts at 1.35s and above
            let raw = (1.35 - avg) / (1.35 - 0.75)
            return 40.0 * max(0, min(1, raw))
        }
        // Fallback when avgLatency not stored (e.g. older records)
        guard let bucket = session.speedBucket else { return 20 }
        switch bucket {
        case .fast: return 40
        case .medium: return 20
        case .slow: return 0
        }
    }

    static func status(score: Int, consistencyLabel: ConsistencyLabel) -> PlayerStatus {
        if score >= PBARecommendationConfig.eliteDecisionScore && consistencyLabel == .steady { return .elite }
        if score >= PBARecommendationConfig.playmakerDecisionScore { return .playmaker }
        if score >= PBARecommendationConfig.developingDecisionScore { return .developing }
        return .beginner
    }
}

// MARK: - Last status (for upgrade toast)

private let lastStatusKey = "pba_last_status_raw"

extension PlayerStatus {
    static func loadLastStatus(playerId: UUID?) -> PlayerStatus? {
        let key = playerId.map { "\(lastStatusKey)_\($0.uuidString)" } ?? lastStatusKey
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return PlayerStatus(rawValue: raw)
    }

    func saveAsLastStatus(playerId: UUID?) {
        let key = playerId.map { "\(lastStatusKey)_\($0.uuidString)" } ?? lastStatusKey
        UserDefaults.standard.set(rawValue, forKey: key)
    }
}

// MARK: - Scan Efficiency (accuracy + first-touch + speed in one score)

/// Combines decision accuracy, first-touch accuracy, and decision speed into a single 0–100 score.
/// Purpose: how efficiently the player converts perception into action.
enum ScanEfficiency {
    /// SpeedScore per rep: Fast = 100, Medium = 70, Slow = 40.
    private static func speedScore(fast: Int, medium: Int, slow: Int, totalReps: Int) -> Double {
        guard totalReps > 0 else { return 0 }
        return (Double(fast) * 100 + Double(medium) * 70 + Double(slow) * 40) / Double(totalReps)
    }

    /// ScanEfficiency = (accuracy × 0.5) + (firstTouchAccuracy × 0.3) + (speedScore × 0.2). Returns 0–100.
    static func score(from session: SessionResult) -> Double {
        let totalReps = session.totalReps
        guard totalReps > 0 else { return 0 }
        let accuracy = Double(session.correctCount) / Double(totalReps) * 100.0
        let firstTouchAccuracy: Double = {
            guard let match = session.firstTouchMatchCount else { return 0 }
            return Double(match) / Double(totalReps) * 100.0
        }()
        let speed = speedScore(
            fast: session.speedCounts.fast,
            medium: session.speedCounts.medium,
            slow: session.speedCounts.slow,
            totalReps: totalReps
        )
        return accuracy * 0.5 + firstTouchAccuracy * 0.3 + speed * 0.2
    }
}
