//
//  AccountDeletionService.swift
//  FootballScanningAI
//
//  In-app account deletion:
//  1) Prefer Edge Function `delete-account` (Apple token revoke + players/history + auth user)
//  2) Fallback `rpc("delete_user")` (players/history + auth user)
//  3) Always run local sign-out cleanup
//

import Foundation

enum AccountDeletionService {
    /// Deletes the remote account (Apple revoke when configured), then clears local state and returns home.
    /// Returns whether the remote delete appeared to succeed.
    @MainActor
    static func performAccountDeletion(
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore,
        router: AppRouter
    ) async -> Bool {
        print("[AccountDeletion] delete account requested")
        let authDeleted = await AuthManager.shared.deleteAccount()
        // Always sign out and return home — even if the RPC failed — so the device is never left mid-session.
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
