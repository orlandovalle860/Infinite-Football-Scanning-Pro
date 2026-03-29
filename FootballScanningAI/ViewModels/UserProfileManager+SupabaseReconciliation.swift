//
//  UserProfileManager+SupabaseReconciliation.swift
//  FootballScanningAI
//
//  Aligns local profiles with Supabase for the signed-in user: removes stale rows that
//  no longer exist remotely while keeping never-synced local-only profiles (offline draft).
//

import Foundation

#if DEBUG
enum ProfileLoadSourceLog {
    static func loadedFromDisk(profileCount: Int) {
        print("[Profiles] source=local persisted UserDefaults userProfiles count=\(profileCount)")
    }

    static func reconciledWithRemote(remoteRowCount: Int, removedStaleCount: Int, keptLocalOnlyUnsyncedCount: Int, resultingProfileCount: Int) {
        print("[Profiles] source=remote Supabase rows=\(remoteRowCount) removedStale=\(removedStaleCount) keptLocalOnlyUnsynced=\(keptLocalOnlyUnsyncedCount) after=\(resultingProfileCount)")
    }

    static func reconcileSkipped(reason: String) {
        print("[Profiles] reconcile skipped: \(reason)")
    }
}
#endif

extension UserProfileManager {
    /// After a successful `fetchPlayersForCurrentUser`, merge server rows into local state and **remove** local profiles that were synced to Supabase but are no longer returned for this account.
    /// Keeps **never-synced** local-only profiles (e.g. offline draft not yet uploaded). No-op on coach/remote devices where fetch is not performed (`isHost` false).
    func reconcileWithSupabasePlayerList(_ remote: [SupabasePlayer], playerStore: PlayerStore) {
        guard ConnectionManager.shared.isHost else {
#if DEBUG
            ProfileLoadSourceLog.reconcileSkipped(reason: "not host (coach/remote — fetch not authoritative)")
#endif
            return
        }
        guard AuthManager.shared.currentUserId != nil else {
#if DEBUG
            ProfileLoadSourceLog.reconcileSkipped(reason: "not signed in")
#endif
            return
        }

        let remoteIds = Set(remote.compactMap(\.uuid))
        let preferredBefore = playerStore.selectedPlayerId ?? currentProfile?.id
        let countBefore = profiles.count

        // 1) Update names from server
        for row in remote {
            guard let id = row.uuid else { continue }
            if let idx = profiles.firstIndex(where: { $0.id == id }) {
                var p = profiles[idx]
                if p.name != row.name {
                    p.name = row.name
                    profiles[idx] = p
                }
            }
        }

        // 2) Ensure every remote player exists locally
        for row in remote {
            guard let id = row.uuid else { continue }
            if !profiles.contains(where: { $0.id == id }) {
                addProfileById(id, name: row.name)
            }
            if !playerStore.players.contains(where: { $0.id == id }) {
                playerStore.addPlayer(id: id, name: row.name)
            }
        }

        // 3) Drop locals that were synced but no longer appear for this user
        let stale = profiles.filter { p in
            !remoteIds.contains(p.id) && SupabasePlayerService.shared.isPlayerSynced(p.id)
        }
        for p in stale {
            SupabasePlayerService.shared.unmarkSynced(id: p.id)
            deleteProfile(p)
            playerStore.removePlayer(id: p.id)
        }

        LaunchProfileDebug.log("reconcile remoteRows=\(remote.count) removedStale=\(stale.count)")

#if DEBUG
        let keptLocalOnly = profiles.filter { p in
            !remoteIds.contains(p.id) && !SupabasePlayerService.shared.isPlayerSynced(p.id)
        }.count
        ProfileLoadSourceLog.reconciledWithRemote(
            remoteRowCount: remote.count,
            removedStaleCount: stale.count,
            keptLocalOnlyUnsyncedCount: keptLocalOnly,
            resultingProfileCount: profiles.count
        )
#endif

        SupabasePlayerService.shared.markPlayersAsSynced(Array(remoteIds))

        // 4) Selection: prefer previous if still present, else first profile
        if let pid = preferredBefore, profiles.contains(where: { $0.id == pid }), let prof = profile(id: pid) {
            switchToProfile(prof)
            playerStore.selectedPlayerId = pid
        } else if let first = profiles.first {
            switchToProfile(first)
            playerStore.selectedPlayerId = first.id
        } else {
            currentProfile = nil
            isProfileCreated = false
            playerStore.selectedPlayerId = nil
        }

        saveProfiles()
        playerStore.persist()

#if DEBUG
        if countBefore > 0, profiles.isEmpty {
            print("[Profiles] note: all profiles removed after reconcile — user will be prompted to create a player if applicable")
        }
#endif
    }
}
