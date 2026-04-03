import Foundation
import CoreGraphics

struct WedgeCueStyle {
    let laneSpan: CGFloat
    let depthFraction: CGFloat
    let centerGapFraction: CGFloat
    let opacity: CGFloat

    static func style(for level: Int) -> WedgeCueStyle {
        switch max(1, min(3, level)) {
        case 1:
            return WedgeCueStyle(laneSpan: 0.78, depthFraction: 0.24, centerGapFraction: 0.20, opacity: 0.86)
        case 2:
            // Subtle increase in challenge: slightly narrower + slightly farther from center.
            return WedgeCueStyle(laneSpan: 0.70, depthFraction: 0.22, centerGapFraction: 0.23, opacity: 0.84)
        default:
            return WedgeCueStyle(laneSpan: 0.64, depthFraction: 0.20, centerGapFraction: 0.26, opacity: 0.82)
        }
    }
}

enum WedgeDifficultyEngine {
    private static let levelKeyPrefix = "wedge_difficulty_level"
    private static let lastEvalDateKeyPrefix = "wedge_difficulty_last_eval_date"

    static func currentLevel(playerId: UUID?) -> Int {
        let pid = playerId?.uuidString ?? "global"
        let key = "\(levelKeyPrefix)_\(pid)"
        let stored = UserDefaults.standard.integer(forKey: key)
        return max(1, min(3, stored == 0 ? 1 : stored))
    }

    static func currentStyle(playerId: UUID?) -> WedgeCueStyle {
        WedgeCueStyle.style(for: currentLevel(playerId: playerId))
    }

    /// Evaluates between sessions only. Returns true only when level increases.
    static func evaluateAndAdvanceIfNeeded(playerId: UUID?, sessions: [SessionResult]) -> Bool {
        let pid = playerId?.uuidString ?? "global"
        let levelKey = "\(levelKeyPrefix)_\(pid)"
        let dateKey = "\(lastEvalDateKeyPrefix)_\(pid)"
        let defaults = UserDefaults.standard

        let training = sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        guard let newest = training.first?.date else { return false }
        if let lastEval = defaults.object(forKey: dateKey) as? Date, newest <= lastEval {
            return false
        }

        let previousLevel = currentLevel(playerId: playerId)
        var level = previousLevel
        let recentTwo = Array(training.prefix(2))
        if recentTwo.count == 2 {
            let times = recentTwo.compactMap(\.avgDecisionTime)
            let hasGoodSpeed = !times.isEmpty && (times.reduce(0, +) / Double(times.count)) < 1.10
            let accuracyValues = recentTwo.filter { $0.totalReps > 0 }.map { Double($0.correctCount) / Double($0.totalReps) }
            let hasGoodAccuracy = !accuracyValues.isEmpty && (accuracyValues.reduce(0, +) / Double(accuracyValues.count)) >= 0.80
            if hasGoodSpeed && hasGoodAccuracy {
                level = min(3, level + 1)
            }
        }

        defaults.set(level, forKey: levelKey)
        defaults.set(newest, forKey: dateKey)
        return level > previousLevel
    }

    /// Removes wedge difficulty UserDefaults for a player (account sign-out).
    static func clearStoredKeys(forPlayerId id: UUID) {
        let pid = id.uuidString
        UserDefaults.standard.removeObject(forKey: "\(levelKeyPrefix)_\(pid)")
        UserDefaults.standard.removeObject(forKey: "\(lastEvalDateKeyPrefix)_\(pid)")
    }
}
