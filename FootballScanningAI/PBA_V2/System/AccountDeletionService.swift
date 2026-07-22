//
//  AccountDeletionService.swift
//  FootballScanningAI
//
//  In-app account deletion:
//  1) Prefer Edge Function `delete-account` (Apple token revoke via stored refresh token + players/history + auth user)
//  2) Fallback `rpc("delete_user")` (players/history + auth user)
//  3) Always run local sign-out cleanup
//
//  Does not present Sign in with Apple during delete — that looked like “sign back in” and confused users.
//  Revoke uses `apple_refresh_token` stored at sign-in by `store-apple-token`.
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
        // Device-scoped wall/pass timing must not carry into a new auth account on the same iPad.
        PartnerPassTempoCalibrationStore.clearSavedCalibration()
        SoloWallCalibrationController.clearSavedSoloWallCalibration()
        print("[AccountDeletion] local pass-tempo / solo wall calibration cleared")
        // Revoke uses tokens stored at SIWA by `store-apple-token` (no mid-delete Apple sheet).
        let authDeleted = await AuthManager.shared.deleteAccount(appleAuthorizationCode: nil)
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
