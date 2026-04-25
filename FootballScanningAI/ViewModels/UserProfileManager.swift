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

    /// Applied when starting the next block from Session Summary → “Start Recommended” (cleared after use in setup).
    @Published var pendingLevelDifficulty: DifficultySettings?
    
    private let userDefaults = UserDefaults.standard
    private let profilesKey = "userProfiles"
    private let currentProfileIdKey = "currentProfileId"
    private let isProfileCreatedKey = "isProfileCreated"
    private let pendingBadgeUnlocksKeyPrefix = "pending_badge_unlocks"
    private let pendingBadgeTierUnlocksKeyPrefix = "pending_badge_tier_unlocks"
    
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

        let stageBeforeProgression = profile.currentStage
        profile.sessionResults.insert(result, at: 0)
        applyAdaptiveTrainingState(for: result, profile: &profile)
        let didAdvance = evaluateProgressionAfterSession(result: result, profile: &profile)
        if result.activityType == stageBeforeProgression.activity {
            profile.lastStageRecommendation = StageSessionRecommendationEngine.make(
                didAdvance: didAdvance,
                stageAfterProgression: profile.currentStage,
                result: result
            )
        }
        PlayerFeedbackEngine.logFeedbackDebug(for: result)
        // Keep guided curriculum stage current immediately after each scored session save.
        let progressAfter = GuidedCurriculumEngine.evaluateAndAdvance(playerId: result.playerID, sessions: profile.sessionResults)
        profile.sessionStreakCount += 1
        profile.longestSessionStreak = max(profile.longestSessionStreak, profile.sessionStreakCount)
        profile.updatePersonalBest(session: result)
        let badgeTierLevelUps = evaluateBadgeTierLevelUps(for: result, profile: &profile)
        profile.lastBadgeTierUnlocked = badgeTierLevelUps.first
        profile.lastUnlockedBadge = badgeTierLevelUps.first.map(playerBadgeForTrackLevel)
        let newlyUnlockedBadges = badgeTierLevelUps.map(playerBadgeForTrackLevel)
        profile.unlockedBadges = mergeUnlockedBadges(existing: profile.unlockedBadges, newBadges: newlyUnlockedBadges)
        enqueuePendingBadgeTierUnlocks(playerId: result.playerID, events: badgeTierLevelUps)
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
        EarlySessionStreakStore.updateAfterSession(result)
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

    @discardableResult
    private func evaluateProgressionAfterSession(result: SessionResult, profile: inout UserProfile) -> Bool {
        let stage = profile.currentStage
        let stageActivity = stage.activity
        guard result.activityType == stageActivity else { return false }

        let accuracy = result.totalReps > 0 ? Double(result.correctCount) / Double(result.totalReps) : 0
        let score = result.decisionTotalScore ?? Double(result.estimatedDecisionSpeedScore ?? Int((accuracy * 100).rounded()))

        var history = profile.stageHistory[stage] ?? []
        history.append(
            PlayerStageSessionResult(
                score: score,
                accuracy: accuracy,
                activityType: result.activityType,
                timestamp: result.date
            )
        )
        profile.stageHistory[stage] = history

        let lastThree = Array(history.suffix(3))
        let last3Scores = lastThree.map(\.score)
        let last3Accuracy = lastThree.map(\.accuracy)
        let avgScore = last3Scores.isEmpty ? 0 : (last3Scores.reduce(0, +) / Double(last3Scores.count))
        let avgAccuracy = last3Accuracy.isEmpty ? 0 : (last3Accuracy.reduce(0, +) / Double(last3Accuracy.count))

        let shouldAdvance = lastThree.count == 3 && avgScore >= 75 && avgAccuracy >= 0.70
        let decision = shouldAdvance ? "advance" : "stay"

        print("[ProgressionDebug] playerId=\(result.playerID.uuidString) currentStage=\(stage.rawValue) last3Scores=\(last3Scores) last3Accuracy=\(last3Accuracy) decision=\(decision)")

        guard shouldAdvance, let next = stage.next else { return false }
        profile.currentStage = next
        profile.stageHistory[next] = []
        return true
    }

    private struct AdaptiveSessionSnapshot {
        let score: Int
        let earlyPercentage: Double
        let latePercentage: Double
        let averageDecisionOffset: Double
    }

    private func applyAdaptiveTrainingState(for latestResult: SessionResult, profile: inout UserProfile) {
        let snapshots = profile.sessionResults
            .sorted(by: { $0.date > $1.date })
            .prefix(5)
            .map(makeAdaptiveSnapshot)

        guard !snapshots.isEmpty else { return }

        let recentScores = snapshots.map(\.score)
        let latest = snapshots[0]
        let currentTempo = profile.adaptiveTrainingState.currentTempo
        let currentLevel = adaptiveLevelFromScore(latest.score)

        let latestTwo = Array(snapshots.prefix(2))
        let hasTwoStrongSessions = latestTwo.count == 2 && latestTwo.allSatisfy {
            $0.score >= 85 && $0.earlyPercentage >= 0.4
        }
        let hasTwoLowSessions = latestTwo.count == 2 && latestTwo.allSatisfy { $0.score < 70 }

        let nextTempo: PassTempo
        let recommendation: String
        let focus: String

        if hasTwoStrongSessions {
            nextTempo = raiseTempo(from: currentTempo)
            recommendation = "You’re ready for Game Speed"
            focus = "increase challenge"
        } else if (70...84).contains(latest.score) {
            nextTempo = currentTempo
            recommendation = "Stay here and push for earlier decisions"
            focus = "commit earlier"
        } else if latest.score < 70 && hasTwoLowSessions {
            nextTempo = lowerTempo(from: currentTempo)
            recommendation = "Slow it down and focus on early decisions"
            focus = "decide earlier"
        } else if latest.score < 70 {
            nextTempo = currentTempo
            recommendation = "Stay here and push for earlier decisions"
            focus = "decide earlier"
        } else {
            nextTempo = currentTempo
            recommendation = "Stay here and push for earlier decisions"
            focus = "commit earlier"
        }

        profile.adaptiveTrainingState = AdaptiveTrainingState(
            currentTempo: nextTempo,
            currentLevel: currentLevel,
            recentScores: recentScores,
            recommendation: recommendation,
            focus: focus
        )
    }

    private func makeAdaptiveSnapshot(from session: SessionResult) -> AdaptiveSessionSnapshot {
        let score: Int
        if let totalScore = session.decisionTotalScore {
            score = max(0, min(100, Int(totalScore.rounded())))
        } else {
            score = session.estimatedDecisionSpeedScore ?? 0
        }

        let totalTiming = session.speedCounts.fast + session.speedCounts.medium + session.speedCounts.slow
        let earlyPct = totalTiming > 0 ? Double(session.speedCounts.fast) / Double(totalTiming) : 0
        let latePct = totalTiming > 0 ? Double(session.speedCounts.slow) / Double(totalTiming) : 0
        let avgOffset = session.avgDecisionWindowSeconds ?? 0

        return AdaptiveSessionSnapshot(
            score: score,
            earlyPercentage: earlyPct,
            latePercentage: latePct,
            averageDecisionOffset: avgOffset
        )
    }

    private func raiseTempo(from tempo: PassTempo) -> PassTempo {
        switch tempo {
        case .controlled: return .gameSpeed
        case .gameSpeed: return .elite
        case .elite: return .elite
        }
    }

    private func lowerTempo(from tempo: PassTempo) -> PassTempo {
        switch tempo {
        case .controlled: return .controlled
        case .gameSpeed: return .controlled
        case .elite: return .gameSpeed
        }
    }

    private func adaptiveLevelFromScore(_ score: Int) -> SessionPerformanceLevel {
        switch score {
        case ..<60: return .reactive
        case ..<75: return .developing
        case ..<90: return .advancing
        default: return .elite
        }
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

    private func evaluateBadgeTierLevelUps(for result: SessionResult, profile: inout UserProfile) -> [BadgeTierUnlockEvent] {
        let total = result.speedCounts.fast + result.speedCounts.medium + result.speedCounts.slow
        let earlyPct = total > 0 ? Double(result.speedCounts.fast) / Double(total) : 0
        let currentScore = sessionScore(result)
        let previousSession = profile.sessionResults
            .filter { $0.id != result.id }
            .sorted(by: { $0.date > $1.date })
            .first
        let scoreJump = previousSession.map { currentScore - sessionScore($0) } ?? 0

        let currentMetrics: [BadgeTrack: Double] = [
            .earlyThinker: earlyPct,
            .levelUp: Double(scoreJump),
            .lockedIn: Double(result.speedCounts.slow),
            .onFire: Double(profile.sessionStreakCount),
            .aheadOfPlay: Double(currentScore)
        ]

        var levelUps: [BadgeTierUnlockEvent] = []
        for track in BadgeTrack.allCases {
            let oldLevel = profile.badgeTierLevels[track] ?? 0
            let newLevel = tierLevel(for: track, metricValue: currentMetrics[track] ?? 0)
            if newLevel > oldLevel {
                profile.badgeTierLevels[track] = newLevel
                levelUps.append(BadgeTierUnlockEvent(track: track, level: newLevel))
            }
        }
        return levelUps
    }

    private func tierLevel(for track: BadgeTrack, metricValue: Double) -> Int {
        let thresholds: [Double]
        switch track {
        case .earlyThinker:
            thresholds = [0.30, 0.40, 0.50, 0.60]
        case .levelUp:
            thresholds = [10, 15, 20, 25]
        case .lockedIn:
            // Lower late count is better (<=4, <=3, <=2, <=1).
            if metricValue <= 1 { return 4 }
            if metricValue <= 2 { return 3 }
            if metricValue <= 3 { return 2 }
            if metricValue <= 4 { return 1 }
            return 0
        case .onFire:
            thresholds = [3, 5, 10, 20]
        case .aheadOfPlay:
            thresholds = [90, 92, 95, 98]
        }
        var level = 0
        for (index, threshold) in thresholds.enumerated() where metricValue >= threshold {
            level = index + 1
        }
        return level
    }

    private func playerBadgeForTrackLevel(_ event: BadgeTierUnlockEvent) -> PlayerBadge {
        switch event.track {
        case .earlyThinker:
            return .earlyThinker
        case .levelUp:
            return .levelUp
        case .lockedIn:
            return .lockedIn
        case .onFire:
            switch event.level {
            case 4: return .onFire20
            case 3: return .onFire10
            case 2: return .onFire5
            default: return .onFire3
            }
        case .aheadOfPlay:
            return .aheadOfPlay
        }
    }

    private func mergeUnlockedBadges(existing: [PlayerBadge], newBadges: [PlayerBadge]) -> [PlayerBadge] {
        var merged = existing
        var seen = Set(existing)
        for badge in newBadges where !seen.contains(badge) {
            merged.append(badge)
            seen.insert(badge)
        }
        return merged
    }

    private func sessionScore(_ session: SessionResult) -> Int {
        if let s = session.decisionTotalScore {
            return max(0, min(100, Int(s.rounded())))
        }
        if session.totalReps > 0 {
            return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100.0))
        }
        return session.estimatedDecisionSpeedScore ?? 0
    }

    func dequeuePendingBadgeTierUnlock(playerId: UUID?) -> BadgeTierUnlockEvent? {
        var pending = loadPendingBadgeTierUnlocks(playerId: playerId)
        guard !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        savePendingBadgeTierUnlocks(pending, playerId: playerId)
        return next
    }

    private func enqueuePendingBadgeTierUnlocks(playerId: UUID, events: [BadgeTierUnlockEvent]) {
        guard !events.isEmpty else { return }
        let displayPriority: [BadgeTrack] = [.aheadOfPlay, .onFire, .levelUp, .earlyThinker, .lockedIn]
        let prioritized = events.sorted { a, b in
            let ai = displayPriority.firstIndex(of: a.track) ?? Int.max
            let bi = displayPriority.firstIndex(of: b.track) ?? Int.max
            if ai == bi {
                return a.level > b.level
            }
            return ai < bi
        }
        // Avoid overwhelming users: show only one new badge modal per session.
        let eventsToQueue = Array(prioritized.prefix(1))
        let existing = loadPendingBadgeTierUnlocks(playerId: playerId)
        var merged = existing
        let existingSet = Set(existing)
        for event in eventsToQueue where !existingSet.contains(event) {
            merged.append(event)
        }
        savePendingBadgeTierUnlocks(merged, playerId: playerId)
    }

    private func pendingBadgeUnlocksKey(playerId: UUID?) -> String {
        let pid = playerId?.uuidString ?? "global"
        return "\(pendingBadgeUnlocksKeyPrefix)_\(pid)"
    }

    private func pendingBadgeTierUnlocksKey(playerId: UUID?) -> String {
        let pid = playerId?.uuidString ?? "global"
        return "\(pendingBadgeTierUnlocksKeyPrefix)_\(pid)"
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

    private func loadPendingBadgeTierUnlocks(playerId: UUID?) -> [BadgeTierUnlockEvent] {
        let key = pendingBadgeTierUnlocksKey(playerId: playerId)
        guard let data = userDefaults.data(forKey: key),
              let events = try? JSONDecoder().decode([BadgeTierUnlockEvent].self, from: data) else {
            return []
        }
        return events
    }

    private func savePendingBadgeTierUnlocks(_ events: [BadgeTierUnlockEvent], playerId: UUID?) {
        let key = pendingBadgeTierUnlocksKey(playerId: playerId)
        if events.isEmpty {
            userDefaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(events) {
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
            sentences.append("Your decisions are correct more often, but sometimes late. Focus on scanning earlier before expected arrival.")
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
