//
//  SessionResultSupabaseHydration.swift
//  FootballScanningAI
//
//  After login, rebuilds local UserProfile.sessionResults from Supabase so Home charts
//  are populated for returning users. Does not run XP/badge flows (merge-only).
//

import Foundation
import Supabase

enum SessionResultSupabaseHydration {

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func hydrateSessionResultsAfterLogin(
        profileManager: UserProfileManager,
        playerIds: [UUID],
        context: String
    ) async {
        guard Config.isSupabaseConfigured else { return }
        guard ConnectionManager.shared.isHost else {
            print("[SessionHydration-Debug] skipped: not host context=\(context)")
            return
        }
        guard AuthManager.shared.currentUserId != nil else { return }
        guard !playerIds.isEmpty else {
            print("[SessionHydration-Debug] skipped: no player ids context=\(context)")
            return
        }

        for playerId in playerIds {
            await hydrateSessionResultsFromSupabase(playerId: playerId, profileManager: profileManager, context: context)
        }
    }

    // MARK: - Per player

    private static func hydrateSessionResultsFromSupabase(
        playerId: UUID,
        profileManager: UserProfileManager,
        context: String
    ) async {
        var fromSummary: [SessionResult] = []
        var summarySessionIds = Set<String>()
        var summaryError: Error?

        do {
            (fromSummary, summarySessionIds) = try await fetchFromSessionSummary(playerId: playerId)
        } catch {
            summaryError = error
            print("[SessionHydration-Debug] session_summary fetch failed player_id=\(playerId.uuidString.lowercased()) error=\(error.localizedDescription) context=\(context)")
        }

        var fromFallback: [SessionResult] = []
        if summaryError != nil {
            do {
                fromFallback = try await fetchFromSessionsFallback(playerId: playerId, excludingSessionIds: [])
            } catch {
                print("[SessionHydration-Debug] sessions fallback failed after summary error player_id=\(playerId.uuidString.lowercased()) error=\(error.localizedDescription) context=\(context)")
            }
        } else {
            do {
                fromFallback = try await fetchFromSessionsFallback(playerId: playerId, excludingSessionIds: summarySessionIds)
            } catch {
                print("[SessionHydration-Debug] sessions fallback failed (non-fatal) player_id=\(playerId.uuidString.lowercased()) error=\(error.localizedDescription) context=\(context)")
            }
        }

        let merged = fromSummary + fromFallback
        let fetchedCount = merged.count

        await MainActor.run {
            let added = profileManager.mergeHydratedSessionResults(merged, forPlayerId: playerId)
            print("[SessionHydration-Debug] player_id=\(playerId.uuidString.lowercased()) sessions_fetched=\(fetchedCount) added_to_local=\(added) context=\(context)")
        }
    }

    // MARK: - session_summary (preferred)

    private struct SessionSummaryHydrateRow: Decodable {
        let id: String
        let session_id: String
        let player_id: String?
        let activity_id: String
        let decisions_total: Int
        let correct_total: Int
        let accuracy: Double?
        let avg_reaction_ms: Double?
        let fast_count: Int
        let medium_count: Int
        let slow_count: Int
        let decision_speed_score: Int?
        let created_at: String
    }

    private static func fetchFromSessionSummary(playerId: UUID) async throws -> ([SessionResult], Set<String>) {
        let client = SupabaseClientManager.client
        let pid = playerId.uuidString.lowercased()
        let rows: [SessionSummaryHydrateRow] = try await client
            .from("session_summary")
            .select("id, session_id, player_id, activity_id, decisions_total, correct_total, accuracy, avg_reaction_ms, fast_count, medium_count, slow_count, decision_speed_score, created_at")
            .eq("player_id", value: pid)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
            .value

        var sessionIds = Set<String>()
        var results: [SessionResult] = []
        results.reserveCapacity(rows.count)

        for row in rows {
            sessionIds.insert(row.session_id.lowercased())
            guard let summaryUUID = UUID(uuidString: row.id) else { continue }
            let resolvedPlayer = row.player_id.flatMap { UUID(uuidString: $0) } ?? playerId
            guard let activity = activityKind(fromActivityId: row.activity_id) else { continue }
            guard row.decisions_total > 0 else { continue }

            let avgSec: Double? = row.avg_reaction_ms.map { $0 / 1000.0 }
            let total = row.decisions_total
            let correct = min(max(row.correct_total, 0), total)

            let result = SessionResult(
                id: summaryUUID,
                date: parseDate(row.created_at),
                playerID: resolvedPlayer,
                activityType: activity,
                correctCount: correct,
                totalReps: total,
                speedCounts: SessionSpeedCounts(
                    fast: row.fast_count,
                    medium: row.medium_count,
                    slow: row.slow_count
                ),
                avgDecisionTime: avgSec,
                biasDirection: nil,
                directionCounts: [:],
                firstTouchCounts: nil,
                firstTouchMatchCount: nil,
                firstTouchTowardPressureCount: nil,
                firstTouchHesitantCount: nil,
                lateAdjustments: nil,
                notes: nil,
                difficulty: nil,
                decisionTotalScore: row.decision_speed_score.map(Double.init),
                forwardChoiceCount: nil,
                forwardOpportunityCount: nil,
                preReceiveDecisionCount: nil,
                decisionTimeStdDev: nil
            )
            results.append(result)
        }

        return (results, sessionIds)
    }

