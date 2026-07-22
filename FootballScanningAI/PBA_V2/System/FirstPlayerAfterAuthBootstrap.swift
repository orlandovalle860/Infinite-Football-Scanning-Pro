//
//  FirstPlayerAfterAuthBootstrap.swift
//  FootballScanningAI
//
//  After Sign in with Apple / email auth, ensure a first player exists without asking for
//  name or email again (Guideline 4 / SIWA HIG). Uses the account-holder name from Apple
//  when available; otherwise a neutral default. Extra players still use AddPlayerView.
//

import Foundation

enum FirstPlayerAfterAuthBootstrap {
    /// Display name for the first training profile when the roster is empty.
    static func defaultFirstPlayerName() -> String {
        if let apple = AuthManager.shared.accountHolderFullName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apple.isEmpty {
            return apple
        }
        if let email = AuthManager.shared.currentUserEmail,
           let local = email.split(separator: "@").first,
           !local.isEmpty {
            return String(local)
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
        profileManager.reconcileWithSupabasePlayerList(remoteList, playerStore: playerStore)

        // Returning user (or any non-empty roster): reconcile already hydrated locals and preserved selection.
        // Never insert another row and never show a name form.
        if !remoteList.isEmpty {
            print("[FirstPlayerBootstrap] context=\(context) existingPlayers=\(remoteList.count) — no create")
            return true
        }

        guard AuthManager.shared.currentUserId != nil else {
            print("[FirstPlayerBootstrap] context=\(context) skipped — no auth.uid")
            return false
        }

        let name = defaultFirstPlayerName()
        let playerId = UUID()
        do {
            try await SupabasePlayerService.shared.insertPlayer(id: playerId, name: name)
        } catch {
            // Race: another device created a row — adopt it.
            if let listRetry = try? await SupabasePlayerService.shared.fetchPlayersForCurrentUser(),
               !listRetry.isEmpty {
                profileManager.reconcileWithSupabasePlayerList(listRetry, playerStore: playerStore)
                print("[FirstPlayerBootstrap] context=\(context) insertConflict adoptedExisting count=\(listRetry.count)")
                return true
            }
            print("[FirstPlayerBootstrap] context=\(context) insertFailed error=\(error.localizedDescription)")
            return false
        }

        hydrateLocal(id: playerId, name: name, profileManager: profileManager, playerStore: playerStore)
        AuthFlowOnboardingSync.markLocalAndSyncRemoteCompleted()
        if let result = twoMinuteTestResult, let progressStore {
            saveTwoMinuteTestSession(result: result, playerId: playerId, profileManager: profileManager, progressStore: progressStore)
        }
        AnalyticsManager.shared.track(.playerCreated, playerId: playerId)
        print("[FirstPlayerBootstrap] context=\(context) createdFirstPlayer id=\(playerId.uuidString.lowercased()) name=\(name)")
        return true
    }

    private static func hydrateLocal(
        id: UUID,
        name: String,
        profileManager: UserProfileManager,
        playerStore: PlayerStore
    ) {
        if !profileManager.profiles.contains(where: { $0.id == id }) {
            profileManager.addProfileWithId(id, name: name)
        }
        if !playerStore.players.contains(where: { $0.id == id }) {
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
