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
    /// After sign-out / account delete: allow the first-session login prompt again; blocks legacy migration from re-marking complete.
    private static let reenableFirstSessionLoginPromptKey = "pba.reenableFirstSessionLoginPrompt"
    private static let lastLoginPromptDayKey = "pba.lastLoginPromptDay"
    private static let loginPromptDeclinedDayKey = "pba.loginPromptDeclinedDay"
    /// Set when the first session ends with a feedback overlay; login fires on overlay Done.
    private static var pendingLoginPromptAfterFeedback = false

    static let meaningfulSessionMinReps = 5
    static let meaningfulSessionMinElapsedSeconds: TimeInterval = 15

    static func isMeaningfulSession(repCount: Int, elapsedSeconds: TimeInterval) -> Bool {
        repCount >= meaningfulSessionMinReps || elapsedSeconds >= meaningfulSessionMinElapsedSeconds
    }

    static var hasCompletedFirstSession: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedFirstSessionKey)
    }

    /// Call on sign-out / account delete so a guest can be asked to Sign in with Apple again after the next meaningful session.
    static func resetLoginPromptEligibilityAfterSignOut() {
        pendingLoginPromptAfterFeedback = false
        UserDefaults.standard.set(false, forKey: hasCompletedFirstSessionKey)
        UserDefaults.standard.set(true, forKey: reenableFirstSessionLoginPromptKey)
        UserDefaults.standard.removeObject(forKey: lastLoginPromptDayKey)
        UserDefaults.standard.removeObject(forKey: loginPromptDeclinedDayKey)
        print("[SignOut-Debug] first-session login prompt eligibility reset")
    }

    private static var shouldSkipLegacyFirstSessionMigration: Bool {
        UserDefaults.standard.bool(forKey: reenableFirstSessionLoginPromptKey)
    }

    private static func clearReenableFirstSessionLoginPromptFlag() {
        UserDefaults.standard.removeObject(forKey: reenableFirstSessionLoginPromptKey)
    }

    /// Records the first completed training session for any activity.
    /// - Parameter deferLoginUntilFeedbackDismissed: `true` when post-session feedback overlay will show first.
    /// - Returns: `true` only the first time a meaningful session completes.
    @discardableResult
    static func noteTrainingSessionCompleted(
        deferLoginUntilFeedbackDismissed: Bool,
        repCount: Int,
        elapsedSeconds: TimeInterval
    ) -> Bool {
        migrateExistingInstallsIfNeeded()
        guard isMeaningfulSession(repCount: repCount, elapsedSeconds: elapsedSeconds) else { return false }
        guard markFirstSessionCompletedIfNeeded() else { return false }
        AuthFlowOnboardingSync.markLocalBaselineCompleted()
        if deferLoginUntilFeedbackDismissed {
            pendingLoginPromptAfterFeedback = true
        } else {
            requestFirstSessionLoginPromptIfNeeded()
        }
        return true
    }

    /// Call from shared solo feedback overlay Done, after navigation home.
    static func requestLoginPromptAfterFeedbackIfPending() {
        guard pendingLoginPromptAfterFeedback else { return }
        pendingLoginPromptAfterFeedback = false
        requestFirstSessionLoginPromptIfNeeded()
    }

    static func requestFirstSessionLoginPromptIfNeeded() {
        guard AuthManager.shared.currentSession == nil else { return }
        NotificationCenter.default.post(name: .firstSessionTrainingCompleted, object: nil)
    }

    /// Call when presenting solo timed feedback overlay.
    static func prepareLoginPromptAfterSoloTimedSessionIfNeeded(repCount: Int, elapsedSeconds: TimeInterval) {
        _ = noteTrainingSessionCompleted(
            deferLoginUntilFeedbackDismissed: true,
            repCount: repCount,
            elapsedSeconds: elapsedSeconds
        )
    }

    /// Standard solo feedback dismiss: clear session state, go home, then deferred login if needed.
    static func completeSoloTimedFeedbackDismiss(
        clearSession: () -> Void,
        dismissOverlay: () -> Void,
        popToRoot: () -> Void
    ) {
        clearSession()
        dismissOverlay()
        popToRoot()
        requestLoginPromptAfterFeedbackIfPending()
    }

    /// Welcome screen is no longer shown at launch — users land on Home directly.
    static func shouldShowWelcomeScreen(isCoachRemoteRole: Bool) -> Bool {
        _ = isCoachRemoteRole
        return false
    }

    /// Existing installs: skip the new welcome funnel.
    static func migrateExistingInstallsIfNeeded() {
        guard !hasCompletedFirstSession else { return }
        // After sign-out/delete we intentionally cleared first-session state — do not re-mark via legacy keys.
        guard !shouldSkipLegacyFirstSessionMigration else { return }
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

    /// Marks first session complete in storage. Prefer ``noteTrainingSessionCompleted(deferLoginUntilFeedbackDismissed:)`` at session end.
    @discardableResult
    static func markFirstSessionCompletedIfNeeded() -> Bool {
        migrateExistingInstallsIfNeeded()
        guard !hasCompletedFirstSession else { return false }
        UserDefaults.standard.set(true, forKey: hasCompletedFirstSessionKey)
        UserDefaults.standard.set(true, forKey: AppStorageKeys.hasLaunchedBefore)
        UserDefaults.standard.set(true, forKey: hasSeenIntroKey)
        clearReenableFirstSessionLoginPromptFlag()
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
