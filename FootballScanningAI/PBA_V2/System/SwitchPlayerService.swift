//
//  SwitchPlayerService.swift
//  FootballScanningAI
//
//  Fast handoff to player selection on the same device/account (no Supabase sign-out, no remote deletes).
//

import Foundation

enum SwitchPlayerService {
    /// Clears active player selection and session-only state, then returns to root so `MainAppView` shows `PlayerSelectionView`.
    /// Multipeer / partner pairing is preserved (`popToRoot(endingPartnerSession: false)`).
    @MainActor
    static func performSwitchPlayer(
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        router: AppRouter
    ) {
        print("[SwitchPlayer-Debug] switch player requested")
        let authPreserved = AuthManager.shared.currentSession != nil

        CurrentSessionStore.shared.clear()
        print("[SwitchPlayer-Debug] cleared local state: CurrentSessionStore (active drill/session_activity ids)")

        profileManager.clearCurrentSelectionForSwitchPlayer()
        print("[SwitchPlayer-Debug] cleared local state: UserProfileManager currentProfile + in-flight training session settings; profiles retained count=\(profileManager.profiles.count)")

        let previousSelection = playerStore.selectedPlayerId?.uuidString ?? "nil"
        playerStore.clearSelectedPlayerOnly()
        print("[SwitchPlayer-Debug] cleared local state: PlayerStore selectedPlayerId (was \(previousSelection)); players retained count=\(playerStore.players.count)")

        print("[SwitchPlayer-Debug] auth session preserved=\(authPreserved) (no sign-out)")

        router.popToRoot(endingPartnerSession: false)
        print("[SwitchPlayer-Debug] routing to player selection (root updated when selectedPlayerId is nil; navigation path cleared)")
    }
}
