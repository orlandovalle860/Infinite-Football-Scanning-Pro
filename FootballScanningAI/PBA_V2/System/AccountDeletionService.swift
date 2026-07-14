//
//  AccountDeletionService.swift
//  FootballScanningAI
//
//  In-app account deletion: Supabase auth user removal + local sign-out cleanup.
//

import Foundation

enum AccountDeletionService {
    /// 1) `rpc("delete_user")` while authenticated  
    /// 2) Always run existing sign-out cleanup (local caches + auth session)  
    /// 3) `performSignOut` pops navigation to root/home  
    /// Returns whether the Supabase RPC succeeded.
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
