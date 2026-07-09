//
//  SupabaseSessionService.swift
//  FootballScanningAI
//
//  Saves each completed training block as one row in Supabase `sessions`, then stores decisions linked to session_id.
//  Uses the Supabase Swift client when configured (Project URL + anon key); otherwise sync is skipped.
//

import Foundation
import Supabase
#if os(iOS)
import UIKit
#endif

/// Relay-only partner display (iPad) writes session rows; coach iPhone does not.
enum SupabaseSessionWriteGate {
    static var mayWriteSessionData: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad || ConnectionManager.shared.isHost
        #else
        return ConnectionManager.shared.isHost
        #endif
    }
}

/// Payload for inserting into the `sessions` table.
private struct SessionsInsertPayload: Encodable {
    let player_id: String?
    let created_at: String
    let block_size: Int
    let started_at: String
    let mode: String?
}

/// Pre-migration `sessions` insert (before `started_at` / `mode` columns exist).
private struct SessionsLegacyInsertPayload: Encodable {
    let player_id: String?
    let created_at: String
    let block_size: Int
}

private func isPostgrestMissingColumnError(_ error: Error) -> Bool {
    let message = String(describing: error)
    return message.contains("PGRST204")
        || (message.contains("Could not find") && message.contains("column"))
}

private func insertSessionRow(
    client: SupabaseClient,
    playerId: String?,
    createdAt: String,
    blockSize: Int,
    startedAt: String,
    mode: String?
) async throws -> UUID? {
    struct InsertedSessionRow: Decodable { let id: String }
    let fullPayload = SessionsInsertPayload(
        player_id: playerId,
        created_at: createdAt,
        block_size: blockSize,
        started_at: startedAt,
        mode: mode
    )
    do {
        let rows: [InsertedSessionRow] = try await client.from("sessions")
            .insert(fullPayload)
            .select()
            .execute()
            .value
        guard let row = rows.first, let id = UUID(uuidString: row.id) else { return nil }
        return id
    } catch {
        guard isPostgrestMissingColumnError(error) else { throw error }
        print("[Supabase] session insert using legacy columns — run SupabaseSessionDurationMigration.sql for mode/started_at")
        let legacyPayload = SessionsLegacyInsertPayload(
            player_id: playerId,
            created_at: createdAt,
            block_size: blockSize
        )
        let rows: [InsertedSessionRow] = try await client.from("sessions")
            .insert(legacyPayload)
            .select()
            .execute()
            .value
        guard let row = rows.first, let id = UUID(uuidString: row.id) else { return nil }
        return id
    }
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
    private static let hasCompletedFirstSessionKey = "has_completed_first_session"

    let session_id: String
    let player_id: String
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
    let duration_seconds: Int
    let rep_count: Int
    let completion_type: String
    let mode: String
    let device_type: String
    let is_first_session: Bool
    let first_session: Bool?
    /// Decision speed score (0–100) for dashboard; optional so older rows without the column still work.
    let decision_speed_score: Int?
    let created_at: String

    /// Build summary from session record and decision list. Computes correct_total, avg_reaction_ms, and fast/medium/slow from decisions.
    static func from(record: SessionRecord, decisions: [TrainingDecisionRecord], sessionIdOverride: UUID? = nil, sessionMode: SessionAnalyticsMode? = nil, durationOverride: Int? = nil) -> SessionSummaryRow {
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
                let window = DecisionTimingModel.decisionWindow(rawRepInterval: t, activity: activity, difficulty: record.difficulty)
                sumMs += window * 1000
                timeCount += 1
            }
        }
        let adaptiveScore: Int = {
            guard let accuracy else { return 70 }
            let windows = decisions.compactMap { d -> Double? in
                guard let t = d.decisionTimeSeconds else { return nil }
                return DecisionTimingModel.decisionWindow(rawRepInterval: t, activity: activity, difficulty: record.difficulty)
            }
            return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: windows, activity: activity)
        }()
        fast = 0
        medium = 0
        slow = 0
        for d in decisions {
            if let t = d.decisionTimeSeconds {
                let window = DecisionTimingModel.decisionWindow(rawRepInterval: t, activity: activity, difficulty: record.difficulty)
                switch DecisionTimingModel.speedBucket(forDecisionWindow: window, activity: activity, score: adaptiveScore) {
                case .fast: fast += 1
                case .medium: medium += 1
                case .slow: slow += 1
                }
            }
        }
        let avgMs = timeCount > 0 ? sumMs / Double(timeCount) : nil
        let analytics = CurrentSessionStore.shared
        let durationSeconds: Int = {
            if let durationOverride { return max(0, durationOverride) }
            guard let startedAt = analytics.analyticsSessionStartedAt ?? analytics.supabaseSessionStartedAt else { return 0 }
            return max(0, Int(record.date.timeIntervalSince(startedAt)))
        }()
        let repCount = max(record.decisionsCompleted, record.reps, total)
        let completion = (analytics.analyticsCompletionType ?? .completed).rawValue
        let mode = (sessionMode ?? analytics.analyticsMode ?? .solo).rawValue
        let playerId = resolvedSummaryPlayerId(record: record)
        let deviceType = currentDeviceType()
        let hasCompletedFirst = UserDefaults.standard.bool(forKey: hasCompletedFirstSessionKey)
        let isFirstSession = !hasCompletedFirst
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return SessionSummaryRow(
            session_id: sessionId.uuidString.lowercased(),
            player_id: playerId,
            activity_id: record.activity.sessionActivityActivityId,
            decisions_total: total,
            correct_total: correctTotal,
            accuracy: accuracy,
            avg_reaction_ms: avgMs,
            fast_count: fast,
            medium_count: medium,
            slow_count: slow,
            duration_seconds: durationSeconds,
            rep_count: repCount,
            completion_type: completion,
            mode: mode,
            device_type: deviceType,
            is_first_session: isFirstSession,
            first_session: isFirstSession ? true : nil,
            decision_speed_score: record.decisionSpeedScore,
            created_at: iso.string(from: record.date)
        )
    }

    /// Build summary from record only (e.g. retry when decisions not in memory). Uses record.decisionsCompleted, .correct, .avgLatency; fast/medium/slow = 0.
    static func from(record: SessionRecord, sessionIdOverride: UUID? = nil, sessionMode: SessionAnalyticsMode? = nil, durationOverride: Int? = nil) -> SessionSummaryRow {
        let sessionId = sessionIdOverride ?? record.id
        let total = record.decisionsCompleted
        let correctTotal = record.correct
        let accuracy = total > 0 ? Double(correctTotal) / Double(total) : nil
        let avgMs = record.avgLatency.map { $0 * 1000 }
        let analytics = CurrentSessionStore.shared
        let durationSeconds: Int = {
            if let durationOverride { return max(0, durationOverride) }
            guard let startedAt = analytics.analyticsSessionStartedAt ?? analytics.supabaseSessionStartedAt else { return 0 }
            return max(0, Int(record.date.timeIntervalSince(startedAt)))
        }()
        let repCount = max(record.decisionsCompleted, record.reps)
        let completion = (analytics.analyticsCompletionType ?? .completed).rawValue
        let mode = (sessionMode ?? analytics.analyticsMode ?? .solo).rawValue
        let playerId = resolvedSummaryPlayerId(record: record)
        let deviceType = currentDeviceType()
        let hasCompletedFirst = UserDefaults.standard.bool(forKey: hasCompletedFirstSessionKey)
        let isFirstSession = !hasCompletedFirst
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return SessionSummaryRow(
            session_id: sessionId.uuidString.lowercased(),
            player_id: playerId,
            activity_id: record.activity.sessionActivityActivityId,
            decisions_total: total,
            correct_total: correctTotal,
            accuracy: accuracy,
            avg_reaction_ms: avgMs,
            fast_count: 0,
            medium_count: 0,
            slow_count: 0,
            duration_seconds: durationSeconds,
            rep_count: repCount,
            completion_type: completion,
            mode: mode,
            device_type: deviceType,
            is_first_session: isFirstSession,
            first_session: isFirstSession ? true : nil,
            decision_speed_score: record.decisionSpeedScore,
            created_at: iso.string(from: record.date)
        )
    }

    private static func currentDeviceType() -> String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
        return "unknown"
        #endif
    }

    private static func resolvedSummaryPlayerId(record: SessionRecord) -> String {
        if let authId = AuthManager.shared.currentUserId?.uuidString.lowercased() {
            return authId
        }
        if let recordId = record.playerId?.uuidString.lowercased() {
            return recordId
        }
        return LocalUserIdentityStore.ensureLocalUserId()
    }
}

