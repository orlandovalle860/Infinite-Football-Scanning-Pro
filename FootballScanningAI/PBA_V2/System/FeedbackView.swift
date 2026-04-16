//
//  FeedbackView.swift
//  FootballScanningAI
//
//  PBA V2 — Visual layer for Player Feedback (badge, trait tags, message).
//

import SwiftUI

struct FeedbackVisual {
    let icon: String
    let color: Color
    let title: String
}

extension PlayerFeedbackProfile {
    var feedbackVisual: FeedbackVisual {
        switch self {
        case .elite:
            return FeedbackVisual(icon: "bolt.fill", color: .green, title: "Elite")
        case .fastButInaccurate:
            return FeedbackVisual(icon: "bolt.slash.fill", color: .orange, title: "Good early decisions — now choose the right option")
        case .accurateButLate:
            return FeedbackVisual(icon: "checkmark.circle.fill", color: .blue, title: "Accurate, But Late")
        case .struggling:
            return FeedbackVisual(icon: "exclamationmark.triangle.fill", color: .red, title: "Struggling")
        }
    }
}

struct FeedbackTag: Identifiable {
    let id: UUID
    let icon: String
    let label: String
    let color: Color

    init(icon: String, label: String, color: Color) {
        self.id = UUID()
        self.icon = icon
        self.label = label
        self.color = color
    }
}

extension PlayerFeedbackEngine {
    /// Deterministic trait tags from session metrics (max 3).
    static func feedbackTags(from result: SessionResult) -> [FeedbackTag] {
        let decisionWindow = result.avgDecisionTime ?? 0
        let accuracy = result.totalReps > 0 ? Double(result.correctCount) / Double(result.totalReps) : 0
        var tags: [FeedbackTag] = []
        if decisionWindow > 0 {
            tags.append(FeedbackTag(icon: "bolt", label: "Fast Decisions", color: .green))
        } else {
            tags.append(FeedbackTag(icon: "clock", label: "Late Decisions", color: .blue))
        }
        if accuracy >= 0.75 {
            tags.append(FeedbackTag(icon: "checkmark", label: "Accurate", color: .green))
        } else {
            tags.append(FeedbackTag(icon: "xmark", label: "Wrong option", color: .red))
        }
        return Array(tags.prefix(3))
    }
}
