//
//  SupabasePlayerService.swift
//  FootballScanningAI
//
//  Syncs player profiles to the Supabase `players` table so sessions can be associated with players.
//  Uses the same player UUID locally and in Supabase. Offline: store locally, upload when connectivity returns.
//

import Foundation
import Supabase

/// One row in the Supabase `players` table. Include columns: id, user_id, name, created_at; optional: age, team, position.
struct SupabasePlayerRow: Encodable {
    let id: String
    let user_id: String?
    let name: String
    let created_at: String
    let age: Int?
    let team: String?
    let position: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(user_id, forKey: .user_id)
        try c.encode(name, forKey: .name)
        try c.encode(created_at, forKey: .created_at)
        try c.encodeIfPresent(age, forKey: .age)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encodeIfPresent(position, forKey: .position)
    }

    private enum CodingKeys: String, CodingKey {
        case id, user_id, name, created_at, age, team, position
    }
}

/// Minimal row for "exists" check (select id only).
private struct PlayerIdRow: Decodable {
    let id: String
}

/// Player row returned from Supabase (for listing by user_id).
struct SupabasePlayer: Decodable, Identifiable {
    let id: String
    let name: String
    let user_id: String?
    let created_at: String
    let age: Int?
    let team: String?
    let position: String?
    var uuid: UUID? { UUID(uuidString: id) }
}

final class SupabasePlayerService {
    static let shared = SupabasePlayerService()

    private let syncedIdsKey = "supabaseSyncedPlayerIds"

    init() {}

    /// Persisted set of player IDs that have been successfully synced to Supabase.
    private var syncedPlayerIds: Set<UUID> {
        get {
            let list = (UserDefaults.standard.array(forKey: syncedIdsKey) as? [String]) ?? []
            return Set(list.compactMap { UUID(uuidString: $0) })
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: syncedIdsKey)
        }
    }

    /// If the player is already in the synced set, no-op. If not signed in, do not insert (players table only after auth).
    /// Otherwise check Supabase for existing row by id; if found, add to synced set. If not found, insert with user_id = auth.uid().
    /// Runs asynchronously; safe to call from main thread.
    func syncPlayer(_ profile: UserProfile) {
        guard ConnectionManager.shared.isHost else { return }
        let client = SupabaseClientManager.client
        guard AuthManager.shared.currentUserId != nil else { return }
        let id = profile.id
        if syncedPlayerIds.contains(id) { return }

        let idStr = id.uuidString.lowercased()
        let userIdStr = AuthManager.shared.currentUserId?.uuidString.lowercased()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let row = SupabasePlayerRow(
            id: idStr,
            user_id: userIdStr,
            name: profile.name,
            created_at: iso.string(from: profile.dateCreated),
            age: nil,
            team: nil,
            position: nil
        )

        Task {
            do {
                let existing: [PlayerIdRow] = try await client.from("players").select("id").eq("id", value: idStr).execute().value
                if !existing.isEmpty {
                    markSynced(id: id)
                    return
                }
                try await client.from("players").insert(row).execute()
                markSynced(id: id)
            } catch {
                print("[Supabase] Failed to sync player \(idStr): \(error)")
            }
        }
    }

    private func markSynced(id: UUID) {
        var set = syncedPlayerIds
        set.insert(id)
        syncedPlayerIds = set
    }

    /// Mark multiple player ids as synced (e.g. after fetching from Supabase so we don't re-insert).
    func markPlayersAsSynced(_ ids: [UUID]) {
        var set = syncedPlayerIds
        for id in ids { set.insert(id) }
        syncedPlayerIds = set
    }

    /// Try to sync all profiles that are not yet in the synced set. Call on app launch and when connectivity returns. No-op on coach remote.
    func retryPendingPlayers(profileManager: UserProfileManager) {
        guard ConnectionManager.shared.isHost else { return }
        for profile in profileManager.profiles where !syncedPlayerIds.contains(profile.id) {
            syncPlayer(profile)
        }
    }

    /// Fetch all players for the current authenticated user. Returns empty if not host or not logged in.
    func fetchPlayersForCurrentUser() async throws -> [SupabasePlayer] {
        guard ConnectionManager.shared.isHost else { return [] }
        guard let userId = AuthManager.shared.currentUserId else { return [] }
        let client = SupabaseClientManager.client
        let userIdStr = userId.uuidString.lowercased()
        var list: [SupabasePlayer]
        do {
            list = try await client.from("players")
                .select("id, name, user_id, created_at, age, team, position")
                .eq("user_id", value: userIdStr)
                .execute()
                .value
        } catch {
            list = try await client.from("players")
                .select("id, name, user_id, created_at")
                .eq("user_id", value: userIdStr)
                .execute()
                .value
        }
        return list
    }

    /// Insert a new player for the current user (e.g. after account creation). Uses the given id, name, and optional age/team/position.
    /// Requires host device and authenticated user; user_id in the row is set to auth.uid(). Throws if not host, not signed in, or Supabase not configured.
    func insertPlayer(id: UUID, name: String, age: Int? = nil, team: String? = nil, position: String? = nil) async throws {
        guard ConnectionManager.shared.isHost else { throw SupabasePlayerError.notConfigured }
        guard let userId = AuthManager.shared.currentUserId else {
            throw SupabasePlayerError.notAuthenticated
        }
        let client = SupabaseClientManager.client
        let idStr = id.uuidString.lowercased()
        let userIdStr = userId.uuidString.lowercased()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let row = SupabasePlayerRow(
            id: idStr,
            user_id: userIdStr,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            created_at: iso.string(from: Date()),
            age: age,
            team: team?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            position: position?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        try await client.from("players").insert(row).execute()
        markSynced(id: id)
    }
}

enum SupabasePlayerError: LocalizedError {
    case notConfigured
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase is not configured."
        case .notAuthenticated: return "You must be signed in to create a player."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
