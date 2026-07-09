//
//  SessionSummaryExperienceCopy.swift
//  FootballScanningAI
//
//  Headline, insight, and next-focus copy for timed session summary.
//

import Foundation

enum SessionSummaryExperienceCopy {
    static func headline(totalReps: Int, activityCount: Int) -> String {
        let situationWord = activityCount == 1 ? "game situation" : "game situations"
        return "\(totalReps) reps across \(activityCount) \(situationWord)"
    }

    static func insight(activityCounts: [ActivityKind: Int]) -> String {
        guard let top = activityCounts.max(by: { $0.value < $1.value }) else {
            return "You trained across multiple game situations."
        }

        switch top.key {
        case .dribbleOrPass:
            return "You focused on decision-making with the ball."
        case .twoMinuteTest:
            return "You trained meeting the ball with early movement."
        case .awayFromPressure:
            return "You trained playing away from pressure."
        case .oneTouchPassing:
            return "You trained quick passing decisions."
        }
    }

    static func sortedActivities(_ counts: [ActivityKind: Int]) -> [(ActivityKind, Int)] {
        counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.displayName < rhs.key.displayName
        }
    }

    static func nextFocusSuggestion(activityCounts: [ActivityKind: Int]) -> String {
        guard activityCounts.count > 1,
              let least = activityCounts.min(by: { $0.value < $1.value }) else {
            return "Keep training across all activities."
        }
        return "Next: focus on \(least.key.displayName)"
    }
}

extension ActivityKind {
    static func timedSessionActivityCounts(from repCountsById: [String: Int]) -> [ActivityKind: Int] {
        var result: [ActivityKind: Int] = [:]
        for activity in sessionSummaryDisplayOrder {
            let count = repCountsById[activity.sessionActivityActivityId, default: 0]
            if count > 0 {
                result[activity] = count
            }
        }
        return result
    }
}
