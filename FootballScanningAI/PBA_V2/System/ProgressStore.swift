//
//  ProgressStore.swift
//  FootballScanningAI
//
//  PBA V2 — Persists session records; call load() on app launch.
//

import Foundation
import Combine

final class ProgressStore: ObservableObject {
    @Published private(set) var sessions: [SessionRecord] = []

    private let key = "pba_sessions_v2"

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            sessions = []
            return
        }
        do {
            sessions = try JSONDecoder().decode([SessionRecord].self, from: data)
        } catch {
            sessions = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(sessions)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // Fail silently for MVP
        }
    }

    func add(_ record: SessionRecord) {
        sessions.insert(record, at: 0)
        if record.reps == 12 {
            DailyTargetState.incrementToday(playerId: record.playerId)
        }
        persist()
    }

    func sessions(for activity: ActivityKind) -> [SessionRecord] {
        sessions.filter { $0.activity == activity }
    }

    /// Sessions for an activity and optional player (nil = legacy; include for selected player).
    func sessions(for activity: ActivityKind, playerId: UUID?) -> [SessionRecord] {
        guard let pid = playerId else { return sessions(for: activity) }
        return sessions.filter { $0.activity == activity && ($0.playerId == pid || $0.playerId == nil) }
    }

    func last(_ activity: ActivityKind) -> SessionRecord? {
        sessions.first(where: { $0.activity == activity })
    }

    func last(_ activity: ActivityKind, playerId: UUID?) -> SessionRecord? {
        sessions(for: activity, playerId: playerId).first
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

    /// Last 5 training blocks (12-rep only: awayFromPressure, dribbleOrPass, oneTouchPassing) for consistency/score.
    func last5TrainingBlocks(playerId: UUID?) -> [SessionRecord] {
        let training: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        let filtered = sessions.filter { training.contains($0.activity) && $0.reps == 12 && (playerId == nil || $0.playerId == playerId || $0.playerId == nil) }
        return Array(filtered.prefix(5))
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
}
