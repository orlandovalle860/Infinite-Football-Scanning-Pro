//
//  AccountDeletionService.swift
//  FootballScanningAI
//
//  In-app account deletion: Supabase auth user removal + local sign-out cleanup.
//

import Foundation

enum AccountDeletionService {
    /// Attempts `deleteUser()`, then always runs local sign-out cleanup. Returns whether auth deletion succeeded.
    @MainActor
    static func performAccountDeletion(
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore,
        router: AppRouter
    ) async -> Bool {
        print("[AccountDeletion] delete account requested")
        let authDeleted = await AuthManager.shared.deleteAccount()
        await AccountSignOutService.performSignOut(
            profileManager: profileManager,
            playerStore: playerStore,
            progressStore: progressStore,
            router: router
        )
        print("[AccountDeletion] complete authDeleted=\(authDeleted)")
        return authDeleted
    }
}
