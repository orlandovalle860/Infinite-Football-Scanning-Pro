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
    private let pendingDeleteIdsKey = "supabasePendingDeletePlayerIds"

    init() {}

    /// Clears local synced/pending-delete caches so the next account does not inherit the previous user’s ids.
    func clearLocalSyncCachesForSignOut() {
        UserDefaults.standard.removeObject(forKey: syncedIdsKey)
        UserDefaults.standard.removeObject(forKey: pendingDeleteIdsKey)
    }

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

    /// Player IDs that are deleted locally and still pending successful remote deletion.
    private var pendingDeletePlayerIds: Set<UUID> {
        get {
            let list = (UserDefaults.standard.array(forKey: pendingDeleteIdsKey) as? [String]) ?? []
            return Set(list.compactMap { UUID(uuidString: $0) })
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: pendingDeleteIdsKey)
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

    /// True if this player id was previously confirmed on the server (insert, fetch, or mark).
    func isPlayerSynced(_ id: UUID) -> Bool {
        syncedPlayerIds.contains(id)
    }

    /// Mark multiple player ids as synced (e.g. after fetching from Supabase so we don't re-insert).
    func markPlayersAsSynced(_ ids: [UUID]) {
        var set = syncedPlayerIds
        for id in ids { set.insert(id) }
        syncedPlayerIds = set
    }

    /// Remove a player id from the local synced cache (e.g. after remote deletion).
    func unmarkSynced(id: UUID) {
        var set = syncedPlayerIds
        set.remove(id)
        syncedPlayerIds = set
    }

    func markPendingDelete(id: UUID) {
        var set = pendingDeletePlayerIds
        set.insert(id)
        pendingDeletePlayerIds = set
    }

    func clearPendingDelete(id: UUID) {
        var set = pendingDeletePlayerIds
        set.remove(id)
        pendingDeletePlayerIds = set
    }

    var pendingDeleteIds: Set<UUID> { pendingDeletePlayerIds }

    /// Try to sync all profiles that are not yet in the synced set. Call on app launch and when connectivity returns. No-op on coach remote.
    func retryPendingPlayers(profileManager: UserProfileManager) {
        guard ConnectionManager.shared.isHost else { return }
        for profile in profileManager.profiles where !syncedPlayerIds.contains(profile.id) {
            syncPlayer(profile)
        }
    }

    /// Retry remote delete for players removed locally but not yet deleted from Supabase.
    func retryPendingDeletes() {
        guard Config.isSupabaseConfigured, AuthManager.shared.currentUserId != nil else { return }
        let pending = pendingDeletePlayerIds
        guard !pending.isEmpty else { return }
        for id in pending {
            Task {
                do {
                    try await deletePlayer(id: id)
                    clearPendingDelete(id: id)
                    #if DEBUG
                    print("[PBA-Debug] Pending delete succeeded: id=\(id.uuidString)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[PBA-Debug] Pending delete retry failed: id=\(id.uuidString), error=\(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    /// Fetch all players for the current authenticated user. Not gated on Multipeer host/display role.
    func fetchPlayersForCurrentUser() async throws -> [SupabasePlayer] {
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
        let filtered = list.filter { row in
            guard let id = row.uuid else { return true }
            return !pendingDeletePlayerIds.contains(id)
        }
        return filtered
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

    /// Delete an existing player from Supabase for the current authenticated user.
    /// Requires host + authenticated user. Also removes the id from local synced cache.
    func deletePlayer(id: UUID) async throws {
        guard Config.isSupabaseConfigured else { throw SupabasePlayerError.notConfigured }
        guard let userId = AuthManager.shared.currentUserId else {
            throw SupabasePlayerError.notAuthenticated
        }
        let client = SupabaseClientManager.client
        let idStr = id.uuidString.lowercased()
        let userIdStr = userId.uuidString.lowercased()
        let tableName = "players"

        #if DEBUG
        print("[PBA-Debug] Supabase delete request: table=\(tableName), id=\(idStr), authUserId=\(userIdStr)")
        #endif

        let before: [PlayerIdRow] = try await client
            .from(tableName)
            .select("id")
            .eq("id", value: idStr)
            .eq("user_id", value: userIdStr)
            .execute()
            .value

        #if DEBUG
        print("[PBA-Debug] Supabase delete start: table=\(tableName), id=\(idStr), user_id=\(userIdStr), beforeCount=\(before.count)")
        #endif

        var strictDeleteError: Error?
        do {
            let strictResponse = try await client
                .from(tableName)
                .delete()
                .eq("id", value: idStr)
                .eq("user_id", value: userIdStr)
                .execute()
            #if DEBUG
            print("[PBA-Debug] Supabase strict delete raw response: \(String(describing: strictResponse))")
            #endif
        } catch {
            strictDeleteError = error
            #if DEBUG
            print("[PBA-Debug] Supabase strict delete error: \(String(describing: error))")
            #endif
        }

        let strictAfter: [PlayerIdRow] = try await client
            .from(tableName)
            .select("id")
            .eq("id", value: idStr)
            .eq("user_id", value: userIdStr)
            .execute()
            .value
        let strictRemovedAnyRow = before.count > strictAfter.count

        // Fallback: delete by id only (RLS should still enforce ownership).
        // This handles cases where user_id formatting/matching differs from expectations.
        var fallbackDeleteError: Error?
        var fallbackRan = false
        if !before.isEmpty && !strictAfter.isEmpty {
            fallbackRan = true
            #if DEBUG
            print("[PBA-Debug] Supabase delete fallback by id only: id=\(idStr)")
            #endif
            do {
                let fallbackResponse = try await client
                    .from(tableName)
                    .delete()
                    .eq("id", value: idStr)
                    .execute()
                #if DEBUG
                print("[PBA-Debug] Supabase fallback delete raw response: \(String(describing: fallbackResponse))")
                #endif
            } catch {
                fallbackDeleteError = error
                #if DEBUG
                print("[PBA-Debug] Supabase fallback delete error: \(String(describing: error))")
                #endif
            }
        }

        let after: [PlayerIdRow] = try await client
            .from(tableName)
            .select("id")
            .eq("id", value: idStr)
            .eq("user_id", value: userIdStr)
            .execute()
            .value
        let fallbackRemovedAnyRow = strictAfter.count > after.count

        // Final existence check by id only (independent of user_id match).
        let finalByIdOnly: [PlayerIdRow] = try await client
            .from(tableName)
            .select("id")
            .eq("id", value: idStr)
            .execute()
            .value
        let existsAfterDelete = !finalByIdOnly.isEmpty

        #if DEBUG
        if let strictDeleteError {
            print("[PBA-Debug] Supabase strict delete captured error detail: \(strictDeleteError)")
        }
        if let fallbackDeleteError {
            print("[PBA-Debug] Supabase fallback delete captured error detail: \(fallbackDeleteError)")
        }
        print("[PBA-Debug] Supabase delete result: table=\(tableName), id=\(idStr), strictRemovedAnyRow=\(strictRemovedAnyRow), fallbackRan=\(fallbackRan), fallbackRemovedAnyRow=\(fallbackRemovedAnyRow), finalExistsById=\(existsAfterDelete), afterCountUserScoped=\(after.count)")
        #endif

        if !before.isEmpty && !after.isEmpty {
            throw SupabasePlayerError.deleteFailed
        }

        unmarkSynced(id: id)
        clearPendingDelete(id: id)
    }
}

enum SupabasePlayerError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase is not configured."
        case .notAuthenticated: return "You must be signed in to create a player."
        case .deleteFailed: return "Supabase player delete failed."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
