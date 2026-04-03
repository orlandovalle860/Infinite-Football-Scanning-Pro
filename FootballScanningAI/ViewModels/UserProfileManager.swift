import Foundation
import SwiftUI
import Combine

/// Describes a new personal best for the celebration banner.
enum NewPersonalBest {
    case decisionSpeed(previous: Double?, new: Double)
    case pressureEscape(previous: Double?, new: Double)
    case forwardIntent(previous: Double?, new: Double)

    var title: String {
        switch self {
        case .decisionSpeed: return "Decision Speed improved"
        case .pressureEscape: return "Away-from-pressure accuracy improved"
        case .forwardIntent: return "Forward Thinking improved"
        }
    }

    var improvementText: String {
        switch self {
        case .decisionSpeed(let prev, let new):
            let a = prev.map { String(format: "%.2fs", $0) } ?? "—"
            return "\(a) → \(String(format: "%.2fs", new))"
        case .pressureEscape(let prev, let new):
            let a = prev.map { String(format: "%.0f%%", $0) } ?? "—"
            return "\(a) → \(String(format: "%.0f%%", new))"
        case .forwardIntent(let prev, let new):
            let a = prev.map { String(format: "%.0f%%", $0) } ?? "—"
            return "\(a) → \(String(format: "%.0f%%", new))"
        }
    }
}

struct SessionRewards {
    let newPersonalBests: [NewPersonalBest]
    let xpEarned: Int
    let totalXP: Int
    let newlyUnlockedBadges: [PlayerBadge]
}

class UserProfileManager: ObservableObject {
    @Published var profiles: [UserProfile] = []
    @Published var currentProfile: UserProfile?
    @Published var isProfileCreated: Bool = false
    
    // Temporary storage for current session settings
    private var currentSessionSettings: TrainingSessionSettings?
    
    private let userDefaults = UserDefaults.standard
    private let profilesKey = "userProfiles"
    private let currentProfileIdKey = "currentProfileId"
    private let isProfileCreatedKey = "isProfileCreated"
    private let pendingBadgeUnlocksKeyPrefix = "pending_badge_unlocks"
    
    init() {
        loadProfiles()
    }
    
    // MARK: - Profile Management
    
    func createProfile(name: String, email: String? = nil) {
        let newProfile = UserProfile(name: name, email: email)
        profiles.append(newProfile)
        currentProfile = newProfile
        isProfileCreated = true
        saveProfiles()
        SupabasePlayerService.shared.syncPlayer(newProfile)
    }
    
    func addProfile(name: String, email: String? = nil) {
        let newProfile = UserProfile(name: name, email: email)
        profiles.append(newProfile)
        saveProfiles()
        SupabasePlayerService.shared.syncPlayer(newProfile)
    }

    /// Add a new player (optional age, team, position) without switching to them. Returns the new profile.
    @discardableResult
    func addProfile(name: String, email: String? = nil, age: String? = nil, team: String? = nil, position: String? = nil) -> UserProfile {
        let newProfile = UserProfile(name: name, email: email, age: age, team: team, position: position)
        profiles.append(newProfile)
        saveProfiles()
        SupabasePlayerService.shared.syncPlayer(newProfile)
        return newProfile
    }

    /// Add a profile with a specific id (e.g. after inserting into Supabase from CreatePlayerAfterAuthView). Does not sync to Supabase.
    func addProfileWithId(_ id: UUID, name: String) {
        let newProfile = UserProfile(id: id, name: name)
        profiles.append(newProfile)
        currentProfile = newProfile
        isProfileCreated = true
        saveProfiles()
    }

    /// Add a profile by id without making it current (e.g. when hydrating from Supabase). Does not sync to Supabase.
    func addProfileById(_ id: UUID, name: String) {
        let newProfile = UserProfile(id: id, name: name)
        profiles.append(newProfile)
        saveProfiles()
    }

    /// Create profile (e.g. after 2-Minute Test) with optional age, team, position and cached test result.
    func createProfile(name: String, email: String? = nil, age: String? = nil, team: String? = nil, position: String? = nil, decisionScore: Int? = nil, status: String? = nil, consistency: String? = nil) {
        let newProfile = UserProfile(
            name: name,
            email: email,
            age: age,
            team: team,
            position: position,
            decisionScore: decisionScore,
            status: status,
            consistency: consistency
        )
        profiles.append(newProfile)
        currentProfile = newProfile
        isProfileCreated = true
        saveProfiles()
        SupabasePlayerService.shared.syncPlayer(newProfile)
    }
    
