//
//  AccountSignOutService.swift
//  FootballScanningAI
//
//  Local sign-out only: clears auth session and device-scoped caches. Does not delete Supabase rows.
//

import Foundation

enum AccountSignOutService {
    /// Clears Supabase auth session, local profiles/players/progress caches, and onboarding flag so another account can sign in.
    @MainActor
    static func performSignOut(
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore,
        router: AppRouter
    ) async {
        print("[SignOut-Debug] sign out requested")
        let playerIds = profileManager.profiles.map(\.id)
        for id in playerIds {
            DailyDecisionProgress.clearForPlayer(id)
            DailyTargetState.clearForPlayer(id)
            WedgeDifficultyEngine.clearStoredKeys(forPlayerId: id)
        }
        DailyTargetState.clearLegacyDailyKeys()
        DailyDecisionProgress.clearLegacyDailyKeys()

        progressStore.clearAllSessionsForSignOut()
        print("[SignOut-Debug] local session history cleared (ProgressStore)")

        ActivityStatsStore.shared.clearAllForSignOut()
        SoloLifetimeRepCounter.clearAllForSignOut()
        PostSessionFeedbackStore.clearAllForSignOut()
        BestEarlyStreakStore.clearAllForSignOut()
        EarlySessionStreakStore.clearAllForSignOut()
        print("[SignOut-Debug] Progress totals / solo lifetime reps / streaks cleared")

        profileManager.clearAllForSignOut()
        print("[SignOut-Debug] local profile caches cleared (UserProfileManager)")

        playerStore.clearAll()
        print("[SignOut-Debug] local PlayerStore cleared")

        SupabasePlayerService.shared.clearLocalSyncCachesForSignOut()
        print("[SignOut-Debug] Supabase player sync caches cleared")

        UserDefaults.standard.set(false, forKey: hasCompletedInitialTestKey)
        print("[SignOut-Debug] hasCompletedInitialTest reset for next user")

        FirstSessionOnboardingStore.resetLoginPromptEligibilityAfterSignOut()

        CurrentSessionStore.shared.clear()
        SupabaseDecisionService.shared.clearPendingDecisionsQueue()

        await AuthManager.shared.signOut()
        print("[SignOut-Debug] auth session cleared (Supabase + local)")

        router.popToRoot()
        print("[SignOut-Debug] navigation stack cleared; routing to root (intro / sign-in when not authenticated)")
    }
}
