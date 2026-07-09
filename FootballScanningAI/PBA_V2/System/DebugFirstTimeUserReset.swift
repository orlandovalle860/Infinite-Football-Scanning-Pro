//
//  DebugFirstTimeUserReset.swift
//  FootballScanningAI
//
//  Simulates first launch by wiping local state. Implementation runs in DEBUG builds only;
//  Release builds keep the API as a no-op so call sites can stay testable without shipping behavior.
//

import Foundation

enum DebugFirstTimeUserReset {
    static func resetToFirstTimeUser(
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore,
        router: AppRouter
    ) {
#if DEBUG
        performReset(
            profileManager: profileManager,
            playerStore: playerStore,
            progressStore: progressStore,
            router: router
        )
#endif
    }

#if DEBUG
    private static let keyPrefixesToRemove = [
        "playerFirstRunGuidanceCompleted.",
        "coachFirstRunGuidanceCompleted.",
        "wedge_difficulty_level",
        "wedge_difficulty_last_eval_date",
        "pba.soloLifetimeReps.",
        "pba_daily_progress",
        "pba_daily_progress_date",
        "pending_badge_unlocks",
        "pending_badge_tier_unlocks",
    ]

    private static let explicitKeysToRemove: [String] = [
        hasCompletedInitialTestKey,
        hasSeenIntroKey,
        hasCompletedPocketOnboardingStepsKey,
        AppStorageKeys.hasLaunchedBefore,
        FirstSessionOnboardingStore.hasCompletedFirstSessionKey,
        "pba.lastLoginPromptDay",
        "pba.loginPromptDeclinedDay",
        PostSessionFeedbackStore.totalSessionsKey,
        PostSessionFeedbackStore.totalRepsKey,
        PostSessionFeedbackStore.longestSessionDurationKey,
        PostSessionFeedbackStore.lastTrainingDayKey,
        PostSessionFeedbackStore.currentStreakDaysKey,
        AppStorageKeys.soloReturnTime,
        AppStorageKeys.soloForceInlineCalibration,
        AppStorageKeys.lastSessionDuration,
        AppStorageKeys.lastTrainingStyle,
        AppStorageKeys.lastMode,
        "pba.lastSelectedTrainingMode",
        "pba.lastSelectedDeviceRole",
        "twoMinuteTest.lastSelectedDeviceRole",
        "awayFromPressure.lastSelectedDeviceRole",
        "dribbleOrPass.lastSelectedDeviceRole",
        "oneTouchPassing.lastSelectedDeviceRole",
        "coachDeviceShownHome",
        "dashboardAudienceRoleV1",
        "dashboardAudienceRolePromptSeenV2",
        "whatsNewControlsSeenV1",
        "hasSeenPlayerSwitcherTooltip",
        "coachRemoteLastUsedActivityV1",
        "partnerPassTempoCalibration.averageTravelTimeSeconds",
        "partnerPassTempoCalibration.savedAt",
        "partnerPassTempoCalibration.trainingMode",
        "pba_sessions_v2",
        "pba_pending_decisions",
        "pba_player_identity",
        "pba_daily_date",
        "pba_daily_blocks",
        "userProfiles",
        "currentProfileId",
        "isProfileCreated",
        "pba_players_v1",
        "pba_selected_player_v1",
        "pba_last_selected_player_v1",
        AppRole.storageKey,
    ]

    private static func performReset(
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore,
        router: AppRouter
    ) {
        clearPersistedState()
        profileManager.clearAllForSignOut()
        playerStore.clearAll()
        progressStore.clearAllSessionsForDebugReset()
        SupabaseDecisionService.shared.clearPendingDecisionsQueue()
        CurrentSessionStore.shared.clear()
        router.resetToHome()

        print("App reset to first-time user state")
    }

    private static func clearPersistedState() {
        let defaults = UserDefaults.standard

        for key in explicitKeysToRemove {
            defaults.removeObject(forKey: key)
        }

        for key in defaults.dictionaryRepresentation().keys {
            if keyPrefixesToRemove.contains(where: { key.hasPrefix($0) }) {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(false, forKey: hasCompletedInitialTestKey)
        defaults.set(false, forKey: hasSeenIntroKey)
        defaults.set(false, forKey: AppStorageKeys.hasLaunchedBefore)
        defaults.set(false, forKey: FirstSessionOnboardingStore.hasCompletedFirstSessionKey)
        defaults.set(AppRole.player.rawValue, forKey: AppRole.storageKey)
    }
#endif
}
