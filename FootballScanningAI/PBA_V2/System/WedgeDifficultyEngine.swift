import Foundation
import CoreGraphics

/// Playable field as a square centered in the display rect — wedge sizing uses `squareSize` only.
struct WedgeFieldGeometry {
    let fieldWidth: CGFloat
    let fieldHeight: CGFloat
    let squareSize: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat

    init(fieldWidth w: CGFloat, fieldHeight h: CGFloat) {
        fieldWidth = w
        fieldHeight = h
        squareSize = min(w, h)
        originX = (w - squareSize) / 2
        originY = (h - squareSize) / 2
        centerX = w / 2
        centerY = h / 2
    }
}

struct WedgeCueStyle {
    /// Fraction of the active edge length for wedge / green-rectangle base (centered on that edge). Wider than a sliver, but clamped below full edge.
    let laneSpan: CGFloat
    let depthFraction: CGFloat
    let centerGapFraction: CGFloat
    let opacity: CGFloat

    /// Slight inward offset from the field border so cues read from the field interior, not the bezel.
    static let edgeInsetFraction: CGFloat = 0.018

    /// Top/bottom span along edge — narrower so horizontal bands don't dominate in landscape.
    private static let horizontalEdgeSpanScale: CGFloat = 0.865
    /// Left/right depth toward center — slightly thicker so vertical wedges aren't thin pillars.
    private static let verticalEdgeDepthScale: CGFloat = 1.09

    static func style(for level: Int) -> WedgeCueStyle {
        switch max(1, min(3, level)) {
        case 1:
            return WedgeCueStyle(laneSpan: 0.50, depthFraction: 0.24, centerGapFraction: 0.21, opacity: 0.86)
        case 2:
            // Subtle increase in challenge: slightly narrower + slightly farther from center.
            return WedgeCueStyle(laneSpan: 0.46, depthFraction: 0.22, centerGapFraction: 0.242, opacity: 0.84)
        default:
            return WedgeCueStyle(laneSpan: 0.42, depthFraction: 0.20, centerGapFraction: 0.273, opacity: 0.82)
        }
    }

    /// Span along the edge the wedge sits on, based on centered square `min(w,h)`.
    /// Top/bottom spans are reduced ~13.5% for balanced visual weight in landscape.
    func spanAlongEdge(for gate: Gate, fieldWidth w: CGFloat, fieldHeight h: CGFloat) -> CGFloat {
        let s = min(w, h)
        let raw = s * laneSpan * spanScale(for: gate)
        return min(s * 0.58, max(s * 0.38, raw))
    }

    /// Depth from edge toward center. Left/right wedges use a ~9% boost so they read as thicker bars, not tall slivers.
    func depthAlongCenter(for gate: Gate, fieldWidth w: CGFloat, fieldHeight h: CGFloat) -> CGFloat {
        let s = min(w, h)
        let depthScale: CGFloat = (gate == .left || gate == .right) ? Self.verticalEdgeDepthScale : 1
        return s * depthFraction * depthScale
    }

    /// Left/right span along edge — slightly taller so vertical wedges balance narrowed top/bottom bands.
    private static let verticalEdgeSpanScale: CGFloat = verticalEdgeDepthScale

    func spanScale(for gate: Gate) -> CGFloat {
        switch gate {
        case .up, .down: return Self.horizontalEdgeSpanScale
        case .left, .right: return Self.verticalEdgeSpanScale
        }
    }
}

/// Fixed snap points on the centered square — identical whether 1, 2, 3, or 4 wedges are visible.
struct WedgeDirectionalAnchors {
    let gate: Gate
    let field: WedgeFieldGeometry
    let style: WedgeCueStyle

    var squareSize: CGFloat { field.squareSize }
    var centerGap: CGFloat { squareSize * style.centerGapFraction }
    var edgeInset: CGFloat { squareSize * WedgeCueStyle.edgeInsetFraction }
    var span: CGFloat {
        style.spanAlongEdge(for: gate, fieldWidth: field.fieldWidth, fieldHeight: field.fieldHeight)
    }
    var halfBase: CGFloat { span / 2 }

    /// Outer base on the square edge (fixed inset from border).
    var baseY: CGFloat {
        switch gate {
        case .up: return field.originY + edgeInset
        case .down: return field.originY + squareSize - edgeInset
        case .left, .right: return field.centerY
        }
    }

    var baseX: CGFloat {
        switch gate {
        case .left: return field.originX + edgeInset
        case .right: return field.originX + squareSize - edgeInset
        case .up, .down: return field.centerX
        }
    }

    /// Inner boundary — same radius from center on every axis (part of a 4-direction ring).
    var innerTipY: CGFloat {
        switch gate {
        case .up: return field.centerY - centerGap
        case .down: return field.centerY + centerGap
        case .left, .right: return field.centerY
        }
    }

    var innerTipX: CGFloat {
        switch gate {
        case .left: return field.centerX - centerGap
        case .right: return field.centerX + centerGap
        case .up, .down: return field.centerX
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

enum WedgeClarityDebugLog {
    static func log(side: String, widthPts: CGFloat, position: String) {
        print("[WedgeClarity-Debug] side=\(side) widthPts=\(String(format: "%.2f", widthPts)) position=\(position)")
    }
}
