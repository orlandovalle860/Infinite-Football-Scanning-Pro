//
//  HomeDashboardDataService.swift
//  FootballScanningAI
//
//  Fetches the last 7 session_summary rows for the current player and returns
//  HomeDashboardData (latest score, improvement, accuracy, avg reaction, fast %, trend).
//

import Foundation
import Supabase

/// Result for the home dashboard: latest score, improvement vs previous, accuracy, avg reaction, fast decision %, and trend of last 7 scores.
struct HomeDashboardData {
    let latestScore: Int?
    let improvement: Int?
    let accuracy: Double?
    let avgReactionMs: Double?
    let fastPercent: Double?
    let trendScores: [Int]
}

/// Fetches last 7 rows from session_summary for the current player; computes improvement, trend, and fast_percent.
final class HomeDashboardDataService {
    static let shared = HomeDashboardDataService()

    private init() {}

    /// Row decoded from session_summary (select decision_speed_score, accuracy, avg_reaction_ms, fast_count, medium_count, slow_count, created_at).
    private struct SessionSummaryFetchRow: Decodable {
        let decision_speed_score: Int?
        let accuracy: Double?
        let avg_reaction_ms: Double?
        let fast_count: Int
        let medium_count: Int
        let slow_count: Int
        let created_at: String
    }

    /// Fetches the last 7 session_summary rows for the given player, then computes and returns HomeDashboardData.
    /// Returns nil if no player or fetch fails.
    func fetchDashboardData(playerId: UUID?) async -> HomeDashboardData? {
        guard let playerId = playerId else { return nil }
        let supabase = SupabaseClientManager.client
        let playerIdStr = playerId.uuidString.lowercased()

        do {
            let sessions: [SessionSummaryFetchRow] = try await supabase
                .from("session_summary")
                .select("decision_speed_score, accuracy, avg_reaction_ms, fast_count, medium_count, slow_count, created_at")
                .eq("player_id", value: playerIdStr)
                .order("created_at", ascending: false)
                .limit(7)
                .execute()
                .value

            return buildDashboardData(from: sessions)
        } catch {
            print("[Supabase] Failed to fetch session_summary for dashboard: \(error)")
            return nil
        }
    }

    private func buildDashboardData(from sessions: [SessionSummaryFetchRow]) -> HomeDashboardData {
        let latestScore = sessions.first?.decision_speed_score
        let previousScore = sessions.count > 1 ? sessions[1].decision_speed_score : nil
        let improvement: Int? = {
            guard let a = latestScore, let b = previousScore else { return nil }
            return a - b
        }()

        let trendScores = sessions.map(\.decision_speed_score).compactMap { $0 }

        let latest = sessions.first
        let accuracy = latest?.accuracy
        let avgReactionMs = latest?.avg_reaction_ms

        let fastPercent: Double? = {
            guard let latest = latest else { return nil }
            let total = latest.fast_count + latest.medium_count + latest.slow_count
            guard total > 0 else { return nil }
            return Double(latest.fast_count) / Double(total)
        }()

        return HomeDashboardData(
            latestScore: latestScore,
            improvement: improvement,
            accuracy: accuracy,
            avgReactionMs: avgReactionMs,
            fastPercent: fastPercent,
            trendScores: trendScores
        )
    }
}
