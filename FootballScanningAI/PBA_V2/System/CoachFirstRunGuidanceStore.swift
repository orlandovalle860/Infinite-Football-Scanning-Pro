//
//  CoachFirstRunGuidanceStore.swift
//  FootballScanningAI
//
//  Persists whether the coach has finished a full block for an activity so we only
//  show first-rep onboarding cues once per activity (UserDefaults; keyed by session activity id).
//

import Foundation

enum CoachFirstRunGuidanceStore {
    private static let keyPrefix = "coachFirstRunGuidanceCompleted."

    static func hasCompletedFirstRun(activityId: String) -> Bool {
        guard !activityId.isEmpty else { return true }
        return UserDefaults.standard.bool(forKey: keyPrefix + activityId)
    }

    /// Call when the coach completes the full block / session for this activity.
    static func markCompletedFirstRun(activityId: String) {
        guard !activityId.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: keyPrefix + activityId)
    }
}
