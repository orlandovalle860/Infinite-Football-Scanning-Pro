import Foundation
import CoreGraphics

struct WedgeCueStyle {
    /// Fraction of the active edge length for wedge / green-rectangle base (centered on that edge). Wider than a sliver, but clamped below full edge.
    let laneSpan: CGFloat
    let depthFraction: CGFloat
    let centerGapFraction: CGFloat
    let opacity: CGFloat

    /// Slight inward offset from the field border so cues read from the field interior, not the bezel.
    static let edgeInsetFraction: CGFloat = 0.018

    static func style(for level: Int) -> WedgeCueStyle {
        switch max(1, min(3, level)) {
        case 1:
            return WedgeCueStyle(laneSpan: 0.50, depthFraction: 0.24, centerGapFraction: 0.20, opacity: 0.86)
        case 2:
            // Subtle increase in challenge: slightly narrower + slightly farther from center.
            return WedgeCueStyle(laneSpan: 0.46, depthFraction: 0.22, centerGapFraction: 0.23, opacity: 0.84)
        default:
            return WedgeCueStyle(laneSpan: 0.42, depthFraction: 0.20, centerGapFraction: 0.26, opacity: 0.82)
        }
    }

    /// Span along the edge the wedge sits on (horizontal length for top/bottom, vertical length for left/right), clamped to ~38–58% so bases are wide but never full edge.
    func spanAlongEdge(for gate: Gate, fieldWidth w: CGFloat, fieldHeight h: CGFloat) -> CGFloat {
        let edge: CGFloat
        let raw: CGFloat
        switch gate {
        case .up, .down:
            edge = w
            let base = w * laneSpan
            let aspect = h / max(w, 1)
            let reduction = max(0.78, min(1.0, aspect * 0.95))
            raw = base * reduction
        case .left, .right:
            edge = h
            raw = h * laneSpan
        }
        return min(edge * 0.58, max(edge * 0.38, raw))
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

enum WedgeClarityDebugLog {
    static func log(side: String, widthPts: CGFloat, position: String) {
        print("[WedgeClarity-Debug] side=\(side) widthPts=\(String(format: "%.2f", widthPts)) position=\(position)")
    }
}
