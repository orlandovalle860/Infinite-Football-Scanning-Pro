//
//  CoachingTrainingNotificationPlanner.swift
//  FootballScanningAI
//
//  Chooses inactivity nudges using existing session data.
//

import Foundation

struct CoachingTrainingNudgePlan {
    let kind: CoachingTrainingNudgeKind
    let title: String
    let body: String
}

enum CoachingTrainingNotificationPlanner {

    private static let trainingActivities: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]

    /// Builds the next nudge, or nil if we shouldn't message (no player / trained today / no history).
    static func makePlan(
        playerId: UUID?,
        profile: UserProfile?,
        progressStore: ProgressStore
    ) -> CoachingTrainingNudgePlan? {
        guard let playerId else { return nil }

        let trainedToday = hasTrainedToday(playerId: playerId, progressStore: progressStore)
        let lastRecordDate = mostRecentSessionRecordDate(playerId: playerId, progressStore: progressStore)

        if !trainedToday, let idle = inactivityPlanIfEligible(playerId: playerId, progressStore: progressStore) {
            return idle
        }

        if lastRecordDate == nil {
            let body = "Start with \(ActivityKind.twoMinuteTest.displayName) or jump into a training block when you're ready."
            return CoachingTrainingNudgePlan(
                kind: .flowNextFocus,
                title: "Start training",
                body: body
            )
        }

        return nil
    }

    /// 1–3 calendar days since last training record; caller ensures not trained today.
    private static func inactivityPlanIfEligible(
        playerId: UUID,
        progressStore: ProgressStore
    ) -> CoachingTrainingNudgePlan? {
        guard let last = mostRecentSessionRecordDate(playerId: playerId, progressStore: progressStore) else { return nil }
        let days = daysSinceSession(last)
        guard days >= 1, days <= 3 else { return nil }

        let kind = CoachingTrainingNudgeKind.inactivityEarly
        return CoachingTrainingNudgePlan(kind: kind, title: CoachingTrainingNotificationCopy.title(for: kind), body: "")
    }

    private static func hasTrainedToday(playerId: UUID, progressStore: ProgressStore) -> Bool {
        let cal = Calendar.current
        return progressStore.sessions.contains { record in
            record.playerId == playerId &&
            (record.activity == .twoMinuteTest || trainingActivities.contains(record.activity)) &&
            cal.isDateInToday(record.date)
        }
    }

    private static func mostRecentSessionRecordDate(playerId: UUID, progressStore: ProgressStore) -> Date? {
        progressStore.sessions
            .filter { $0.playerId == playerId && ($0.activity == .twoMinuteTest || trainingActivities.contains($0.activity)) }
            .max(by: { $0.date < $1.date })?
            .date
    }

    private static func daysSinceSession(_ date: Date) -> Int {
        let cal = Calendar.current
        let startLast = cal.startOfDay(for: date)
        let startNow = cal.startOfDay(for: Date())
        return cal.dateComponents([.day], from: startLast, to: startNow).day ?? 0
    }
}
