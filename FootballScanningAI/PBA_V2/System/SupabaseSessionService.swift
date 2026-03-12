//
//  SupabaseSessionService.swift
//  FootballScanningAI
//
//  Saves each completed training block as one row in Supabase `sessions`, then stores decisions linked to session_id.
//  Uses the Supabase Swift client when configured (Project URL + anon key); otherwise sync is skipped.
//

import Foundation
import Supabase

/// Payload for inserting into the `sessions` table. Only these fields are written: player_id, created_at, block_size. No activity_name or activity_id.
private struct SessionsInsertPayload: Encodable {
    let player_id: String?
    let created_at: String
    let block_size: Int
}

/// Payload for one row in the `decisions` table.
struct SupabaseDecisionRow: Encodable {
    let session_id: String
    let rep_index: Int
    let correct: Bool
    let decision_time_seconds: Double?
    let chosen_direction: String
}

/// Payload for one row in the `session_summary` table. When a drill finishes we compute summary stats and insert with:
/// session_id, player_id, activity_id, decisions_total, correct_total, accuracy, avg_reaction_ms, fast_count, medium_count, slow_count, decision_speed_score, created_at.
struct SessionSummaryRow: Encodable {
    let session_id: String
    let player_id: String?
    let activity_id: String
    let decisions_total: Int
    let correct_total: Int
    /// Correct proportion 0.0–1.0 (correct_total / decisions_total). Nil when no decisions.
    let accuracy: Double?
    /// Average reaction time in milliseconds (DB column: avg_reaction_ms).
    let avg_reaction_ms: Double?
    let fast_count: Int
    let medium_count: Int
    let slow_count: Int
    /// Decision speed score (0–100) for dashboard; optional so older rows without the column still work.
    let decision_speed_score: Int?
    let created_at: String

    /// Build summary from session record and decision list. Computes correct_total, avg_reaction_ms, and fast/medium/slow from decisions.
    static func from(record: SessionRecord, decisions: [TrainingDecisionRecord], sessionIdOverride: UUID? = nil) -> SessionSummaryRow {
        let sessionId = sessionIdOverride ?? record.id
        let activity = record.activity
        let total = decisions.count
        let correctTotal = decisions.filter(\.correct).count
        let accuracy = total > 0 ? Double(correctTotal) / Double(total) : nil
        var sumMs: Double = 0
        var timeCount = 0
        var fast = 0, medium = 0, slow = 0
        for d in decisions {
            if let t = d.decisionTimeSeconds {
                sumMs += t * 1000
                timeCount += 1
                switch TimingThresholds.speedBucket(for: t, activity: activity) {
                case .fast: fast += 1
                case .medium: medium += 1
                case .slow: slow += 1
                }
            }
        }
        let avgMs = timeCount > 0 ? sumMs / Double(timeCount) : nil
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return SessionSummaryRow(
            session_id: sessionId.uuidString.lowercased(),
            player_id: record.playerId.map { $0.uuidString.lowercased() },
            activity_id: record.activity.sessionActivityActivityId,
            decisions_total: total,
            correct_total: correctTotal,
            accuracy: accuracy,
            avg_reaction_ms: avgMs,
            fast_count: fast,
            medium_count: medium,
            slow_count: slow,
            decision_speed_score: record.decisionSpeedScore,
            created_at: iso.string(from: record.date)
        )
    }

    /// Build summary from record only (e.g. retry when decisions not in memory). Uses record.decisionsCompleted, .correct, .avgLatency; fast/medium/slow = 0.
    static func from(record: SessionRecord, sessionIdOverride: UUID? = nil) -> SessionSummaryRow {
        let sessionId = sessionIdOverride ?? record.id
        let total = record.decisionsCompleted
        let correctTotal = record.correct
        let accuracy = total > 0 ? Double(correctTotal) / Double(total) : nil
        let avgMs = record.avgLatency.map { $0 * 1000 }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return SessionSummaryRow(
            session_id: sessionId.uuidString.lowercased(),
            player_id: record.playerId.map { $0.uuidString.lowercased() },
            activity_id: record.activity.sessionActivityActivityId,
            decisions_total: total,
            correct_total: correctTotal,
            accuracy: accuracy,
            avg_reaction_ms: avgMs,
            fast_count: 0,
            medium_count: 0,
            slow_count: 0,
            decision_speed_score: record.decisionSpeedScore,
            created_at: iso.string(from: record.date)
        )
    }
}

final class SupabaseSessionService {
    static let shared = SupabaseSessionService()

