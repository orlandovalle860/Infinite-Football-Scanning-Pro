//
//  AuthFlowOnboardingSync.swift
//  FootballScanningAI
//
//  Keeps “2-Minute baseline completed” in sync with Supabase auth user_metadata (per auth.uid),
//  and mirrors it to local AppStorage/UserDefaults for routing. Backfills metadata from
//  session_summary when older accounts have no flag yet.
//

import Foundation
import Supabase

enum AuthFlowOnboardingSync {
    /// Matches `auth.users.raw_user_meta_data` key (snake_case).
    static let metadataKey = "has_completed_initial_test"

    // MARK: - Parse

    static func parseMetadataFlag(from user: User?) -> Bool? {
        guard let user else { return nil }
        guard let value = user.userMetadata[metadataKey] else { return nil }
        switch value {
        case .bool(let b):
            return b
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(t) { return true }
            if ["false", "0", "no"].contains(t) { return false }
            return nil
        case .integer(let i):
            return i != 0
        case .double(let d):
            return d != 0
        default:
            return nil
        }
    }

    /// After a successful player list fetch (or empty list), refresh session, merge remote + optional history, update local flag, backfill metadata if needed.
    static func resolveAndApplyOnboardingStateAfterLogin(
        email: String?,
        playerList: [SupabasePlayer],
        context: String,
        profileManager: UserProfileManager
    ) async {
        let localCompletionBeforeLogin = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
        print("[GuestMerge-Debug] local completion before login: \(localCompletionBeforeLogin) context=\(context)")

        guard Config.isSupabaseConfigured else {
            print("[GuestMerge-Debug] auth.uid=\(AuthManager.shared.currentUserId?.uuidString.lowercased() ?? "nil") merge skipped (Supabase not configured)")
            authFlowDebugLog(
                context: context,
                email: email,
                uid: AuthManager.shared.currentUserId,
                playerRecordExists: !playerList.isEmpty,
                localFlag: UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey),
                remoteFlag: nil,
                inferredFromHistory: false,
                merged: UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey),
                routingNote: "supabase_not_configured"
            )
            return
        }

        await AuthManager.shared.refreshSessionFromSupabase()

        // If caller had no rows (e.g. coach path or error), fetch again now that Multipeer role does not block.
        var effectiveList = playerList
        if effectiveList.isEmpty, AuthManager.shared.currentUserId != nil {
            if let fetched = try? await SupabasePlayerService.shared.fetchPlayersForCurrentUser() {
                effectiveList = fetched
            }
        }

        let uid = AuthManager.shared.currentUserId
        print("[GuestMerge-Debug] auth.uid=\(uid?.uuidString.lowercased() ?? "nil")")
        let guestTwoMinuteLocalSessions = ProgressStore.shared.sessions.filter { $0.activity == .twoMinuteTest }.count
        print("[GuestMerge-Debug] local ProgressStore two_minute session rows (device): \(guestTwoMinuteLocalSessions)")

        let user = AuthManager.shared.currentSession?.user
        let remoteParsed = parseMetadataFlag(from: user)
        let local = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
        let playerRecordExists = !effectiveList.isEmpty

        var inferred = false
        if remoteParsed != true, playerRecordExists {
            let ids = effectiveList.compactMap(\.uuid)
            inferred = await hasTwoMinuteSessionSummary(forPlayerIds: ids)
        }

        // Include local device flag so a baseline finished before sign-in (or without cloud row yet) is not lost.
        let merged = (remoteParsed == true) || inferred || local
        let guestMergeTriggered = localCompletionBeforeLogin && merged && uid != nil
        print("[GuestMerge-Debug] merge triggered (guest baseline → account): \(guestMergeTriggered) merged=\(merged) remoteMetadata=\(String(describing: remoteParsed)) inferredHistory=\(inferred)")

        if merged {
            UserDefaults.standard.set(true, forKey: hasCompletedInitialTestKey)
        }

        let routing = merged ? "skip_baseline" : "require_baseline"
        print("[GuestMerge-Debug] routing decision: \(routing)")

        authFlowDebugLog(
            context: context,
            email: email ?? user?.email,
            uid: uid,
            playerRecordExists: playerRecordExists,
            localFlag: local,
            remoteFlag: remoteParsed,
            inferredFromHistory: inferred,
            merged: merged,
            routingNote: routing
        )

        var metadataUpdateOk = false
        if merged, remoteParsed != true {
            metadataUpdateOk = await persistRemoteCompletedTrue()
            print("[GuestMerge-Debug] metadata update result: \(metadataUpdateOk ? "success" : "failed_or_skipped")")
        } else if remoteParsed == true {
            print("[GuestMerge-Debug] metadata update skipped (already true on user)")
            metadataUpdateOk = true
        }

        await AuthManager.shared.refreshSessionFromSupabase()
        let remoteAfter = parseMetadataFlag(from: AuthManager.shared.currentSession?.user)
        let finalLocal = UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
        print("[GuestMerge-Debug] final hasCompletedInitialTest local=\(finalLocal) remoteMetadata=\(String(describing: remoteAfter))")

        let targetPlayerIds: [UUID] = {
            let fromList = effectiveList.compactMap(\.uuid)
            if !fromList.isEmpty { return fromList }
            return profileManager.profiles.map(\.id)
        }()
        Task(priority: .utility) {
            await SessionResultSupabaseHydration.hydrateSessionResultsAfterLogin(
                profileManager: profileManager,
                playerIds: targetPlayerIds,
                context: context
            )
        }
    }

    /// Sets local flag only — e.g. user just finished the 2‑minute test before an account exists (no auth to sync yet).
    static func markLocalBaselineCompleted() {
        UserDefaults.standard.set(true, forKey: hasCompletedInitialTestKey)
    }

    /// Sets local flag and pushes true to user_metadata (best-effort).
    static func markLocalAndSyncRemoteCompleted() {
        UserDefaults.standard.set(true, forKey: hasCompletedInitialTestKey)
        Task { await persistRemoteCompletedTrue() }
    }

    /// Pushes `has_completed_initial_test` to auth user_metadata. Returns whether the update appeared to succeed.
    @discardableResult
    static func persistRemoteCompletedTrue() async -> Bool {
        guard AuthManager.shared.currentUserId != nil else {
            print("[GuestMerge-Debug] persistRemote skipped: no auth.uid")
            return false
        }
        let client = SupabaseClientManager.client
        do {
            _ = try await client.auth.update(
                user: UserAttributes(data: [metadataKey: .bool(true)])
            )
            await AuthManager.shared.refreshSessionFromSupabase()
            print("[AuthFlow-Debug] persistRemote has_completed_initial_test=true OK")
            print("[GuestMerge-Debug] user_metadata has_completed_initial_test write OK")
            return true
        } catch {
            print("[AuthFlow-Debug] persistRemote failed error=\(error.localizedDescription)")
            print("[GuestMerge-Debug] user_metadata write failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - History backfill (legacy accounts)

    private struct SessionSummaryIdRow: Decodable {
        let id: String
    }

    private static func hasTwoMinuteSessionSummary(forPlayerIds playerIds: [UUID]) async -> Bool {
        guard !playerIds.isEmpty else { return false }
        let client = SupabaseClientManager.client
        let ids = playerIds.map { $0.uuidString.lowercased() }
        let activityId = ActivityKind.twoMinuteTest.sessionActivityActivityId
        do {
            let rows: [SessionSummaryIdRow] = try await client.from("session_summary")
                .select("id")
                .in("player_id", values: ids)
                .eq("activity_id", value: activityId)
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            print("[AuthFlow-Debug] session_summary two_minute probe failed error=\(error.localizedDescription)")
            return false
        }
    }

    private static func authFlowDebugLog(
        context: String,
        email: String?,
        uid: UUID?,
        playerRecordExists: Bool,
        localFlag: Bool,
        remoteFlag: Bool?,
        inferredFromHistory: Bool,
        merged: Bool,
        routingNote: String
    ) {
        let remoteStr: String
        if let r = remoteFlag {
            remoteStr = "\(r)"
        } else {
            remoteStr = "nil"
        }
        print(
            "[AuthFlow-Debug] context=\(context) email=\(email ?? "nil") auth.uid=\(uid?.uuidString.lowercased() ?? "nil") playerRecordExists=\(playerRecordExists) hasCompletedInitialTest local=\(localFlag) remoteMetadata=\(remoteStr) inferredTwoMinHistory=\(inferredFromHistory) mergedCompleted=\(merged) routing=\(routingNote)"
        )
    }
}
