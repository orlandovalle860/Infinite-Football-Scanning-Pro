//
//  ProgressStore.swift
//  FootballScanningAI
//
//  PBA V2 — In-memory session state; persistence is delegated to SessionDataStore. Call load() on app launch.
//

import Foundation
import Combine

final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    @Published private(set) var sessions: [SessionRecord] = []

    /// All session reads/writes go through the data store so cloud sync can be added later without changing call sites.
    private let dataStore: SessionDataStore

    init(dataStore: SessionDataStore = LocalSessionDataStore()) {
        self.dataStore = dataStore
    }

    func load() {
        sessions = dataStore.loadSessions()
    }

    private func persist() {
        dataStore.saveSessions(sessions)
    }

    func add(_ record: SessionRecord) {
        #if DEBUG
        print("[PBA-Debug] ProgressStore.add: activity=\(record.activity.rawValue), decisionSpeedScore=\(record.decisionSpeedScore ?? -1), playerId=\(record.playerId?.uuidString ?? "nil"), correct=\(record.correct)/\(record.decisionsCompleted), date=\(record.date)")
        #endif
        sessions.insert(record, at: 0)
        if record.decisionsCompleted == 12 {
            DailyTargetState.incrementToday(playerId: record.playerId)
        }
        DailyDecisionProgress.addDecisions(record.decisionsCompleted, playerId: record.playerId)
        persist()
        #if DEBUG
        print("[PBA-Debug] ProgressStore.add: save success. sessions.count=\(sessions.count)")
        #endif
    }

    /// Sessions that have not yet been uploaded to Supabase (saved locally with synced = false).
    var unsyncedSessions: [SessionRecord] {
        sessions.filter { !$0.synced }
    }

    /// Mark a session as synced after successful upload. Persists the updated list.
    func markSynced(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index] = sessions[index].with(synced: true)
        persist()
    }

    /// Clear the unsynced sessions queue by marking all sessions as synced. Use when old sessions were saved with an outdated schema and should not be retried. Session records remain in history.
    func clearUnsyncedSessionQueue() {
        var changed = false
        for index in sessions.indices where !sessions[index].synced {
            sessions[index] = sessions[index].with(synced: true)
            changed = true
        }
        if changed { persist(); recalculateProgress() }
    }

    /// Removes all session records for the given player (e.g. when the profile is deleted).
    func removeSessions(forPlayerId id: UUID) {
        sessions.removeAll { $0.playerId == id }
        DailyDecisionProgress.clearForPlayer(id)
        persist()
        recalculateProgress()
    }

    /// Call after mutations so dependent state / UI can refresh (e.g. after removing a player).
    func recalculateProgress() {
        objectWillChange.send()
    }

    func sessions(for activity: ActivityKind) -> [SessionRecord] {
        sessions.filter { $0.activity == activity }
    }

    /// Sessions for an activity and optional player (nil = legacy; include for selected player).
    func sessions(for activity: ActivityKind, playerId: UUID?) -> [SessionRecord] {
        guard let pid = playerId else { return sessions.filter { $0.activity == activity && $0.playerId == nil } }
        return sessions.filter { $0.activity == activity && $0.playerId == pid }
    }

    func last(_ activity: ActivityKind) -> SessionRecord? {
        sessions.first(where: { $0.activity == activity })
    }

    func last(_ activity: ActivityKind, playerId: UUID?) -> SessionRecord? {
        sessions(for: activity, playerId: playerId).first
    }

    /// Session immediately before the most recent for this activity and player (for session-to-session comparison). Nil if fewer than 2 sessions.
    func previous(_ activity: ActivityKind, playerId: UUID?) -> SessionRecord? {
        let list = Array(sessions(for: activity, playerId: playerId).prefix(2))
        return list.count >= 2 ? list[1] : nil
    }

    /// Best Decision Speed Score (0–100) for this activity and player from sessions table data. Nil if no sessions with a score.
    func bestDecisionSpeedScore(activity: ActivityKind, playerId: UUID?) -> Int? {
        sessions(for: activity, playerId: playerId)
            .compactMap(\.decisionSpeedScore)
            .max()
    }

    func bestTwoMinuteTest() -> SessionRecord? {
        sessions(for: .twoMinuteTest).max(by: { $0.correct < $1.correct })
    }

    func bestTwoMinuteTest(playerId: UUID?) -> SessionRecord? {
        sessions(for: .twoMinuteTest, playerId: playerId).max(by: { $0.correct < $1.correct })
    }

    func lastN(_ activity: ActivityKind, n: Int) -> [SessionRecord] {
        Array(sessions(for: activity).prefix(n))
    }

    func lastN(_ activity: ActivityKind, n: Int, playerId: UUID?) -> [SessionRecord] {
        Array(sessions(for: activity, playerId: playerId).prefix(n))
    }

    /// Last 5 training blocks (12 decisions: awayFromPressure, dribbleOrPass, oneTouchPassing) for consistency/score.
    func last5TrainingBlocks(playerId: UUID?) -> [SessionRecord] {
        let training: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        let filtered = sessions.filter {
            training.contains($0.activity) &&
            $0.decisionsCompleted == 12 &&
            (playerId == nil ? $0.playerId == nil : $0.playerId == playerId)
        }
        return Array(filtered.prefix(5))
    }

    /// Number of completed curriculum training blocks (AFP + DOP + OTP, 12 decisions each) for this player. Used for "Block X of Y".
    func curriculumBlocksCompleted(playerId: UUID?) -> Int {
        let training: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        return sessions.filter {
            training.contains($0.activity) &&
            $0.decisionsCompleted == 12 &&
            (playerId == nil ? $0.playerId == nil : $0.playerId == playerId)
        }.count
    }

    // MARK: - Curriculum readiness (unlock next activity)

    /// Unlocked = user can open and train this activity. When AppConfig.testerMode is true, all activities are unlocked.
    /// Otherwise curriculum order: 2-Minute Test → AFP (after test) → DOP (after AFP ready) → OTP (after DOP ready).
    func isUnlocked(activity: ActivityKind, playerId: UUID?) -> Bool {
        if AppConfig.testerMode {
            return true
        }
        switch activity {
        case .twoMinuteTest:
            return true
        case .awayFromPressure:
            return last(.twoMinuteTest, playerId: playerId) != nil
        case .dribbleOrPass:
            return isReady(activity: .awayFromPressure, playerId: playerId)
        case .oneTouchPassing:
            return isReady(activity: .dribbleOrPass, playerId: playerId)
        }
    }

    /// Ready = (2 Strong OR 3 Solid) AND speed Medium/Fast on qualifying blocks AND consistency not Streaky.
    func isReady(activity: ActivityKind, playerId: UUID?) -> Bool {
        let list = lastN(activity, n: 3, playerId: playerId)
        guard list.count >= 2 else { return false }
        let first2 = Array(list.prefix(2))
        let first3 = Array(list.prefix(3))
        let speedOk: (SessionRecord) -> Bool = { $0.speedBucket == .fast || $0.speedBucket == .medium }
        var accuracyAndTimingOk = false
        if first2.count == 2 && first2.allSatisfy({ $0.correct >= 10 && speedOk($0) }) {
            accuracyAndTimingOk = true
        }
        if !accuracyAndTimingOk, first3.count == 3, first3.allSatisfy({ $0.correct >= 9 && speedOk($0) }) {
            accuracyAndTimingOk = true
        }
        guard accuracyAndTimingOk else { return false }
        let last5 = lastN(activity, n: 5, playerId: playerId)
        let consistency = DashboardConsistency.label(from: Array(last5))
        return consistency != .streaky
    }

    /// Almost there: accuracy & timing met but consistency is Streaky (don't unlock next).
    func isAlmostThere(activity: ActivityKind, playerId: UUID?) -> Bool {
        let list = lastN(activity, n: 3, playerId: playerId)
        guard list.count >= 2 else { return false }
        let first2 = Array(list.prefix(2))
        let first3 = Array(list.prefix(3))
        let speedOk: (SessionRecord) -> Bool = { $0.speedBucket == .fast || $0.speedBucket == .medium }
        var accuracyAndTimingOk = false
        if first2.count == 2 && first2.allSatisfy({ $0.correct >= 10 && speedOk($0) }) {
            accuracyAndTimingOk = true
        }
        if !accuracyAndTimingOk, first3.count == 3, first3.allSatisfy({ $0.correct >= 9 && speedOk($0) }) {
            accuracyAndTimingOk = true
        }
        guard accuracyAndTimingOk else { return false }
        let last5 = lastN(activity, n: 5, playerId: playerId)
        let consistency = DashboardConsistency.label(from: Array(last5))
        return consistency == .streaky
    }

    /// Last block summary string for curriculum: e.g. "Solid • Medium"
    func lastBlockSummary(activity: ActivityKind, playerId: UUID?) -> String? {
        guard let last = self.last(activity, playerId: playerId) else { return nil }
        let label: String
        if last.correct >= 10 { label = "Strong" }
        else if last.correct >= 9 { label = "Solid" }
        else { label = "Needs work" }
        let speed = last.speedBucket?.rawValue.capitalized ?? "—"
        return "\(label) • \(speed)"
    }

    /// Clears all locally persisted session records (account sign-out). Does not delete remote Supabase rows.
    func clearAllSessionsForSignOut() {
        sessions = []
        persist()
        recalculateProgress()
    }
}