    init() {}

    /// Creates a session row in Supabase when a training activity starts. Inserts only player_id, block_size, created_at; DB generates id.
    /// 1. Call this first. 2. Wait for the returned session id. 3. Store it in CurrentSessionStore. 4. Only after that allow decisions to be saved (SupabaseDecisionService will reject inserts until session_id exists).
    /// If this returns nil (e.g. network/RLS failure), do not allow decisions to save.
    func createSessionForDrill(activity: ActivityKind, blockSize: Int, playerId: UUID?) async -> UUID? {
        guard ConnectionManager.shared.isHost else { return nil }
        let client = SupabaseClientManager.client
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload = SessionsInsertPayload(
            player_id: playerId?.uuidString.lowercased(),
            created_at: iso.string(from: Date()),
            block_size: blockSize
        )
        struct InsertedSessionRow: Decodable {
            let id: String
        }
        do {
            let rows: [InsertedSessionRow] = try await client.from("sessions")
                .insert(payload)
                .select()
                .execute()
                .value
            guard let row = rows.first, let id = UUID(uuidString: row.id) else { return nil }
            return id
        } catch {
            print("[Supabase] Failed to create session for drill: \(error)")
            return nil
        }
    }

    // MARK: - session_activities (sessions → session_activities → events / decisions)

    /// When a drill block starts: insert a row into session_activities with session_id (current session), activity_id (current drill), block_number, started_at = now(). Returns the inserted session_activity id (e.g. for CurrentSessionStore).
    func logSessionActivity(sessionId: UUID, activityId: String, blockNumber: Int) async -> UUID? {
        guard ConnectionManager.shared.isHost else { return nil }
        let client = SupabaseClientManager.client
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        struct InsertPayload: Encodable {
            let session_id: String
            let activity_id: String
            let block_number: Int
            let started_at: String
        }
        let payload = InsertPayload(
            session_id: sessionId.uuidString.lowercased(),
            activity_id: activityId,
            block_number: blockNumber,
            started_at: iso.string(from: Date())  // started_at = now()
        )
        struct InsertedRow: Decodable {
            let id: String
        }
        do {
            let rows: [InsertedRow] = try await client.from("session_activities")
                .insert(payload)
                .select()
                .execute()
                .value
            guard let row = rows.first, let id = UUID(uuidString: row.id) else { return nil }
            return id
        } catch {
            print("[Supabase] Failed to insert session_activity: \(error)")
            return nil
        }
    }

    /// Creates a row in session_activities when a drill starts. Calls logSessionActivity; use either name. Returns the inserted session_activity id. Caller should set CurrentSessionStore.currentSessionActivityId.
    func createSessionActivity(sessionId: UUID, activityId: String, blockNumber: Int) async -> UUID? {
        await logSessionActivity(sessionId: sessionId, activityId: activityId, blockNumber: blockNumber)
    }

    /// Sets ended_at = now() on the session_activity row. Call when the drill finishes.
    func endSessionActivity(sessionActivityId: UUID) async {
        guard ConnectionManager.shared.isHost else { return }
        let client = SupabaseClientManager.client
        struct Patch: Encodable { let ended_at: String }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let patch = Patch(ended_at: iso.string(from: Date()))
        do {
            try await client.from("session_activities")
                .update(patch)
                .eq("id", value: sessionActivityId.uuidString.lowercased())
                .execute()
        } catch {
            print("[Supabase] Failed to end session_activity \(sessionActivityId): \(error)")
        }
    }

    /// Updates an existing session row (created at start with pairing code) with final metrics. Call when block completes.
    func updateSession(record: SessionRecord) async {
        guard ConnectionManager.shared.isHost else { return }
        let client = SupabaseClientManager.client
        struct Patch: Encodable {
            let decisions_completed: Int
            let decision_speed_score: Int?
        }
        let patch = Patch(
            decisions_completed: record.decisionsCompleted,
            decision_speed_score: record.decisionSpeedScore
        )
        do {
            try await client.from("sessions")
                .update(patch)
                .eq("id", value: record.id.uuidString.lowercased())
                .execute()
        } catch {
            print("[Supabase] Failed to update session \(record.id): \(error)")
        }
    }


