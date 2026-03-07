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
    /// From last block or rolling average of last 3 training blocks.
    static func score(from sessions: [SessionRecord]) -> Int {
        let list = sessions.prefix(3)
        guard !list.isEmpty else { return 0 }
        let totalReps = 12
        let accuracySum = list.map { Double($0.correct) / Double(totalReps) * 50 }.reduce(0, +)
        let timingSum = list.map { timingPoints($0.speedBucket) }.reduce(0, +)
        let biasSum = list.map { biasPoints($0.bias) }.reduce(0, +)
        let n = Double(list.count)
        return max(0, min(100, Int((accuracySum + timingSum + biasSum) / n)))
    }

    private static func timingPoints(_ speed: SpeedBucket?) -> Double {
        guard let s = speed else { return 15 }
        switch s {
        case .fast: return 30
        case .medium: return 20
        case .slow: return 10
        }
    }

    private static func biasPoints(_ bias: String?) -> Double {
        guard let b = bias, !b.isEmpty, b != "None", b != "Balanced" else { return 20 }
        return 10
    }

    /// Bias >= 70% would be "extreme" (5 pts) — we don't store %, so use presence of bias as 10; no bias 20.
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
