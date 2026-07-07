//
//  FirstSessionOnboardingStore.swift
//  FootballScanningAI
//
//  Delayed Sign in with Apple: train first, prompt after the first session completes.
//

import Foundation

extension Notification.Name {
    static let firstSessionTrainingCompleted = Notification.Name("FirstSessionTrainingCompleted")
    static let requestDeferredLoginPrompt = Notification.Name("RequestDeferredLoginPrompt")
}

enum FirstSessionOnboardingStore {
    static let hasCompletedFirstSessionKey = "pba.hasCompletedFirstSession"
    private static let lastLoginPromptDayKey = "pba.lastLoginPromptDay"
    private static let loginPromptDeclinedDayKey = "pba.loginPromptDeclinedDay"

    static var hasCompletedFirstSession: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedFirstSessionKey)
    }

    /// Welcome screen is no longer shown at launch — users land on Home directly.
    static func shouldShowWelcomeScreen(isCoachRemoteRole: Bool) -> Bool {
        _ = isCoachRemoteRole
        return false
    }

    /// Existing installs: skip the new welcome funnel.
    static func migrateExistingInstallsIfNeeded() {
        guard !hasCompletedFirstSession else { return }
        let legacyComplete =
            UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
            || UserDefaults.standard.bool(forKey: hasSeenIntroKey)
            || UserDefaults.standard.bool(forKey: AppStorageKeys.hasLaunchedBefore)
        if legacyComplete {
            UserDefaults.standard.set(true, forKey: hasCompletedFirstSessionKey)
            UserDefaults.standard.set(true, forKey: hasSeenIntroKey)
        }
    }

    static func prepareForImmediateFirstSession() {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.hasLaunchedBefore)
        UserDefaults.standard.set(true, forKey: hasSeenIntroKey)
        PBASessionFlowPolicy.persistTrainingMode(.solo)
    }

    /// Call when the first Meet the Ball session finishes. Returns `true` only once.
    @discardableResult
    static func markFirstSessionCompletedIfNeeded() -> Bool {
        migrateExistingInstallsIfNeeded()
        guard !hasCompletedFirstSession else { return false }
        UserDefaults.standard.set(true, forKey: hasCompletedFirstSessionKey)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.hasLaunchedBefore)
        UserDefaults.standard.set(true, forKey: hasSeenIntroKey)
        return true
    }

    static func recordLoginPromptPresented(on date: Date = Date()) {
        UserDefaults.standard.set(calendarDayString(for: date), forKey: lastLoginPromptDayKey)
    }

    static func recordLoginPromptDeclined(on date: Date = Date()) {
        UserDefaults.standard.set(calendarDayString(for: date), forKey: loginPromptDeclinedDayKey)
        recordLoginPromptPresented(on: date)
    }

    /// Later-day return prompt (not the immediate post-first-session overlay).
    static func shouldShowReturnDayLoginPrompt(
        isAuthenticated: Bool,
        loginPromptShownThisSession: Bool
    ) -> Bool {
        guard hasCompletedFirstSession, !isAuthenticated, !loginPromptShownThisSession else { return false }
        let today = calendarDayString(for: Date())
        let lastPrompt = UserDefaults.standard.string(forKey: lastLoginPromptDayKey)
        return lastPrompt != today
    }

    static func shouldPromptLoginBeforeProgress(
        isAuthenticated: Bool,
        loginPromptShownThisSession: Bool
    ) -> Bool {
        guard hasCompletedFirstSession, !isAuthenticated, !loginPromptShownThisSession else { return false }
        return true
    }

    private static func calendarDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