    /// Insert one session row (only player_id, block_size, created_at). If this record.id was created at start (CurrentSessionStore), updates the row instead of inserting.
    func saveSession(record: SessionRecord, decisions: [TrainingDecisionRecord], onSynced: (() -> Void)? = nil) {
        guard ConnectionManager.shared.isHost else { return }
        let client = SupabaseClientManager.client
        let sessionId = record.id.uuidString.lowercased()

        Task {
            do {
                var sessionIdForSummary: UUID? = nil
                if CurrentSessionStore.shared.sessionId == record.id {
                    if let activityId = CurrentSessionStore.shared.currentSessionActivityId {
                        await endSessionActivity(sessionActivityId: activityId)
                    }
                    await updateSession(record: record)
                    await MainActor.run { CurrentSessionStore.shared.clear() }
                    sessionIdForSummary = record.id
                } else {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let payload = SessionsInsertPayload(
                        player_id: record.playerId?.uuidString.lowercased(),
                        created_at: iso.string(from: record.date),
                        block_size: record.reps
                    )
                    struct InsertedRow: Decodable { let id: String }
                    let rows: [InsertedRow] = try await client.from("sessions")
                        .insert(payload)
                        .select()
                        .execute()
                        .value
                    if let row = rows.first, let id = UUID(uuidString: row.id) {
                        sessionIdForSummary = id
                    }
                }
                if let sid = sessionIdForSummary {
                    await writeSessionSummary(record: record, decisions: decisions, sessionIdOverride: sid)
                }
                if let onSynced = onSynced {
                    await MainActor.run { onSynced() }
                }
            } catch {
                let msg = "\(error)"
                print("[Supabase] Failed to save session \(sessionId): \(error)")
                if msg.contains("42501") || msg.contains("row-level security") {
                    print("[Supabase] RLS policy is blocking the insert. Run SupabaseRLSPolicies.sql in the Supabase SQL Editor to allow inserts.")
                }
            }
        }
    }

    /// When a drill finishes: compute summary stats and insert one row into session_summary.
    /// Use sessionIdOverride when the session was inserted with a DB-generated id (e.g. retry path).
    func writeSessionSummary(record: SessionRecord, decisions: [TrainingDecisionRecord], sessionIdOverride: UUID? = nil) async {
        guard ConnectionManager.shared.isHost else { return }
        let sessionId = sessionIdOverride ?? record.id
        let row = decisions.isEmpty
            ? SessionSummaryRow.from(record: record, sessionIdOverride: sessionId)
            : SessionSummaryRow.from(record: record, decisions: decisions, sessionIdOverride: sessionId)
        await insertSessionSummary(row: row)
    }

    /// Inserts one row into session_summary. Used by writeSessionSummary.
    private func insertSessionSummary(row: SessionSummaryRow) async {
        guard ConnectionManager.shared.isHost else { return }
        let client = SupabaseClientManager.client
        do {
            try await client.from("session_summary").insert(row).execute()
        } catch {
            print("[Supabase] Failed to insert session_summary for session \(row.session_id): \(error)")
        }
    }

    /// Fetches Decision Speed Scores from the sessions table for percentile.
    /// Returns nil when not host or the request fails (e.g. column missing).
    func fetchDecisionSpeedScores(activityName: String) async -> [Int]? {
        guard ConnectionManager.shared.isHost else { return nil }
        let client = SupabaseClientManager.client
        struct Row: Decodable { let decision_speed_score: Int? }
        do {
            let rows: [Row] = try await client.from("sessions").select("decision_speed_score").execute().value
            return rows.compactMap(\.decision_speed_score)
        } catch {
            print("[Supabase] Failed to fetch decision speed scores: \(error)")
            return nil
        }
    }

    /// Percentile (0–100): (number of session scores below current / total session scores including current) * 100.
    /// Uses previous session scores from DB; current score is included in total. Returns nil when no data.
    func decisionSpeedPercentile(activityName: String, currentScore: Int) async -> Int? {
        guard let previousScores = await fetchDecisionSpeedScores(activityName: activityName) else { return nil }
        let total = previousScores.count + 1
        guard total > 0 else { return nil }
        let scoresBelow = previousScores.filter { $0 < currentScore }.count
        return Int(round(Double(scoresBelow) / Double(total) * 100))
    }

    /// Upload all sessions that are stored locally with synced = false. Call on app launch or when connectivity returns.
    /// Session insert uses only player_id, created_at, block_size. No-op on coach remote.
    func retryPendingSessions(progressStore: ProgressStore) {
        guard ConnectionManager.shared.isHost else { return }
        let unsynced = progressStore.unsyncedSessions
        guard !unsynced.isEmpty else { return }
        for record in unsynced {
            saveSession(record: record, decisions: []) { [weak progressStore] in
                progressStore?.markSynced(id: record.id)
            }
        }
    }
}
