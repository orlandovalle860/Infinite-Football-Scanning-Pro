//
//  FirstPlayerAfterAuthBootstrap.swift
//  FootballScanningAI
//
//  After Sign in with Apple / email auth, ensure a first player exists without asking for
//  name or email again (Guideline 4 / SIWA HIG). Uses the account-holder name from Apple
//  when available; otherwise a neutral default. Extra players still use AddPlayerView.
//
//  Concurrency: only one bootstrap runs at a time (Login sheet + session onChange + hydrate
//  can otherwise insert two identical rows with the Apple account name).
//

import Foundation

enum FirstPlayerAfterAuthBootstrap {
    @MainActor private static var isRunning = false
    @MainActor private static var waiters: [CheckedContinuation<Bool, Never>] = []

    /// Display name for the first training profile when the roster is empty.
    /// Prefer Apple account name. Never use Hide My Email local-parts (e.g. `y4tj7vtdhn@privaterelay…`).
    static func defaultFirstPlayerName() -> String {
        if let apple = AuthManager.shared.accountHolderFullName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apple.isEmpty {
            return apple
        }
        if let email = AuthManager.shared.currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            let lower = email.lowercased()
            // Sign in with Apple private relay — local part is a random token, not a display name.
            if lower.hasSuffix("@privaterelay.appleid.com") || lower.contains("privaterelay.appleid.com") {
                return "Player"
            }
            if let local = email.split(separator: "@").first,
               !local.isEmpty {
                return String(local)
            }
        }
        return "Player"
    }

    /// If the signed-in user has no players, creates one from SIWA/account identity and hydrates local stores.
    /// Returns `true` when at least one player exists afterward (created or already present).
    @MainActor
    static func ensureFirstPlayerIfNeeded(
        remoteList: [SupabasePlayer],
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore?,
        twoMinuteTestResult: TwoMinuteTestResult?,
        context: String
    ) async -> Bool {
        // Serialize without nesting a MainActor Task (that pattern can deadlock the launch spinner).
        if isRunning {
            print("[FirstPlayerBootstrap] context=\(context) awaiting in-flight bootstrap")
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        isRunning = true
        let result = await ensureFirstPlayerIfNeededLocked(
            remoteList: remoteList,
            profileManager: profileManager,
            playerStore: playerStore,
            progressStore: progressStore,
            twoMinuteTestResult: twoMinuteTestResult,
            context: context
        )
        isRunning = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: result)
        }
        return result
    }

    @MainActor
    private static func ensureFirstPlayerIfNeededLocked(
        remoteList: [SupabasePlayer],
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore?,
        twoMinuteTestResult: TwoMinuteTestResult?,
        context: String
    ) async -> Bool {
        // Re-fetch under the lock so a concurrent caller that already inserted is visible.
        let authoritative: [SupabasePlayer]
        if let latest = try? await SupabasePlayerService.shared.fetchPlayersForCurrentUser() {
            authoritative = latest
        } else {
            authoritative = remoteList
        }

        profileManager.reconcileWithSupabasePlayerList(authoritative, playerStore: playerStore)

        if !authoritative.isEmpty {
            removeUnsyncedLocalsNotInRemote(
                remoteIds: Set(authoritative.compactMap(\.uuid)),
                profileManager: profileManager,
                playerStore: playerStore
            )
            print("[FirstPlayerBootstrap] context=\(context) existingPlayers=\(authoritative.count) — no create")
            return true
        }

        guard AuthManager.shared.currentUserId != nil else {
            print("[FirstPlayerBootstrap] context=\(context) skipped — no auth.uid")
            return false
        }

        let name = defaultFirstPlayerName()
        // Promote an existing local profile when present — avoids local leftover + new Apple-named row.
        let playerId: UUID
        if let local = profileManager.currentProfile ?? profileManager.profiles.first {
            playerId = local.id
        } else if let localPlayer = playerStore.selectedPlayerId.flatMap({ id in
            playerStore.players.first(where: { $0.id == id })
        }) ?? playerStore.players.first {
            playerId = localPlayer.id
        } else {
            playerId = UUID()
        }

        do {
            try await SupabasePlayerService.shared.insertPlayer(id: playerId, name: name)
        } catch {
            if let listRetry = try? await SupabasePlayerService.shared.fetchPlayersForCurrentUser(),
               !listRetry.isEmpty {
                profileManager.reconcileWithSupabasePlayerList(listRetry, playerStore: playerStore)
                removeUnsyncedLocalsNotInRemote(
                    remoteIds: Set(listRetry.compactMap(\.uuid)),
                    profileManager: profileManager,
                    playerStore: playerStore
                )
                print("[FirstPlayerBootstrap] context=\(context) insertConflict adoptedExisting count=\(listRetry.count)")
                return true
            }
            print("[FirstPlayerBootstrap] context=\(context) insertFailed error=\(error.localizedDescription)")
            return false
        }

        hydrateLocal(id: playerId, name: name, profileManager: profileManager, playerStore: playerStore)
        removeOtherLocalProfiles(
            keeping: playerId,
            profileManager: profileManager,
            playerStore: playerStore
        )
        AuthFlowOnboardingSync.markLocalAndSyncRemoteCompleted()
        if let result = twoMinuteTestResult, let progressStore {
            saveTwoMinuteTestSession(result: result, playerId: playerId, profileManager: profileManager, progressStore: progressStore)
        }
        AnalyticsManager.shared.track(.playerCreated, playerId: playerId)
        print("[FirstPlayerBootstrap] context=\(context) createdFirstPlayer id=\(playerId.uuidString.lowercased()) name=\(name)")
        return true
    }

    /// Drop never-synced local drafts that are not on the server (prevents duplicate Switch Player rows after SIWA).
    private static func removeUnsyncedLocalsNotInRemote(
        remoteIds: Set<UUID>,
        profileManager: UserProfileManager,
        playerStore: PlayerStore
    ) {
        let extras = profileManager.profiles.filter { profile in
            !remoteIds.contains(profile.id) && !SupabasePlayerService.shared.isPlayerSynced(profile.id)
        }
        for profile in extras {
            print("[FirstPlayerBootstrap] removing unsynced local duplicate id=\(profile.id.uuidString.lowercased()) name=\(profile.name)")
            profileManager.deleteProfile(profile)
            playerStore.removePlayer(id: profile.id)
        }
        playerStore.persist()
    }

    private static func removeOtherLocalProfiles(
        keeping keepId: UUID,
        profileManager: UserProfileManager,
        playerStore: PlayerStore
    ) {
        let extras = profileManager.profiles.filter { $0.id != keepId }
        for profile in extras {
            print("[FirstPlayerBootstrap] removing extra local profile id=\(profile.id.uuidString.lowercased()) name=\(profile.name)")
            if SupabasePlayerService.shared.isPlayerSynced(profile.id) {
                SupabasePlayerService.shared.unmarkSynced(id: profile.id)
            }
            profileManager.deleteProfile(profile)
            playerStore.removePlayer(id: profile.id)
        }
        playerStore.persist()
    }

    private static func hydrateLocal(
        id: UUID,
        name: String,
        profileManager: UserProfileManager,
        playerStore: PlayerStore
    ) {
        if let idx = profileManager.profiles.firstIndex(where: { $0.id == id }) {
            var p = profileManager.profiles[idx]
            if p.name != name {
                p.name = name
                profileManager.profiles[idx] = p
                profileManager.saveProfiles()
            }
        } else {
            profileManager.addProfileWithId(id, name: name)
        }
        if playerStore.players.contains(where: { $0.id == id }) {
            if playerStore.players.first(where: { $0.id == id })?.name != name {
                playerStore.removePlayer(id: id)
                playerStore.addPlayer(id: id, name: name)
            }
        } else {
            playerStore.addPlayer(id: id, name: name)
        }
        SupabasePlayerService.shared.markPlayersAsSynced([id])
        if let profile = profileManager.profiles.first(where: { $0.id == id }) {
            profileManager.switchToProfile(profile)
        }
        playerStore.selectedPlayerId = id
        playerStore.persist()
    }

    private static func saveTwoMinuteTestSession(
        result: TwoMinuteTestResult,
        playerId: UUID,
        profileManager: UserProfileManager,
        progressStore: ProgressStore
    ) {
        let speedBucket = UniversalBlockSummaryHeadline.resolve(
            fast: result.fastCount,
            medium: result.mediumCount,
            slow: result.slowCount
        ).bucket
        let biasString = result.biasDirection?.userFacingName ?? "Balanced"
        let record = SessionRecord(
            id: UUID(),
            date: Date(),
            activity: .twoMinuteTest,
            gridSize: .fiveByFive,
            difficulty: result.difficulty,
            reps: result.totalReps,
            decisionsCompleted: result.totalReps,
            correct: result.correctCount,
            forwardCorrect: result.forwardChoiceCount,
            speedBucket: speedBucket,
            bias: biasString,
            avgLatency: result.avgDecisionTime,
            profile: nil,
            playerId: playerId
        )
        progressStore.add(record)
        SupabaseSessionService.shared.saveSession(record: record, decisions: []) {
            progressStore.markSynced(id: record.id)
        }
        let sessionResult = SessionResult(
            playerID: playerId,
            activityType: .twoMinuteTest,
            correctCount: result.correctCount,
            totalReps: result.totalReps,
            speedCounts: SessionSpeedCounts(fast: result.fastCount, medium: result.mediumCount, slow: result.slowCount),
            avgDecisionTime: result.avgDecisionTime,
            biasDirection: result.biasDirection,
            directionCounts: result.directionCounts,
            difficulty: result.difficulty,
            forwardChoiceCount: result.forwardChoiceCount,
            forwardOpportunityCount: result.forwardOpportunityCount
        )
        profileManager.addSessionResult(sessionResult)
    }
}