    // MARK: - sessions + session_activities + decisions (fallback)

    private struct SessionRow: Decodable {
        let id: String
        let block_size: Int
        let decisions_completed: Int
        let decision_speed_score: Int?
        let created_at: String
    }

    private struct SessionActivityRow: Decodable {
        let session_id: String
        let activity_id: String
        let block_number: Int
    }

    private struct DecisionRow: Decodable {
        let session_id: String
        let correct: Bool
        let decision_time_seconds: Double?
    }

    private static func fetchFromSessionsFallback(playerId: UUID, excludingSessionIds: Set<String>) async throws -> [SessionResult] {
        let client = SupabaseClientManager.client
        let pid = playerId.uuidString.lowercased()

        let sessionRows: [SessionRow] = try await client
            .from("sessions")
            .select("id, block_size, decisions_completed, decision_speed_score, created_at")
            .eq("player_id", value: pid)
            .order("created_at", ascending: false)
            .limit(500)
            .execute()
            .value

        let filtered = sessionRows.filter { !excludingSessionIds.contains($0.id.lowercased()) }
        guard !filtered.isEmpty else { return [] }

        let sessionIdList = filtered.map(\.id)

        let activities: [SessionActivityRow] = try await client
            .from("session_activities")
            .select("session_id, activity_id, block_number")
            .in("session_id", values: sessionIdList)
            .execute()
            .value

        var activityBySession: [String: String] = [:]
        var bestBlock: [String: Int] = [:]
        for a in activities {
            let sid = a.session_id.lowercased()
            let prev = bestBlock[sid] ?? Int.max
            if a.block_number < prev {
                bestBlock[sid] = a.block_number
                activityBySession[sid] = a.activity_id
            }
        }

        let decisions: [DecisionRow] = try await client
            .from("decisions")
            .select("session_id, correct, decision_time_seconds")
            .in("session_id", values: sessionIdList)
            .execute()
            .value

        var decisionsBySession: [String: [DecisionRow]] = [:]
        for d in decisions {
            let sid = d.session_id.lowercased()
            decisionsBySession[sid, default: []].append(d)
        }

        var results: [SessionResult] = []

        for s in filtered {
            let sid = s.id.lowercased()
            guard let activityIdStr = activityBySession[sid],
                  let activity = activityKind(fromActivityId: activityIdStr),
                  let sessionUUID = UUID(uuidString: s.id) else { continue }

            let reps = decisionsBySession[sid] ?? []
            let total: Int
            let correct: Int
            var avgRaw: Double?
            var fast = 0, medium = 0, slow = 0

            if !reps.isEmpty {
                total = reps.count
                correct = reps.filter(\.correct).count
                let times = reps.compactMap(\.decision_time_seconds)
                if !times.isEmpty {
                    avgRaw = times.reduce(0, +) / Double(times.count)
                }
                for t in times {
                    switch TimingThresholds.speedBucket(for: t, activity: activity) {
                    case .fast: fast += 1
                    case .medium: medium += 1
                    case .slow: slow += 1
                    }
                }
            } else {
                total = max(s.decisions_completed, s.block_size, 1)
                correct = 0
            }

            guard total > 0 else { continue }

            let result = SessionResult(
                id: sessionUUID,
                date: parseDate(s.created_at),
                playerID: playerId,
                activityType: activity,
                correctCount: correct,
                totalReps: total,
                speedCounts: SessionSpeedCounts(fast: fast, medium: medium, slow: slow),
                avgDecisionTime: avgRaw,
                biasDirection: nil,
                directionCounts: [:],
                firstTouchCounts: nil,
                firstTouchMatchCount: nil,
                firstTouchTowardPressureCount: nil,
                firstTouchHesitantCount: nil,
                lateAdjustments: nil,
                notes: nil,
                difficulty: nil,
                decisionTotalScore: s.decision_speed_score.map(Double.init),
                forwardChoiceCount: nil,
                forwardOpportunityCount: nil,
                preReceiveDecisionCount: nil,
                decisionTimeStdDev: nil
            )
            results.append(result)
        }

        return results
    }

    // MARK: - Helpers

    private static func activityKind(fromActivityId id: String) -> ActivityKind? {
        switch id.lowercased() {
        case "two_minute_test": return .twoMinuteTest
        case "away_from_pressure": return .awayFromPressure
        case "dribble_or_pass": return .dribbleOrPass
        case "one_touch_passing": return .oneTouchPassing
        default: return nil
        }
    }

    private static func parseDate(_ s: String) -> Date {
        if let d = isoFractional.date(from: s) { return d }
        return isoPlain.date(from: s) ?? Date()
    }
}