    func switchToProfile(_ profile: UserProfile) {
        currentProfile = profile
        isProfileCreated = true
        saveProfiles()
    }

    func profile(id: UUID?) -> UserProfile? {
        guard let id else { return nil }
        return profiles.first(where: { $0.id == id })
    }
    
    func updateProfile(_ profile: UserProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            if currentProfile?.id == profile.id {
                currentProfile = profile
            }
            saveProfiles()
        }
    }
    
    /// Adds the session result, updates personal bests, and applies simple XP rewards.
    @discardableResult
    func addSessionResult(_ result: SessionResult) -> SessionRewards {
        guard let index = profiles.firstIndex(where: { $0.id == result.playerID }) else {
            return SessionRewards(newPersonalBests: [], xpEarned: 0, totalXP: 0, newlyUnlockedBadges: [])
        }
        var profile = profiles[index]
        var newBests: [NewPersonalBest] = []
        let progressBefore = GuidedCurriculumEngine.currentProgress(playerId: result.playerID)
        let isFirstSessionToday = isFirstSessionOfDay(for: profile, at: result.date)

        // Decision speed (any block with avg time; lower is better)
        if let current = result.avgDecisionTime {
            let previous = profile.fastestDecisionSpeedSeconds
            if previous == nil || current < previous! {
                let oldVal = previous
                profile.fastestDecisionSpeedSeconds = current
                newBests.append(.decisionSpeed(previous: oldVal, new: current))
            }
        }

        // Away-from-pressure first-decision accuracy (AFP only; higher % is better)
        if result.activityType == .awayFromPressure, result.totalReps > 0 {
            let current = Double(result.correctCount) / Double(result.totalReps) * 100.0
            let previous = profile.bestPressureEscapePercent
            if previous == nil || current > previous! {
                let oldVal = previous
                profile.bestPressureEscapePercent = current
                newBests.append(.pressureEscape(previous: oldVal, new: current))
            }
        }

        // Forward intent (Dribble or Pass or One-Touch Passing; higher % is better; only when forward option was available)
        if (result.activityType == .dribbleOrPass || result.activityType == .oneTouchPassing),
           let opp = result.forwardOpportunityCount, opp > 0, let choice = result.forwardChoiceCount {
            let current = Double(choice) / Double(opp) * 100.0
            let previous = profile.bestForwardIntentPercent
            if previous == nil || current > previous! {
                let oldVal = previous
                profile.bestForwardIntentPercent = current
                newBests.append(.forwardIntent(previous: oldVal, new: current))
            }
        }

        profile.sessionResults.insert(result, at: 0)
        // Keep guided curriculum stage current immediately after each scored session save.
        let progressAfter = GuidedCurriculumEngine.evaluateAndAdvance(playerId: result.playerID, sessions: profile.sessionResults)
        profile.updatePersonalBest(session: result)
        let newlyUnlockedBadges = unlockBadges(for: result, profile: &profile)
        enqueuePendingBadgeUnlocks(playerId: result.playerID, badges: newlyUnlockedBadges)
        let xpEarned = xpEarnedForSession(
            result: result,
            hasNewPersonalBest: !newBests.isEmpty,
            isStageProgression: didProgressStage(before: progressBefore, after: progressAfter),
            isFirstSessionToday: isFirstSessionToday
        )
        profile.totalXP += xpEarned
        profiles[index] = profile
        updateWeeklyStreakAfterBlock(profileIndex: index, sessionDate: result.date)
        if currentProfile?.id == result.playerID {
            currentProfile = profiles[index]
        }
        saveProfiles()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .coachingTrainingNudgesShouldRefresh, object: nil)
        }
        return SessionRewards(
            newPersonalBests: newBests,
            xpEarned: xpEarned,
            totalXP: profile.totalXP,
            newlyUnlockedBadges: newlyUnlockedBadges
        )
    }

    /// Merges session rows loaded from Supabase after login (no XP, badges, or curriculum side effects).
    @discardableResult
    func mergeHydratedSessionResults(_ newResults: [SessionResult], forPlayerId playerId: UUID) -> Int {
        guard let index = profiles.firstIndex(where: { $0.id == playerId }) else { return 0 }
        var profile = profiles[index]
        let existingIds = Set(profile.sessionResults.map(\.id))
        let toAdd = newResults.filter { !existingIds.contains($0.id) }
        guard !toAdd.isEmpty else { return 0 }
        for r in toAdd.sorted(by: { $0.date < $1.date }) {
            profile.sessionResults.insert(r, at: 0)
        }
        profiles[index] = profile
        if currentProfile?.id == playerId {
            currentProfile = profile
        }
        saveProfiles()
        return toAdd.count
    }

    private func unlockBadges(for result: SessionResult, profile: inout UserProfile) -> [PlayerBadge] {
        var unlockedNow: [PlayerBadge] = []
        var unlockedSet = Set(profile.unlockedBadges)

        func unlock(_ badge: PlayerBadge) {
            if !unlockedSet.contains(badge) {
                unlockedSet.insert(badge)
                unlockedNow.append(badge)
            }
        }

        // 1) Early Decider: Avg Decision Time < 0.90s in a session.
        if let avg = result.avgDecisionTime, avg < 0.90 {
            unlock(.earlyDecider)
        }
        // 2) Forward Thinker: Forward Thinking >= 60% when opportunities exist.
        if let opp = result.forwardOpportunityCount, opp > 0, let choice = result.forwardChoiceCount,
           Double(choice) / Double(opp) >= 0.60 {
            unlock(.forwardThinker)
        }
        // 3) Consistent: 3 sessions in a row with accuracy >= 80% and decision speed not Too Late.
        let training = profile.sessionResults.filter {
            [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType)
        }
        if training.count >= 3 {
            let lastThree = Array(training.prefix(3))
            let allStrong = lastThree.allSatisfy { session in
                guard session.totalReps > 0 else { return false }
                let accuracy = Double(session.correctCount) / Double(session.totalReps)
                let notTooLate = (session.avgDecisionTime ?? .greatestFiniteMagnitude) <= 1.20
                return accuracy >= 0.80 && notTooLate
            }
            if allStrong {
                unlock(.consistent)
            }
        }

        profile.unlockedBadges = Array(unlockedSet)
        return unlockedNow
    }

    func dequeuePendingBadgeUnlock(playerId: UUID?) -> PlayerBadge? {
        var pending = loadPendingBadgeUnlocks(playerId: playerId)
        guard !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        savePendingBadgeUnlocks(pending, playerId: playerId)
        return next
    }

    private func enqueuePendingBadgeUnlocks(playerId: UUID, badges: [PlayerBadge]) {
        guard !badges.isEmpty else { return }
        let displayPriority: [PlayerBadge] = [.consistent, .earlyDecider, .forwardThinker]
        let prioritized = badges.sorted { a, b in
            let ai = displayPriority.firstIndex(of: a) ?? Int.max
            let bi = displayPriority.firstIndex(of: b) ?? Int.max
            return ai < bi
        }
        // Avoid overwhelming users: show only one new badge modal per session.
        let badgesToQueue = Array(prioritized.prefix(1))
        let existing = loadPendingBadgeUnlocks(playerId: playerId)
        var merged = existing
        let existingSet = Set(existing)
        for badge in badgesToQueue where !existingSet.contains(badge) {
            merged.append(badge)
        }
        savePendingBadgeUnlocks(merged, playerId: playerId)
    }

    private func pendingBadgeUnlocksKey(playerId: UUID?) -> String {
        let pid = playerId?.uuidString ?? "global"
        return "\(pendingBadgeUnlocksKeyPrefix)_\(pid)"
    }

    private func loadPendingBadgeUnlocks(playerId: UUID?) -> [PlayerBadge] {
        let key = pendingBadgeUnlocksKey(playerId: playerId)
        guard let data = userDefaults.data(forKey: key),
              let badges = try? JSONDecoder().decode([PlayerBadge].self, from: data) else {
            return []
        }
        return badges
    }

    private func savePendingBadgeUnlocks(_ badges: [PlayerBadge], playerId: UUID?) {
        let key = pendingBadgeUnlocksKey(playerId: playerId)
        if badges.isEmpty {
            userDefaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(badges) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func isFirstSessionOfDay(for profile: UserProfile, at date: Date) -> Bool {
        let cal = Calendar.current
        return !profile.sessionResults.contains { cal.isDate($0.date, inSameDayAs: date) }
    }

    private func didProgressStage(before: GuidedCurriculumProgress, after: GuidedCurriculumProgress) -> Bool {
        return before.stage != after.stage || before.loop != after.loop
    }

    private func xpEarnedForSession(
        result: SessionResult,
        hasNewPersonalBest: Bool,
        isStageProgression: Bool,
        isFirstSessionToday: Bool
    ) -> Int {
        var xp = 0
        // Complete session
        xp += 50
        // Accuracy >= 70%
        if result.totalReps > 0, Double(result.correctCount) / Double(result.totalReps) >= 0.70 {
            xp += 25
        }
        // Fast decisions >= 50%
        let totalSpeedTagged = result.speedCounts.fast + result.speedCounts.medium + result.speedCounts.slow
        if totalSpeedTagged > 0, Double(result.speedCounts.fast) / Double(totalSpeedTagged) >= 0.50 {
            xp += 25
        }
        // New personal best
        if hasNewPersonalBest {
            xp += 50
        }
        // Stage progression
        if isStageProgression {
            xp += 100
        }
        // First session of day
        if isFirstSessionToday {
            xp += 25
        }
        return xp
    }

    /// Monday-based calendar for weekly boundaries (week resets every Monday).
    private static var mondayWeekCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }

    private static func startOfWeekMonday(for date: Date) -> Date? {
        let cal = Self.mondayWeekCalendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps)
    }

    /// Ensures weekly progress is rolled over when a new week (Monday) has started. Call when displaying Home or before reading streak/sessions.
    func ensureWeeklyRolloverIfNeeded() {
        guard let nowWeekStart = Self.startOfWeekMonday(for: Date()) else { return }
        var didChange = false
        for index in profiles.indices {
            var profile = profiles[index]
            guard let lastStart = profile.lastWeekStart, lastStart < nowWeekStart else {
                if profile.lastWeekStart == nil {
                    profile.lastWeekStart = nowWeekStart
                    profiles[index] = profile
                    didChange = true
                }
                continue
            }
            // New week: evaluate last week (1 session = 1 block, 3+ sessions keeps streak).
            if profile.blocksCompletedThisWeek >= 3 {
                profile.currentWeeklyStreak += 1
                profile.longestWeeklyStreak = max(profile.longestWeeklyStreak, profile.currentWeeklyStreak)
            } else {
                profile.currentWeeklyStreak = 0
            }
            profile.blocksCompletedThisWeek = 0
            profile.lastWeekStart = nowWeekStart
            profiles[index] = profile
            didChange = true
        }
        if didChange {
            if let id = currentProfile?.id, let idx = profiles.firstIndex(where: { $0.id == id }) {
                currentProfile = profiles[idx]
            }
            saveProfiles()
        }
    }

    /// Weekly streak: 1 session = 1 block (36 decisions). 3+ sessions in a week keeps/extends streak. Call after adding a block (SessionResult).
    private func updateWeeklyStreakAfterBlock(profileIndex: Int, sessionDate: Date) {
        guard let weekStart = Self.startOfWeekMonday(for: sessionDate) else { return }
        var profile = profiles[profileIndex]
        if let lastStart = profile.lastWeekStart, lastStart < weekStart {
            if profile.blocksCompletedThisWeek >= 3 {
                profile.currentWeeklyStreak += 1
                profile.longestWeeklyStreak = max(profile.longestWeeklyStreak, profile.currentWeeklyStreak)
            } else {
                profile.currentWeeklyStreak = 0
            }
            profile.blocksCompletedThisWeek = 0
            profile.lastWeekStart = weekStart
        } else if profile.lastWeekStart == nil {
            profile.lastWeekStart = weekStart
        }
        profile.blocksCompletedThisWeek += 1
        profile.lastSessionDate = sessionDate
        profiles[profileIndex] = profile
    }

    /// Current consecutive weeks with 3+ sessions (1 session = 1 full block). Call ensureWeeklyRolloverIfNeeded() when Home appears so streak is up to date.
    func currentWeeklyStreak() -> Int {
        guard let profile = currentProfile else { return 0 }
        return profile.currentWeeklyStreak
    }

    /// Longest ever consecutive weeks with 3+ sessions.
    func longestWeeklyStreak() -> Int {
        guard let profile = currentProfile else { return 0 }
        return profile.longestWeeklyStreak
    }

    /// Sessions completed this week (1 session = 1 full training block, 36 decisions). Resets every Monday. Call ensureWeeklyRolloverIfNeeded() when Home appears.
    func sessionsCompletedThisWeek() -> Int {
        guard let profile = currentProfile else { return 0 }
        guard let nowWeekStart = Self.startOfWeekMonday(for: Date()),
              let lastStart = profile.lastWeekStart, lastStart == nowWeekStart else { return 0 }
        return profile.blocksCompletedThisWeek
    }

    /// Returns true if this session would beat (or set) the current personal best for the activity. Call before addSessionResult to know if we should show "New Personal Best".
    func wouldBeNewPersonalBest(session: SessionResult) -> Bool {
        guard let profile = profiles.first(where: { $0.id == session.playerID }) else { return false }
        let current = profile.personalBests[session.activityType]?.bestCorrect ?? 0
        return session.correctCount > current
    }

    func fastestDecisionSpeedSeconds() -> Double? { currentProfile?.fastestDecisionSpeedSeconds }
    func bestPressureEscapePercent() -> Double? { currentProfile?.bestPressureEscapePercent }
    func bestForwardIntentPercent() -> Double? { currentProfile?.bestForwardIntentPercent }

    func isPremiumActive(playerId: UUID?) -> Bool {
#if DEBUG
        return true
#else
        let pid = playerId ?? currentProfile?.id
        guard let pid else { return false }
        return profiles.first(where: { $0.id == pid })?.isPremium ?? false
#endif
    }

    func upgradeToPremium(playerId: UUID?) {
        let pid = playerId ?? currentProfile?.id
        guard let pid, let index = profiles.firstIndex(where: { $0.id == pid }) else { return }
        profiles[index].isPremium = true
        if currentProfile?.id == pid {
            currentProfile = profiles[index]
        }
        saveProfiles()
    }

    // MARK: - Player Progress (report card)

    /// Most recent train sessions (blocks/tests) for the active profile, newest first.
    func recentTrainSessions(limit: Int = 5) -> [SessionResult] {
        guard let profile = currentProfile else { return [] }
        return Array(profile.sessionResults.prefix(limit))
    }

    /// All session results for the current profile, sorted by date ascending (oldest first) for charts.
    func sessionResultsForCharts() -> [SessionResult] {
        guard let profile = currentProfile else { return [] }
        return profile.sessionResults.sorted { $0.date < $1.date }
    }

    /// Aggregate speed counts from sessions.
    static func speedCounts(from sessions: [SessionResult]) -> (fast: Int, medium: Int, slow: Int) {
        var f = 0, m = 0, s = 0
        for session in sessions {
            f += session.speedCounts.fast
            m += session.speedCounts.medium
            s += session.speedCounts.slow
        }
        return (f, m, s)
    }

    /// Consecutive calendar days with at least one train session, counting backward from today. Stops at first day with no session.
    func trainingStreakDays() -> Int {
        guard let profile = currentProfile else { return 0 }
        let cal = Calendar.current
        let daysWithSession = Set(profile.sessionResults.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var check = cal.startOfDay(for: Date())
        while daysWithSession.contains(check) {
            streak += 1
            check = cal.date(byAdding: .day, value: -1, to: check) ?? check
        }
        return streak
    }

    /// 2–3 sentence coach insight from recent sessions.
    func coachInsightForProgress(sessions: [SessionResult]) -> String {
        if sessions.count < 2 {
            return "Complete 2–3 blocks to unlock personalized feedback."
        }
        let recent = Array(sessions.prefix(5))
        let (fast, medium, slow) = Self.speedCounts(from: recent)
        let total = fast + medium + slow
        let slowPct = total > 0 ? Double(slow) / Double(total) : 0
        let firstCorrect = recent.first?.correctCount ?? 0
        let lastCorrect = recent.last?.correctCount ?? 0
        let accuracyImproving = recent.count >= 2 && lastCorrect > firstCorrect

        var sentences: [String] = []

        if accuracyImproving && slowPct >= 0.4 {
            sentences.append("Your decisions are correct more often, but sometimes late. Focus on scanning earlier before the ball arrives.")
        } else if total > 0 && fast > slow && recent.count >= 2 {
            sentences.append("You're deciding earlier. Keep building that habit on the critical scan before receiving.")
        }

        if let biasSession = recent.first(where: { $0.biasDirection != nil }),
           let dir = biasSession.biasDirection {
            let direction = ["up": "up", "down": "down", "left": "left", "right": "right"][dir.rawValue] ?? dir.rawValue
            sentences.append("You favor the \(direction) side. Challenge yourself to scan both shoulders and use the whole field.")
        }

        if sentences.isEmpty {
            sentences.append("Keep training. Consistency will show up in your next report.")
        }
        return sentences.prefix(2).joined(separator: " ")
    }

    /// Clears current profile selection and any in-flight training session settings (Switch Player). Does not remove profiles or sign out.
    func clearCurrentSelectionForSwitchPlayer() {
        currentSessionSettings = nil
        currentProfile = nil
        if !profiles.isEmpty {
            isProfileCreated = true
        }
        saveProfiles()
    }

    /// Clears all profiles and persisted keys (account sign-out). Does not delete remote Supabase players.
    func clearAllForSignOut() {
        profiles = []
        currentProfile = nil
        isProfileCreated = false
        saveProfiles()
    }

    func deleteProfile(_ profile: UserProfile) {
        profiles.removeAll { $0.id == profile.id }
        
        // If we're deleting the current profile, switch to another one or clear
        if currentProfile?.id == profile.id {
            if let firstProfile = profiles.first {
                currentProfile = firstProfile
            } else {
                currentProfile = nil
                isProfileCreated = false
            }
        }
        
        saveProfiles()
    }
    
    func getProfile(by id: UUID) -> UserProfile? {
        return profiles.first { $0.id == id }
    }
    
    func getProfilesCount() -> Int {
        return profiles.count
    }
    
    func hasMultipleProfiles() -> Bool {
        return profiles.count > 1
    }
    
    // MARK: - Training Session Management
    
    func startTrainingSession(settings: TrainingSessionSettings) {
        guard var profile = currentProfile else { return }
        
        // Update last active
        profile.lastActive = Date()
        
        // Store current session settings temporarily
        currentSessionSettings = settings
        
        updateProfile(profile)
    }
    
    func endTrainingSession(duration: TimeInterval) {
        guard var profile = currentProfile,
              let settings = currentSessionSettings else { return }
        
        // Convert colors to hex strings
        let colorsUsedHex = settings.colorsUsed.map { $0.toHex() }
        let numberColorHex = settings.numberColor.toHex()
        let arrowColorHex = settings.arrowColor.toHex()
        
        // Create training session record
        let session = TrainingSession(
            displayMode: settings.displayMode,
            colorsUsed: colorsUsedHex,
            numbersUsed: settings.numbersUsed,
            arrowsUsed: settings.arrowsUsed,
            lanesUsed: settings.lanesUsed,
            beepInterval: settings.beepInterval,
            numberColor: numberColorHex,
            arrowColor: arrowColorHex,
            colorSet: settings.colorSet,
            actionSet: settings.actionSet,
            customActions: settings.customActions,
            criticalScanDelay: settings.criticalScanDelay,
            criticalScanDuration: settings.criticalScanDuration,
            criticalScanResetTime: settings.criticalScanResetTime,
            screenProtectionEnabled: settings.screenProtectionEnabled,
            soundEnabled: settings.soundEnabled,
            duration: duration
        )
        
        // Add to training history
        profile.trainingSessions.append(session)
        
        // Update statistics
        profile.totalSessions += 1
        profile.totalTrainingTime += duration
        
        if duration > profile.longestSession {
            profile.longestSession = duration
        }
        
        // Calculate average session length
        if profile.totalSessions > 0 {
            profile.averageSessionLength = profile.totalTrainingTime / Double(profile.totalSessions)
        }
        
        // Update weekly and monthly counts
        updateSessionCounts(&profile)
        
        // Clear current session settings
        currentSessionSettings = nil
        
        updateProfile(profile)
    }
    
    // MARK: - Statistics
    
    func getWeeklyStats() -> (sessions: Int, totalTime: TimeInterval) {
        guard let profile = currentProfile else { return (0, 0) }
        
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        
        let weeklySessions = profile.trainingSessions.filter { session in
            session.date >= weekAgo
        }
        
        let totalTime = weeklySessions.reduce(0) { $0 + $1.duration }
        return (weeklySessions.count, totalTime)
    }
    
    func getMonthlyStats() -> (sessions: Int, totalTime: TimeInterval) {
        guard let profile = currentProfile else { return (0, 0) }
        
        let calendar = Calendar.current
        let now = Date()
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        
        let monthlySessions = profile.trainingSessions.filter { session in
            session.date >= monthAgo
        }
        
        let totalTime = monthlySessions.reduce(0) { $0 + $1.duration }
        return (monthlySessions.count, totalTime)
    }
    
    func getRecentSessions(limit: Int = 10) -> [TrainingSession] {
        guard let profile = currentProfile else { return [] }
        
        return Array(profile.trainingSessions.sorted { $0.date > $1.date }.prefix(limit))
    }
    
    // MARK: - Family Management
    
    func getFamilyStats() -> FamilyStats {
        let totalSessions = profiles.reduce(0) { $0 + $1.totalSessions }
        let totalTrainingTime = profiles.reduce(0) { $0 + $1.totalTrainingTime }
        let totalProfiles = profiles.count
        
        return FamilyStats(
            totalAthletes: totalProfiles,
            totalSessions: totalSessions,
            totalTrainingTime: totalTrainingTime,
            profiles: profiles
        )
    }
    
    // MARK: - Private Methods
    
    private func updateSessionCounts(_ profile: inout UserProfile) {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        
        let weeklySessions = profile.trainingSessions.filter { $0.date >= weekAgo }
        let monthlySessions = profile.trainingSessions.filter { $0.date >= monthAgo }
        
        profile.sessionsThisWeek = weeklySessions.count
        profile.sessionsThisMonth = monthlySessions.count
    }
    
    func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            userDefaults.set(encoded, forKey: profilesKey)
        }
        
        if let currentProfile = currentProfile {
            userDefaults.set(currentProfile.id.uuidString, forKey: currentProfileIdKey)
        } else {
            userDefaults.removeObject(forKey: currentProfileIdKey)
        }
        
        userDefaults.set(isProfileCreated, forKey: isProfileCreatedKey)
    }
    
    private func loadProfiles() {
        // Load all profiles
        if let data = userDefaults.data(forKey: profilesKey),
           let loadedProfiles = try? JSONDecoder().decode([UserProfile].self, from: data) {
            profiles = loadedProfiles
        } else {
            profiles = []
        }
        
        // Load current profile: only use stored id if it exists in loaded profiles
        if let currentProfileIdString = userDefaults.string(forKey: currentProfileIdKey),
           let currentProfileId = UUID(uuidString: currentProfileIdString),
           let profile = profiles.first(where: { $0.id == currentProfileId }) {
            currentProfile = profile
            isProfileCreated = true
        } else if let firstProfile = profiles.first {
            currentProfile = firstProfile
            isProfileCreated = true
        } else {
            currentProfile = nil
            isProfileCreated = false
        }

#if DEBUG
        ProfileLoadSourceLog.loadedFromDisk(profileCount: profiles.count)
#endif
    }
}

// MARK: - Supporting Types

struct TrainingSessionSettings {
    let displayMode: DisplayMode
    let colorsUsed: [Color]
    let numbersUsed: [Int]
    let arrowsUsed: [String]
    let lanesUsed: [String]
    let beepInterval: BeepInterval
    let numberColor: Color
    let arrowColor: Color
    let colorSet: ScanningColorSet
    let actionSet: ActionSet
    let customActions: [CustomAction]
    let criticalScanDelay: Double
    let criticalScanDuration: Double
    let criticalScanResetTime: Double
    let screenProtectionEnabled: Bool
    let soundEnabled: Bool
}

struct FamilyStats {
    let totalAthletes: Int
    let totalSessions: Int
    let totalTrainingTime: TimeInterval
    let profiles: [UserProfile]
    
    var averageSessionsPerAthlete: Double {
        guard totalAthletes > 0 else { return 0 }
        return Double(totalSessions) / Double(totalAthletes)
    }
    
    var averageTrainingTimePerAthlete: TimeInterval {
        guard totalAthletes > 0 else { return 0 }
        return totalTrainingTime / Double(totalAthletes)
    }
}
