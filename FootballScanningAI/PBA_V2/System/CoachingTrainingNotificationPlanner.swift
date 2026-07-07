//
//  CoachingTrainingNotificationPlanner.swift
//  FootballScanningAI
//
//  Chooses A (performance) > B (curriculum flow) > C (inactivity) using existing session + curriculum data.
//

import Foundation

struct CoachingTrainingNudgePlan {
    let kind: CoachingTrainingNudgeKind
    let title: String
    let body: String
}

enum CoachingTrainingNotificationPlanner {

    private static let trainingActivities: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]

    /// Builds the next nudge, or nil if we shouldn't message (no player / no usable history for any path).
    /// Priority: **A performance** → **B ready-to-progress** → **C inactivity (1–3 days)** → **B default next focus**.
    static func makePlan(
        playerId: UUID?,
        profile: UserProfile?,
        progressStore: ProgressStore
    ) -> CoachingTrainingNudgePlan? {
        guard let playerId else { return nil }

        let trainedToday = hasTrainedToday(playerId: playerId, progressStore: progressStore)
        let lastResult = resolveLatestSessionResult(playerId: playerId, profile: profile, progressStore: progressStore)
        let lastRecordDate = mostRecentSessionRecordDate(playerId: playerId, progressStore: progressStore)

        let guided = GuidedCurriculumEngine.currentProgress(playerId: playerId)
        let nextTitle = guided.nextActivity.displayName
        let baselineDone = GuidedCurriculumEngine.hasCompletedBaseline(playerId: playerId)

        // A — performance-driven (last session signals)
        if let session = lastResult {
            let previous = progressStore.previous(session.activityType, playerId: playerId)
            let pkg = CoachInsightGenerator.insightPackage(for: session, previous: previous)
            if let kind = performanceKind(package: pkg, session: session) {
                return CoachingTrainingNudgePlan(
                    kind: kind,
                    title: CoachingTrainingNotificationCopy.title(for: kind),
                    body: ""
                )
            }
        }

        // B — unlocked next curriculum activity but haven’t logged a block there yet
        if let readyActivity = nextCurriculumActivityToHighlight(playerId: playerId, progressStore: progressStore) {
            let templates = CoachingTrainingNotificationCopy.bodies(for: .flowReadyToProgress)
            let template = templates[variationIndex(seed: playerId, kind: .flowReadyToProgress, count: templates.count)]
            let body = CoachingTrainingNotificationCopy.formatFlowReady(template: template, nextActivityTitle: readyActivity.displayName)
            return CoachingTrainingNudgePlan(
                kind: .flowReadyToProgress,
                title: CoachingTrainingNotificationCopy.title(for: .flowReadyToProgress),
                body: body
            )
        }

        // C — light touch after 1–3 days quiet (never same-day as a session)
        if !trainedToday, let idle = inactivityPlanIfEligible(playerId: playerId, progressStore: progressStore) {
            return idle
        }

        // B — default: next focus on path
        if baselineDone || lastResult != nil || lastRecordDate != nil {
            let templates = CoachingTrainingNotificationCopy.bodies(for: .flowNextFocus)
            let template = templates[variationIndex(seed: playerId, kind: .flowNextFocus, count: templates.count)]
            let body = CoachingTrainingNotificationCopy.formatFlowNextFocus(template: template, activityTitle: nextTitle, focus: guided.focus)
            return CoachingTrainingNudgePlan(
                kind: .flowNextFocus,
                title: CoachingTrainingNotificationCopy.title(for: .flowNextFocus),
                body: body
            )
        }

        let body = "Train with \(ActivityKind.twoMinuteTest.displayName) once — it sets your path so every block targets the right habit."
        return CoachingTrainingNudgePlan(
            kind: .flowNextFocus,
            title: "Start training",
            body: body
        )
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

    // MARK: - Performance (A)

    private static func performanceKind(
        package: CoachInsightGenerator.InsightPackage,
        session: SessionResult
    ) -> CoachingTrainingNudgeKind? {
        if package.modifiers.contains(.inconsistent) {
            return .performanceInconsistent
        }
        if package.modifiers.contains(.improving), !package.modifiers.contains(.declining) {
            return .performanceImproving
        }
        if package.modifiers.contains(.declining) {
            return .performanceDeclining
        }
        let slowRate = Double(session.speedCounts.slow) / Double(max(session.totalReps, 1))
        switch package.playerState {
        case .lateCorrect:
            return .performanceSlowDecisions
        case .inconsistent:
            return .performanceInconsistent
        case .sharp, .fastIncorrect, .lateIncorrect:
            if slowRate >= 0.38 {
                return .performanceSlowDecisions
            }
        }
        return nil
    }

    // MARK: - Flow (B)

    /// Next activity in the AFP → DOP → OTP chain is **unlocked** but has **no logged session** yet, while the prior step has history.
    private static func nextCurriculumActivityToHighlight(playerId: UUID, progressStore: ProgressStore) -> ActivityKind? {
        if progressStore.isUnlocked(activity: .dribbleOrPass, playerId: playerId),
           progressStore.last(.dribbleOrPass, playerId: playerId) == nil,
           progressStore.last(.awayFromPressure, playerId: playerId) != nil {
            return .dribbleOrPass
        }
        if progressStore.isUnlocked(activity: .oneTouchPassing, playerId: playerId),
           progressStore.last(.oneTouchPassing, playerId: playerId) == nil,
           progressStore.last(.dribbleOrPass, playerId: playerId) != nil {
            return .oneTouchPassing
        }
        return nil
    }

    private static func hasTrainedToday(playerId: UUID, progressStore: ProgressStore) -> Bool {
        let cal = Calendar.current
        return progressStore.sessions.contains { record in
            record.playerId == playerId &&
            (record.activity == .twoMinuteTest || trainingActivities.contains(record.activity)) &&
            cal.isDateInToday(record.date)
        }
    }

    // MARK: - Session resolution

    private static func resolveLatestSessionResult(
        playerId: UUID,
        profile: UserProfile?,
        progressStore: ProgressStore
    ) -> SessionResult? {
        let fromProfile = profile?.sessionResults
            .filter { $0.playerID == playerId }
            .max(by: { $0.date < $1.date })

        let fromRecord = latestTrainingRecord(playerId: playerId, progressStore: progressStore).map { syntheticSessionResult(from: $0, playerId: playerId) }

        switch (fromProfile, fromRecord) {
        case (let p?, let r?):
            return p.date >= r.date ? p : r
        case (let p?, nil):
            return p
        case (nil, let r?):
            return r
        case (nil, nil):
            return nil
        }
    }

    private static func latestTrainingRecord(playerId: UUID, progressStore: ProgressStore) -> SessionRecord? {
        progressStore.sessions
            .filter { $0.playerId == playerId && ($0.activity == .twoMinuteTest || trainingActivities.contains($0.activity)) }
            .max(by: { $0.date < $1.date })
    }

    private static func mostRecentSessionRecordDate(playerId: UUID, progressStore: ProgressStore) -> Date? {
        latestTrainingRecord(playerId: playerId, progressStore: progressStore)?.date
    }

    private static func syntheticSessionResult(from record: SessionRecord, playerId: UUID) -> SessionResult {
        let n = max(record.decisionsCompleted, 1)
        let counts = speedCountsFromBucket(record.speedBucket, totalReps: n)
        return SessionResult(
            id: record.id,
            date: record.date,
            playerID: record.playerId ?? playerId,
            activityType: record.activity,
            correctCount: record.correct,
            totalReps: n,
            speedCounts: counts,
            avgDecisionTime: record.avgLatency,
            biasDirection: gate(fromBiasString: record.bias),
            directionCounts: [:],
            difficulty: record.difficulty
        )
    }

    private static func speedCountsFromBucket(_ bucket: SpeedBucket?, totalReps: Int) -> SessionSpeedCounts {
        let n = max(totalReps, 1)
        switch bucket {
        case .fast:
            let f = max(1, Int(Double(n) * 0.55))
            let s = max(0, Int(Double(n) * 0.12))
            let m = max(0, n - f - s)
            return SessionSpeedCounts(fast: f, medium: m, slow: s)
        case .slow:
            let s = max(1, Int(Double(n) * 0.45))
            let f = max(0, Int(Double(n) * 0.18))
            let m = max(0, n - f - s)
            return SessionSpeedCounts(fast: f, medium: m, slow: s)
        case .medium, .none:
            let m = max(1, Int(Double(n) * 0.4))
            let f = (n - m) / 2
            let s = max(0, n - m - f)
            return SessionSpeedCounts(fast: f, medium: m, slow: s)
        }
    }

    private static func gate(fromBiasString: String?) -> Gate? {
        guard let raw = fromBiasString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if raw.contains("left") { return .left }
        if raw.contains("right") { return .right }
        if raw.contains("up") { return .up }
        if raw.contains("down") { return .down }
        return nil
    }

    private static func daysSinceSession(_ date: Date) -> Int {
        let cal = Calendar.current
        let startLast = cal.startOfDay(for: date)
        let startNow = cal.startOfDay(for: Date())
        return cal.dateComponents([.day], from: startLast, to: startNow).day ?? 0
    }

    // MARK: - Variation

    private static func variationIndex(seed: UUID, kind: CoachingTrainingNudgeKind, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var hasher = Hasher()
        hasher.combine(seed)
        hasher.combine(kind.rawValue)
        return abs(hasher.finalize()) % count
    }
}
