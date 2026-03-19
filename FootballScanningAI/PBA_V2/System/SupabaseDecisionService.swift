//
//  SupabaseDecisionService.swift
//  FootballScanningAI
//
//  Saves per-rep Decision rows to Supabase `decisions` table (trigger → confirmation reaction time).
//

import Foundation
import Supabase

/// Decodable row from `decisions` table for fetch.
private struct SupabaseDecisionRowDecodable: Decodable {
    let id: String
    let session_id: String
    let player_id: String?
    let activity_name: String
    let stimulus_type: String
    let decision_direction: String
    let reaction_time_ms: Int
    let correct: Bool
    let created_at: String
}

/// One row in the `decisions` table (reaction-time schema). Do not send activity_name.
struct SupabaseDecisionRowV2: Encodable {
    let id: String
    let session_id: String
    let session_activity_id: String?
    /// Null when not signed in.
    let player_id: String?
    /// Snake-case activity id (e.g. "away_from_pressure", "two_minute_test").
    let activity_id: String
    let decision_direction: String
    let decision_type: String
    let correct: Bool
    let reaction_time_ms: Int
    let created_at: String
}

final class SupabaseDecisionService {
    static let shared = SupabaseDecisionService()

    /// Max reaction time to accept; above this the rep is discarded.
    static let maxReactionTimeMs = 2000

    init() {}

    /// Save one decision after a valid rep. Call from display when coach confirms direction (or ✕).
    /// Only inserts when the session exists in Supabase: requires CurrentSessionStore.sessionId to match decision.sessionId (session must be created first). Skips if not host. Runs async.
    func saveDecision(_ decision: Decision) {
        guard ConnectionManager.shared.isHost else { return }
        guard let currentSessionId = CurrentSessionStore.shared.sessionId else {
            return
        }
        guard currentSessionId == decision.sessionId else {
            return
        }
        if decision.reactionTimeMs > Self.maxReactionTimeMs { return }

        let client = SupabaseClientManager.client
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sessionActivityId = CurrentSessionStore.shared.currentSessionActivityId?.uuidString.lowercased()
        let activityId = ActivityKind(rawValue: decision.activityName)?.sessionActivityActivityId ?? decision.activityName
        let row = SupabaseDecisionRowV2(
            id: decision.id.uuidString.lowercased(),
            session_id: decision.sessionId.uuidString.lowercased(),
            session_activity_id: sessionActivityId,
            player_id: decision.playerId?.uuidString.lowercased(),
            activity_id: activityId,
            decision_direction: decision.decisionDirection,
            decision_type: decision.stimulusType,
            correct: decision.correct,
            reaction_time_ms: decision.reactionTimeMs,
            created_at: iso.string(from: decision.createdAt)
        )

        Task {
            do {
                print("Saving decision")
                try await client.from("decisions").upsert(row, onConflict: "id").execute()
            } catch {
                print("[Supabase] Failed to save decision \(decision.id): \(error)")
                enqueuePending(decision)
            }
        }
    }

    /// Returns true if decisions can be saved (session was created in Supabase and stored in CurrentSessionStore).
    static var canSaveDecisions: Bool {
        CurrentSessionStore.shared.sessionId != nil
    }

    private static let pendingDecisionsKey = "pba_pending_decisions"

    private func enqueuePending(_ decision: Decision) {
        var list = loadPendingDecisions()
        list.append(decision)
        savePendingDecisions(list)
    }

    private func loadPendingDecisions() -> [Decision] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingDecisionsKey) else { return [] }
        return (try? JSONDecoder().decode([Decision].self, from: data)) ?? []
    }

    private func savePendingDecisions(_ list: [Decision]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: Self.pendingDecisionsKey)
    }

    private func removePendingDecision(id: UUID) {
        var list = loadPendingDecisions()
        list.removeAll { $0.id == id }
        savePendingDecisions(list)
    }

    /// Clear the local pending-decisions queue. Use when old decisions reference sessions from an outdated schema and should not be retried.
    func clearPendingDecisionsQueue() {
        savePendingDecisions([])
    }

    /// Retry uploading queued decisions (e.g. on app launch or when scene becomes active). Call from host only.
    func retryPendingDecisions() {
        guard ConnectionManager.shared.isHost else { return }
        let pending = loadPendingDecisions()
        guard !pending.isEmpty else { return }
        Task {
            for decision in pending {
                let sessionActivityId = CurrentSessionStore.shared.currentSessionActivityId?.uuidString.lowercased()
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let activityId = ActivityKind(rawValue: decision.activityName)?.sessionActivityActivityId ?? decision.activityName
                let row = SupabaseDecisionRowV2(
                    id: decision.id.uuidString.lowercased(),
                    session_id: decision.sessionId.uuidString.lowercased(),
                    session_activity_id: sessionActivityId,
                    player_id: decision.playerId?.uuidString.lowercased(),
                    activity_id: activityId,
                    decision_direction: decision.decisionDirection,
                    decision_type: decision.stimulusType,
                    correct: decision.correct,
                    reaction_time_ms: decision.reactionTimeMs,
                    created_at: iso.string(from: decision.createdAt)
                )
                do {
                    try await SupabaseClientManager.client.from("decisions").upsert(row, onConflict: "id").execute()
                    await MainActor.run { removePendingDecision(id: decision.id) }
                } catch {
                    let errStr = String(describing: error)
                    let isForeignKey = errStr.contains("23503") || errStr.lowercased().contains("foreign key")
                    if isForeignKey {
                        await MainActor.run { removePendingDecision(id: decision.id) }
                        print("[Supabase] Removed decision \(decision.id) from retry queue (session no longer exists).")
                    } else {
                        print("[Supabase] Retry failed for decision \(decision.id): \(error)")
                    }
                }
            }
        }
    }

    /// Fetch decisions for a player (for analytics / recommendation). Returns empty if not host.
    func fetchDecisions(playerId: UUID) async throws -> [Decision] {
        guard ConnectionManager.shared.isHost else { return [] }
        let client = SupabaseClientManager.client
        let playerIdStr = playerId.uuidString.lowercased()
        let rows: [SupabaseDecisionRowDecodable] = try await client.from("decisions")
            .select()
            .eq("player_id", value: playerIdStr)
            .execute()
            .value
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rows.compactMap { row in
            guard let id = UUID(uuidString: row.id),
                  let sessionId = UUID(uuidString: row.session_id),
                  let createdAt = iso.date(from: row.created_at) else { return nil }
            let playerUuid = row.player_id.flatMap { UUID(uuidString: $0) }
            return Decision(
                id: id,
                sessionId: sessionId,
                playerId: playerUuid,
                activityName: row.activity_name,
                stimulusType: row.stimulus_type,
                decisionDirection: row.decision_direction,
                reactionTimeMs: row.reaction_time_ms,
                correct: row.correct,
                createdAt: createdAt
            )
        }
    }

    /// Recommend activity with the slowest average reaction time from decisions. Nil if no data.
    static func recommendActivityFromDecisions(_ decisions: [Decision]) -> ActivityKind? {
        guard !decisions.isEmpty else { return nil }
        let byActivity = Dictionary(grouping: decisions, by: { $0.activityName })
        var slowestActivity: String?
        var slowestAvg: Double = 0
        for (activityName, list) in byActivity {
            let avg = Double(list.map(\.reactionTimeMs).reduce(0, +)) / Double(list.count)
            if avg > slowestAvg {
                slowestAvg = avg
                slowestActivity = activityName
            }
        }
        guard let id = slowestActivity else { return nil }
        return ActivityKind(rawValue: id)
    }
}