final class SupabaseSessionService {
    static let shared = SupabaseSessionService()

    init() {}

    /// Creates a session row in Supabase when a training activity starts.
    func createSessionForDrill(
        activity: ActivityKind,
        blockSize: Int,
        playerId: UUID?,
        mode: SessionAnalyticsMode? = nil,
        startedAt: Date = Date()
    ) async -> UUID? {
        guard SupabaseSessionWriteGate.mayWriteSessionData else {
            print("[Supabase] createSessionForDrill skipped — write gate denied")
            return nil
        }
        let client = SupabaseClientManager.client
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = iso.string(from: startedAt)
        do {
            guard let id = try await insertSessionRow(
                client: client,
                playerId: resolvedPlayerId(record: nil, explicitPlayerId: playerId),
                createdAt: createdAt,
                blockSize: blockSize,
                startedAt: createdAt,
                mode: mode?.rawValue
            ) else { return nil }
            print("[Supabase] createSessionForDrill ok id=\(id.uuidString.lowercased()) mode=\(mode?.rawValue ?? "nil") blockSize=\(blockSize)")
            return id
        } catch {
            print("[Supabase] createSessionForDrill failed activity=\(activity.sessionActivityActivityId) error=\(error)")
            return nil
        }
    }

    // MARK: - session_activities (sessions → session_activities → events / decisions)

    /// When a drill block starts: insert a row into session_activities with session_id (current session), activity_id (current drill), block_number, started_at = now(). Returns the inserted session_activity id (e.g. for CurrentSessionStore).
    func logSessionActivity(sessionId: UUID, activityId: String, blockNumber: Int) async -> UUID? {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return nil }
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

    /// Opens a drill block: session_activities (decision FK) + session_activity_segments (analytics).
    func openSessionActivityBlock(sessionId: UUID, activityId: String, blockNumber: Int) async -> (sessionActivityId: UUID?, segmentId: UUID?) {
        async let sessionActivityId = createSessionActivity(
            sessionId: sessionId,
            activityId: activityId,
            blockNumber: blockNumber
        )
        async let segmentId = createSessionActivitySegment(
            sessionId: sessionId,
            activityId: activityId
        )
        return (await sessionActivityId, await segmentId)
    }

    /// Sets ended_at = now() on the session_activity row. Call when the drill finishes.
    func endSessionActivity(sessionActivityId: UUID) async {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
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

    // MARK: - session_activity_segments (multi-activity sessions)

    /// Opens an activity stint within an existing session. Call when an activity starts or after switching activities.
    func createSessionActivitySegment(sessionId: UUID, activityId: String) async -> UUID? {
        let sessionIdString = sessionId.uuidString.lowercased()
        guard SupabaseSessionWriteGate.mayWriteSessionData else {
            print("[SEGMENT SKIP] write gate denied activity=\(activityId) session=\(sessionIdString)")
            return nil
        }
        print("[SEGMENT INSERT] activity=\(activityId) session=\(sessionIdString)")
        let client = SupabaseClientManager.client
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        struct InsertPayload: Encodable {
            let session_id: String
            let activity_id: String
            let started_at: String
            let rep_count: Int
        }
        let payload = InsertPayload(
            session_id: sessionIdString,
            activity_id: activityId,
            started_at: iso.string(from: Date()),
            rep_count: 0
        )
        struct InsertedRow: Decodable { let id: String }
        do {
            let rows: [InsertedRow] = try await client.from("session_activity_segments")
                .insert(payload)
                .select()
                .execute()
                .value
            guard let row = rows.first, let id = UUID(uuidString: row.id) else { return nil }
            print("[SEGMENT INSERT] ok id=\(id.uuidString.lowercased()) activity=\(activityId)")
            return id
        } catch {
            print("[SEGMENT ERROR] \(error)")
            let msg = "\(error)"
            if msg.contains("42501") || msg.localizedCaseInsensitiveContains("row-level security") {
                print("[SEGMENT ERROR] RLS blocked insert — run SupabaseSessionActivitySegmentsMigration.sql or segment policies in SupabaseRLSPolicies.sql")
            }
            return nil
        }
    }

    /// Closes an activity stint with final rep count for that segment.
    func endSessionActivitySegment(segmentId: UUID, activityId: String, repCount: Int) async {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let client = SupabaseClientManager.client
        struct Patch: Encodable {
            let ended_at: String
            let rep_count: Int
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let patch = Patch(
            ended_at: iso.string(from: Date()),
            rep_count: max(0, repCount)
        )
        do {
            try await client.from("session_activity_segments")
                .update(patch)
                .eq("id", value: segmentId.uuidString.lowercased())
                .execute()
            print("[SEGMENT CLOSE] activity=\(activityId) segment=\(segmentId.uuidString.lowercased()) reps=\(max(0, repCount))")
        } catch {
            print("[Supabase] Failed to end session_activity_segment \(segmentId): \(error)")
        }
    }

    /// Increment open segment rep_count after each accepted PASS (best-effort; final count set on segment close).
    func syncSessionActivitySegmentRepCount(segmentId: UUID, repCount: Int) {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let client = SupabaseClientManager.client
        struct Patch: Encodable { let rep_count: Int }
        let count = max(0, repCount)
        Task {
            do {
                try await client.from("session_activity_segments")
                    .update(Patch(rep_count: count))
                    .eq("id", value: segmentId.uuidString.lowercased())
                    .execute()
            } catch {
                #if DEBUG
                print("[Supabase] segment rep sync failed segmentId=\(segmentId) reps=\(count): \(error)")
                #endif
            }
        }
    }

    /// Aggregated rep totals per activity_id for a session (sums all segment stints).
    func fetchAggregatedSegmentRepCounts(sessionId: UUID) async -> [String: Int]? {
        struct Row: Decodable {
            let activity_id: String
            let rep_count: Int
        }
        let sessionIdString = sessionId.uuidString.lowercased()
        let client = SupabaseClientManager.client
        do {
            let rows: [Row] = try await client.from("session_activity_segments")
                .select("activity_id, rep_count")
                .eq("session_id", value: sessionIdString)
                .execute()
                .value
            var aggregated: [String: Int] = [:]
            for row in rows where row.rep_count > 0 {
                aggregated[row.activity_id, default: 0] += row.rep_count
            }
            #if DEBUG
            print("[SEGMENT FETCH] session=\(sessionIdString) breakdown=\(aggregated)")
            #endif
            return aggregated
        } catch {
            print("[SEGMENT FETCH] failed session=\(sessionIdString): \(error)")
            return nil
        }
    }

    /// Finalize session row: ended_at, duration_seconds, rep totals, mode.
    func finalizeSession(
        record: SessionRecord,
        endedAt: Date,
        durationSeconds: Int,
        mode: SessionAnalyticsMode?
    ) async {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let client = SupabaseClientManager.client
        struct Patch: Encodable {
            let decisions_completed: Int
            let decision_speed_score: Int?
            let ended_at: String
            let duration_seconds: Int
            let mode: String?
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let patch = Patch(
            decisions_completed: record.decisionsCompleted,
            decision_speed_score: record.decisionSpeedScore,
            ended_at: iso.string(from: endedAt),
            duration_seconds: max(0, durationSeconds),
            mode: mode?.rawValue
        )
        do {
            try await client.from("sessions")
                .update(patch)
                .eq("id", value: record.id.uuidString.lowercased())
                .execute()
        } catch {
            if isPostgrestMissingColumnError(error) {
                print("[Supabase] finalizeSession using legacy columns — run SupabaseSessionDurationMigration.sql")
                await updateSession(record: record)
            } else {
                print("[Supabase] Failed to finalize session \(record.id): \(error)")
            }
        }
    }

    /// Updates an existing session row (legacy path).
    func updateSession(record: SessionRecord) async {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
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
    func saveSession(
        record: SessionRecord,
        decisions: [TrainingDecisionRecord],
        sessionMode: SessionAnalyticsMode? = nil,
        durationSeconds: Int? = nil,
        endedAt: Date? = nil,
        onSynced: (() -> Void)? = nil
    ) {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let client = SupabaseClientManager.client
        let sessionId = record.id.uuidString.lowercased()

        Task {
            do {
                var sessionIdForSummary: UUID? = nil
                let modeForSummary = sessionMode ?? CurrentSessionStore.shared.analyticsMode
                let sessionEndedAt = endedAt ?? record.date
                let sessionDurationSeconds: Int = {
                    if let durationSeconds { return max(0, durationSeconds) }
                    if let started = CurrentSessionStore.shared.supabaseSessionStartedAt
                        ?? CurrentSessionStore.shared.analyticsSessionStartedAt {
                        return max(0, Int(sessionEndedAt.timeIntervalSince(started)))
                    }
                    return 0
                }()
                if CurrentSessionStore.shared.sessionId == record.id {
                    if let segmentId = CurrentSessionStore.shared.currentSessionActivitySegmentId {
                        let segmentReps = max(
                            CurrentSessionStore.shared.currentSegmentRepCount,
                            record.reps
                        )
                        let segmentActivityId = CurrentSessionStore.shared.currentSegmentActivityId ?? "unknown"
                        await endSessionActivitySegment(
                            segmentId: segmentId,
                            activityId: segmentActivityId,
                            repCount: segmentReps
                        )
                        await MainActor.run {
                            CurrentSessionStore.shared.clearCurrentSessionActivitySegment()
                        }
                    }
                    if let activityId = CurrentSessionStore.shared.currentSessionActivityId {
                        await endSessionActivity(sessionActivityId: activityId)
                    }
                    await finalizeSession(
                        record: record,
                        endedAt: sessionEndedAt,
                        durationSeconds: sessionDurationSeconds,
                        mode: modeForSummary
                    )
                    await MainActor.run { CurrentSessionStore.shared.clear() }
                    sessionIdForSummary = record.id
                } else {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let createdAt = iso.string(from: record.date)
                    sessionIdForSummary = try await insertSessionRow(
                        client: client,
                        playerId: resolvedPlayerId(record: record, explicitPlayerId: nil),
                        createdAt: createdAt,
                        blockSize: record.reps,
                        startedAt: createdAt,
                        mode: modeForSummary?.rawValue
                    )
                }
                if let sid = sessionIdForSummary {
                    await writeSessionSummary(
                        record: record,
                        decisions: decisions,
                        sessionIdOverride: sid,
                        sessionMode: modeForSummary,
                        durationSeconds: sessionDurationSeconds
                    )
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
    func writeSessionSummary(
        record: SessionRecord,
        decisions: [TrainingDecisionRecord],
        sessionIdOverride: UUID? = nil,
        sessionMode: SessionAnalyticsMode? = nil,
        durationSeconds: Int? = nil
    ) async {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let sessionId = sessionIdOverride ?? record.id
        let row = decisions.isEmpty
            ? SessionSummaryRow.from(record: record, sessionIdOverride: sessionId, sessionMode: sessionMode, durationOverride: durationSeconds)
            : SessionSummaryRow.from(record: record, decisions: decisions, sessionIdOverride: sessionId, sessionMode: sessionMode, durationOverride: durationSeconds)
        await insertSessionSummary(row: row)
    }

    /// Inserts one row into session_summary. Used by writeSessionSummary.
    private func insertSessionSummary(row: SessionSummaryRow) async {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let client = SupabaseClientManager.client
        do {
            try await client.from("session_summary").insert(row).execute()
            if row.is_first_session {
                UserDefaults.standard.set(true, forKey: "has_completed_first_session")
            }
            LocalUserIdentityStore.markHasSession(for: row.player_id)
        } catch {
            // Optional column compatibility: retry without `first_session` if the DB has not added it yet.
            if row.first_session != nil, shouldRetryWithoutFirstSession(error) {
                await insertSessionSummaryWithoutFirstSession(row: row)
                return
            }
            print("[Supabase] Failed to insert session_summary for session \(row.session_id): \(error)")
        }
    }

    private func shouldRetryWithoutFirstSession(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        return message.contains("first_session") && (message.contains("column") || message.contains("schema cache"))
    }

    private func insertSessionSummaryWithoutFirstSession(row: SessionSummaryRow) async {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let client = SupabaseClientManager.client
        struct SessionSummaryRowWithoutFirstSession: Encodable {
            let session_id: String
            let player_id: String
            let activity_id: String
            let decisions_total: Int
            let correct_total: Int
            let accuracy: Double?
            let avg_reaction_ms: Double?
            let fast_count: Int
            let medium_count: Int
            let slow_count: Int
            let duration_seconds: Int
            let rep_count: Int
            let completion_type: String
            let mode: String
            let device_type: String
            let is_first_session: Bool
            let decision_speed_score: Int?
            let created_at: String
        }
        let fallback = SessionSummaryRowWithoutFirstSession(
            session_id: row.session_id,
            player_id: row.player_id,
            activity_id: row.activity_id,
            decisions_total: row.decisions_total,
            correct_total: row.correct_total,
            accuracy: row.accuracy,
            avg_reaction_ms: row.avg_reaction_ms,
            fast_count: row.fast_count,
            medium_count: row.medium_count,
            slow_count: row.slow_count,
            duration_seconds: row.duration_seconds,
            rep_count: row.rep_count,
            completion_type: row.completion_type,
            mode: row.mode,
            device_type: row.device_type,
            is_first_session: row.is_first_session,
            decision_speed_score: row.decision_speed_score,
            created_at: row.created_at
        )
        do {
            try await client.from("session_summary").insert(fallback).execute()
            if row.is_first_session {
                UserDefaults.standard.set(true, forKey: "has_completed_first_session")
            }
            LocalUserIdentityStore.markHasSession(for: row.player_id)
        } catch {
            print("[Supabase] Failed to insert session_summary fallback for session \(row.session_id): \(error)")
        }
    }

    /// Fetches Decision Speed Scores from the sessions table (e.g. optional internal analytics).
    /// Returns nil when not host or the request fails (e.g. column missing).
    func fetchDecisionSpeedScores(activityName: String) async -> [Int]? {
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return nil }
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
        guard SupabaseSessionWriteGate.mayWriteSessionData else { return }
        let unsynced = progressStore.unsyncedSessions
        guard !unsynced.isEmpty else { return }
        for record in unsynced {
            saveSession(record: record, decisions: []) { [weak progressStore] in
                progressStore?.markSynced(id: record.id)
            }
        }
    }

    private func resolvedPlayerId(record: SessionRecord?, explicitPlayerId: UUID?) -> String {
        if let authId = AuthManager.shared.currentUserId?.uuidString.lowercased() {
            return authId
        }
        if let explicitPlayerId {
            return explicitPlayerId.uuidString.lowercased()
        }
        if let recordId = record?.playerId?.uuidString.lowercased() {
            return recordId
        }
        return LocalUserIdentityStore.ensureLocalUserId()
    }
}
