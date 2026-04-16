import Foundation
import SwiftUI

// MARK: - Personal Best per activity
struct ActivityBest: Codable {
    var bestCorrect: Int
    var bestTotal: Int
}

enum PlayerProgressStage: String, Codable, CaseIterable {
    case awayFromPressure
    case dribbleOrPass
    case oneTouchPassing

    var activity: ActivityKind {
        switch self {
        case .awayFromPressure: return .awayFromPressure
        case .dribbleOrPass: return .dribbleOrPass
        case .oneTouchPassing: return .oneTouchPassing
        }
    }

    var next: PlayerProgressStage? {
        switch self {
        case .awayFromPressure: return .dribbleOrPass
        case .dribbleOrPass: return .oneTouchPassing
        case .oneTouchPassing: return nil
        }
    }
}

struct PlayerStageSessionResult: Codable, Hashable {
    let score: Double
    let accuracy: Double
    let activityType: ActivityKind
    let timestamp: Date
}

struct AdaptiveTrainingState: Codable, Equatable {
    var currentTempo: PassTempo
    var currentLevel: SessionPerformanceLevel
    var recentScores: [Int]
    var recommendation: String
    var focus: String
}

enum BadgeTrack: String, Codable, CaseIterable, Hashable {
    case earlyThinker
    case levelUp
    case lockedIn
    case onFire
    case aheadOfPlay

    var title: String {
        switch self {
        case .earlyThinker: return "Early Thinker"
        case .levelUp: return "Level Up"
        case .lockedIn: return "Locked In"
        case .onFire: return "On Fire"
        case .aheadOfPlay: return "Ahead of Play"
        }
    }

    var icon: String {
        switch self {
        case .earlyThinker: return "brain.head.profile"
        case .levelUp: return "arrow.up.circle.fill"
        case .lockedIn: return "lock.shield.fill"
        case .onFire: return "flame.fill"
        case .aheadOfPlay: return "hare.fill"
        }
    }
}

struct BadgeTierUnlockEvent: Codable, Equatable, Hashable {
    let track: BadgeTrack
    let level: Int
}

enum PlayerBadge: String, Codable, CaseIterable, Hashable {
    // Engagement / performance badges
    case earlyThinker = "Early Thinker"
    case levelUp = "Level Up"
    case lockedIn = "Locked In"
    case onFire3 = "On Fire I"
    case onFire5 = "On Fire II"
    case onFire10 = "On Fire III"
    case onFire20 = "On Fire IV"
    case aheadOfPlay = "Ahead of Play"
    // Legacy badges kept for backward compatibility with persisted data.
    case earlyDecider = "Early Decider"
    case forwardThinker = "Forward Thinker"
    case consistent = "Consistent"
    case firstSession = "First Session"
    case fastThinker = "Fast Thinker"
    case accuratePlayer = "Accurate Player"
    case forwardPlayer = "Forward Player"

    var title: String { rawValue }

    var unlockDescription: String {
        switch self {
        case .earlyThinker:
            return "At least half of your decisions were early in one session."
        case .levelUp:
            return "Your score jumped by 10 or more from the previous session."
        case .lockedIn:
            return "You kept late decisions very low in a session."
        case .onFire3:
            return "You reached a 3-session streak."
        case .onFire5:
            return "You reached a 5-session streak."
        case .onFire10:
            return "You reached a 10-session streak."
        case .onFire20:
            return "You reached a 20-session streak."
        case .aheadOfPlay:
            return "You scored 90+ in a session."
        case .earlyDecider:
            return "You're making decisions before pressure arrives."
        case .forwardThinker:
            return "You consistently choose forward options when available."
        case .consistent:
            return "You maintained strong performance across sessions."
        case .firstSession:
            return "Completed your first training session."
        case .fastThinker:
            return "Recorded at least 60% fast decisions in a session."
        case .accuratePlayer:
            return "Reached at least 80% decision accuracy in a session."
        case .forwardPlayer:
            return "Chose the forward option at least 50% of the time when available."
        }
    }

    var icon: String {
        switch self {
        case .earlyThinker: return "brain.head.profile"
        case .levelUp: return "arrow.up.circle.fill"
        case .lockedIn: return "lock.shield.fill"
        case .onFire3, .onFire5, .onFire10, .onFire20: return "flame.fill"
        case .aheadOfPlay: return "hare.fill"
        case .earlyDecider: return "bolt.fill"
        case .forwardThinker: return "arrow.up.right.circle.fill"
        case .consistent: return "checkmark.seal.fill"
        case .firstSession, .fastThinker, .accuratePlayer, .forwardPlayer: return "star.fill"
        }
    }
}

// MARK: - User Profile Model
struct UserProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var email: String?
    var dateCreated: Date
    var lastActive: Date

    // Player info (optional; set after 2-Minute Test profile creation)
    var age: String?
    var team: String?
    var position: String?

    // Cached from latest test/training (optional)
    var decisionScore: Int?
    var status: String?
    var consistency: String?
    
    // User Preferences
    var preferredDisplayMode: DisplayMode
    var preferredColors: [String] // Store color as hex string
    var preferredNumbers: [Int]
    var preferredArrows: [String]
    var preferredLanes: [String]
    var preferredBeepInterval: BeepInterval
    var preferredNumberColor: String // hex string
    var preferredArrowColor: String // hex string
    var preferredColorSet: ScanningColorSet
    var preferredActionSet: ActionSet
    var screenProtectionEnabled: Bool
    var soundEnabled: Bool
    
    // Critical Scan Preferences
    var criticalScanDelay: Double
    var criticalScanDuration: Double
    var criticalScanResetTime: Double
    
    // Custom Actions
    var customActions: [CustomAction]
    
    // Training Statistics
    var totalSessions: Int
    var totalTrainingTime: TimeInterval
    var sessionsThisWeek: Int
    var sessionsThisMonth: Int
    var longestSession: TimeInterval
    var averageSessionLength: TimeInterval
    
    // Training History
    var trainingSessions: [TrainingSession]

    // Session summaries (coach report) per block/test — stored separately by UserProfileManager
    var sessionResults: [SessionResult]

    /// Best score per activity (e.g. Away From Pressure 11/12).
    var personalBests: [ActivityKind: ActivityBest]

    // Weekly training streak (3+ sessions per week = 1 session = 2 blocks)
    var currentWeeklyStreak: Int
    var longestWeeklyStreak: Int
    var blocksCompletedThisWeek: Int
    var lastSessionDate: Date?
    var lastWeekStart: Date?

    // Personal bests (motivation metrics)
    /// Lowest average decision time in a block (seconds). Lower is better.
    var fastestDecisionSpeedSeconds: Double?
    /// Highest correct % in Playing Away From Pressure. Higher is better.
    var bestPressureEscapePercent: Double?
    /// Highest forward intent % in Dribble or Pass. Higher is better.
    var bestForwardIntentPercent: Double?
    /// Simple cumulative XP total for this player.
    var totalXP: Int
    /// Unlocked badges for this player.
    var unlockedBadges: [PlayerBadge]
    /// Latest badge unlocked in the most recent completed session (if any).
    var lastUnlockedBadge: PlayerBadge?
    /// Tier level (0...4) for each badge track.
    var badgeTierLevels: [BadgeTrack: Int]
    /// Latest tier level up event for badges.
    var lastBadgeTierUnlocked: BadgeTierUnlockEvent?
    /// Session streak counter (increments per completed session; V1 does not hard-reset on short pauses).
    var sessionStreakCount: Int
    var longestSessionStreak: Int
    /// Premium entitlement flag (StoreKit to be integrated later).
    var isPremium: Bool
    /// Player progression stage (AFP -> DOP -> OTP).
    var currentStage: PlayerProgressStage
    /// Session results tracked per stage for progression evaluation.
    var stageHistory: [PlayerProgressStage: [PlayerStageSessionResult]]
    /// Latest next-session prescription after a scored block (tied to that session via `tiedSessionId`).
    var lastStageRecommendation: StageSessionRecommendation?
    /// Adaptive progression state based on recent scored sessions.
    var adaptiveTrainingState: AdaptiveTrainingState

    /// Create a profile with a specific id (e.g. to match a Supabase players row after account creation).
    init(id: UUID, name: String, email: String? = nil, age: String? = nil, team: String? = nil, position: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.dateCreated = Date()
        self.lastActive = Date()
        self.age = age
        self.team = team
        self.position = position
        self.decisionScore = nil
        self.status = nil
        self.consistency = nil
        self.preferredDisplayMode = .colors
        self.preferredColors = []
        self.preferredNumbers = []
        self.preferredArrows = []
        self.preferredLanes = []
        self.preferredBeepInterval = .medium
        self.preferredNumberColor = "#FFFFFF"
        self.preferredArrowColor = "#FFFFFF"
        self.preferredColorSet = .standard
        self.preferredActionSet = .basic
        self.screenProtectionEnabled = true
        self.soundEnabled = true
        self.criticalScanDelay = 0.5
        self.criticalScanDuration = 1.0
        self.criticalScanResetTime = 5.0
        self.customActions = [
            CustomAction(number: 1, action: "Action", isCustom: false),
            CustomAction(number: 2, action: "Action", isCustom: false),
            CustomAction(number: 3, action: "Action", isCustom: false),
            CustomAction(number: 4, action: "Action", isCustom: false),
            CustomAction(number: 5, action: "Action", isCustom: false),
            CustomAction(number: 6, action: "Action", isCustom: false),
            CustomAction(number: 7, action: "Action", isCustom: false),
            CustomAction(number: 8, action: "Action", isCustom: false)
        ]
        self.totalSessions = 0
        self.totalTrainingTime = 0
        self.sessionsThisWeek = 0
        self.sessionsThisMonth = 0
        self.longestSession = 0
        self.averageSessionLength = 0
        self.trainingSessions = []
        self.sessionResults = []
        self.personalBests = [:]
        self.currentWeeklyStreak = 0
        self.longestWeeklyStreak = 0
        self.blocksCompletedThisWeek = 0
        self.lastSessionDate = nil
        self.lastWeekStart = nil
        self.fastestDecisionSpeedSeconds = nil
        self.bestPressureEscapePercent = nil
        self.bestForwardIntentPercent = nil
        self.totalXP = 0
        self.unlockedBadges = []
        self.lastUnlockedBadge = nil
        self.badgeTierLevels = [:]
        self.lastBadgeTierUnlocked = nil
        self.sessionStreakCount = 0
        self.longestSessionStreak = 0
        self.isPremium = false
        self.currentStage = .awayFromPressure
        self.stageHistory = [:]
        self.lastStageRecommendation = nil
        self.adaptiveTrainingState = AdaptiveTrainingState(
            currentTempo: .controlled,
            currentLevel: .reactive,
            recentScores: [],
            recommendation: "Stay here and push for earlier decisions",
            focus: "commit earlier"
        )
    }

    init(name: String, email: String? = nil, age: String? = nil, team: String? = nil, position: String? = nil, decisionScore: Int? = nil, status: String? = nil, consistency: String? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.dateCreated = Date()
        self.lastActive = Date()
        self.age = age
        self.team = team
        self.position = position
        self.decisionScore = decisionScore
        self.status = status
        self.consistency = consistency
        
        // Default preferences
        self.preferredDisplayMode = .colors
        self.preferredColors = []
        self.preferredNumbers = []
        self.preferredArrows = []
        self.preferredLanes = []
        self.preferredBeepInterval = .medium
        self.preferredNumberColor = "#FFFFFF"
        self.preferredArrowColor = "#FFFFFF"
        self.preferredColorSet = .standard
        self.preferredActionSet = .basic
        self.screenProtectionEnabled = true
        self.soundEnabled = true
        
        // Default critical scan settings
        self.criticalScanDelay = 0.5
        self.criticalScanDuration = 1.0
        self.criticalScanResetTime = 5.0
        
        // Default custom actions
        self.customActions = [
            CustomAction(number: 1, action: "Action", isCustom: false),
            CustomAction(number: 2, action: "Action", isCustom: false),
            CustomAction(number: 3, action: "Action", isCustom: false),
            CustomAction(number: 4, action: "Action", isCustom: false),
            CustomAction(number: 5, action: "Action", isCustom: false),
            CustomAction(number: 6, action: "Action", isCustom: false),
            CustomAction(number: 7, action: "Action", isCustom: false),
            CustomAction(number: 8, action: "Action", isCustom: false)
        ]
        
        // Initialize statistics
        self.totalSessions = 0
        self.totalTrainingTime = 0
        self.sessionsThisWeek = 0
        self.sessionsThisMonth = 0
        self.longestSession = 0
        self.averageSessionLength = 0
        
        // Initialize training history
        self.trainingSessions = []
        self.sessionResults = []
        self.personalBests = [:]
        self.currentWeeklyStreak = 0
        self.longestWeeklyStreak = 0
        self.blocksCompletedThisWeek = 0
        self.lastSessionDate = nil
        self.lastWeekStart = nil
        self.fastestDecisionSpeedSeconds = nil
        self.bestPressureEscapePercent = nil
        self.bestForwardIntentPercent = nil
        self.totalXP = 0
        self.unlockedBadges = []
        self.lastUnlockedBadge = nil
        self.badgeTierLevels = [:]
        self.lastBadgeTierUnlocked = nil
        self.sessionStreakCount = 0
        self.longestSessionStreak = 0
        self.isPremium = false
        self.currentStage = .awayFromPressure
        self.stageHistory = [:]
        self.lastStageRecommendation = nil
        self.adaptiveTrainingState = AdaptiveTrainingState(
            currentTempo: .controlled,
            currentLevel: .reactive,
            recentScores: [],
            recommendation: "Stay here and push for earlier decisions",
            focus: "commit earlier"
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, email, dateCreated, lastActive, age, team, position
        case decisionScore, status, consistency
        case preferredDisplayMode, preferredColors, preferredNumbers, preferredArrows, preferredLanes
        case preferredBeepInterval, preferredNumberColor, preferredArrowColor, preferredColorSet, preferredActionSet
        case screenProtectionEnabled, soundEnabled
        case criticalScanDelay, criticalScanDuration, criticalScanResetTime, customActions
        case totalSessions, totalTrainingTime, sessionsThisWeek, sessionsThisMonth
        case longestSession, averageSessionLength, trainingSessions, sessionResults, personalBests
        case currentWeeklyStreak, longestWeeklyStreak, blocksCompletedThisWeek, lastSessionDate, lastWeekStart
        case fastestDecisionSpeedSeconds, bestPressureEscapePercent, bestForwardIntentPercent
        case totalXP
        case unlockedBadges
        case lastUnlockedBadge
        case badgeTierLevels
        case lastBadgeTierUnlocked
        case sessionStreakCount
        case longestSessionStreak
        case isPremium
        case currentStage
        case stageHistory
        case lastStageRecommendation
        case adaptiveTrainingState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        dateCreated = try c.decode(Date.self, forKey: .dateCreated)
        lastActive = try c.decode(Date.self, forKey: .lastActive)
        age = try c.decodeIfPresent(String.self, forKey: .age)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        position = try c.decodeIfPresent(String.self, forKey: .position)
        decisionScore = try c.decodeIfPresent(Int.self, forKey: .decisionScore)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        consistency = try c.decodeIfPresent(String.self, forKey: .consistency)
        preferredDisplayMode = try c.decode(DisplayMode.self, forKey: .preferredDisplayMode)
        preferredColors = try c.decode([String].self, forKey: .preferredColors)
        preferredNumbers = try c.decode([Int].self, forKey: .preferredNumbers)
        preferredArrows = try c.decode([String].self, forKey: .preferredArrows)
        preferredLanes = try c.decode([String].self, forKey: .preferredLanes)
        preferredBeepInterval = try c.decode(BeepInterval.self, forKey: .preferredBeepInterval)
        preferredNumberColor = try c.decode(String.self, forKey: .preferredNumberColor)
        preferredArrowColor = try c.decode(String.self, forKey: .preferredArrowColor)
        preferredColorSet = try c.decode(ScanningColorSet.self, forKey: .preferredColorSet)
        preferredActionSet = try c.decode(ActionSet.self, forKey: .preferredActionSet)
        screenProtectionEnabled = try c.decode(Bool.self, forKey: .screenProtectionEnabled)
        soundEnabled = try c.decode(Bool.self, forKey: .soundEnabled)
        criticalScanDelay = try c.decode(Double.self, forKey: .criticalScanDelay)
        criticalScanDuration = try c.decode(Double.self, forKey: .criticalScanDuration)
        criticalScanResetTime = try c.decode(Double.self, forKey: .criticalScanResetTime)
        customActions = try c.decode([CustomAction].self, forKey: .customActions)
        totalSessions = try c.decode(Int.self, forKey: .totalSessions)
        totalTrainingTime = try c.decode(TimeInterval.self, forKey: .totalTrainingTime)
        sessionsThisWeek = try c.decode(Int.self, forKey: .sessionsThisWeek)
        sessionsThisMonth = try c.decode(Int.self, forKey: .sessionsThisMonth)
        longestSession = try c.decode(TimeInterval.self, forKey: .longestSession)
        averageSessionLength = try c.decode(TimeInterval.self, forKey: .averageSessionLength)
        trainingSessions = try c.decode([TrainingSession].self, forKey: .trainingSessions)
        sessionResults = try c.decodeIfPresent([SessionResult].self, forKey: .sessionResults) ?? []
        personalBests = try c.decodeIfPresent([ActivityKind: ActivityBest].self, forKey: .personalBests) ?? [:]
        currentWeeklyStreak = try c.decodeIfPresent(Int.self, forKey: .currentWeeklyStreak) ?? 0
        longestWeeklyStreak = try c.decodeIfPresent(Int.self, forKey: .longestWeeklyStreak) ?? 0
        blocksCompletedThisWeek = try c.decodeIfPresent(Int.self, forKey: .blocksCompletedThisWeek) ?? 0
        lastSessionDate = try c.decodeIfPresent(Date.self, forKey: .lastSessionDate)
        lastWeekStart = try c.decodeIfPresent(Date.self, forKey: .lastWeekStart)
        fastestDecisionSpeedSeconds = try c.decodeIfPresent(Double.self, forKey: .fastestDecisionSpeedSeconds)
        bestPressureEscapePercent = try c.decodeIfPresent(Double.self, forKey: .bestPressureEscapePercent)
        bestForwardIntentPercent = try c.decodeIfPresent(Double.self, forKey: .bestForwardIntentPercent)
        totalXP = try c.decodeIfPresent(Int.self, forKey: .totalXP) ?? 0
        unlockedBadges = try c.decodeIfPresent([PlayerBadge].self, forKey: .unlockedBadges) ?? []
        lastUnlockedBadge = try c.decodeIfPresent(PlayerBadge.self, forKey: .lastUnlockedBadge)
        badgeTierLevels = try c.decodeIfPresent([BadgeTrack: Int].self, forKey: .badgeTierLevels) ?? [:]
        lastBadgeTierUnlocked = try c.decodeIfPresent(BadgeTierUnlockEvent.self, forKey: .lastBadgeTierUnlocked)
        sessionStreakCount = try c.decodeIfPresent(Int.self, forKey: .sessionStreakCount) ?? 0
        longestSessionStreak = try c.decodeIfPresent(Int.self, forKey: .longestSessionStreak) ?? 0
        isPremium = try c.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        currentStage = try c.decodeIfPresent(PlayerProgressStage.self, forKey: .currentStage) ?? .awayFromPressure
        stageHistory = try c.decodeIfPresent([PlayerProgressStage: [PlayerStageSessionResult]].self, forKey: .stageHistory) ?? [:]
        lastStageRecommendation = try c.decodeIfPresent(StageSessionRecommendation.self, forKey: .lastStageRecommendation)
        adaptiveTrainingState = try c.decodeIfPresent(AdaptiveTrainingState.self, forKey: .adaptiveTrainingState)
            ?? AdaptiveTrainingState(
                currentTempo: .controlled,
                currentLevel: .reactive,
                recentScores: [],
                recommendation: "Stay here and push for earlier decisions",
                focus: "commit earlier"
            )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encode(dateCreated, forKey: .dateCreated)
        try c.encode(lastActive, forKey: .lastActive)
        try c.encodeIfPresent(age, forKey: .age)
        try c.encodeIfPresent(team, forKey: .team)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encodeIfPresent(decisionScore, forKey: .decisionScore)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(consistency, forKey: .consistency)
        try c.encode(preferredDisplayMode, forKey: .preferredDisplayMode)
        try c.encode(preferredColors, forKey: .preferredColors)
        try c.encode(preferredNumbers, forKey: .preferredNumbers)
        try c.encode(preferredArrows, forKey: .preferredArrows)
        try c.encode(preferredLanes, forKey: .preferredLanes)
        try c.encode(preferredBeepInterval, forKey: .preferredBeepInterval)
        try c.encode(preferredNumberColor, forKey: .preferredNumberColor)
        try c.encode(preferredArrowColor, forKey: .preferredArrowColor)
        try c.encode(preferredColorSet, forKey: .preferredColorSet)
        try c.encode(preferredActionSet, forKey: .preferredActionSet)
        try c.encode(screenProtectionEnabled, forKey: .screenProtectionEnabled)
        try c.encode(soundEnabled, forKey: .soundEnabled)
        try c.encode(criticalScanDelay, forKey: .criticalScanDelay)
        try c.encode(criticalScanDuration, forKey: .criticalScanDuration)
        try c.encode(criticalScanResetTime, forKey: .criticalScanResetTime)
        try c.encode(customActions, forKey: .customActions)
        try c.encode(totalSessions, forKey: .totalSessions)
        try c.encode(totalTrainingTime, forKey: .totalTrainingTime)
        try c.encode(sessionsThisWeek, forKey: .sessionsThisWeek)
        try c.encode(sessionsThisMonth, forKey: .sessionsThisMonth)
        try c.encode(longestSession, forKey: .longestSession)
        try c.encode(averageSessionLength, forKey: .averageSessionLength)
        try c.encode(trainingSessions, forKey: .trainingSessions)
        try c.encode(sessionResults, forKey: .sessionResults)
        try c.encode(personalBests, forKey: .personalBests)
        try c.encode(currentWeeklyStreak, forKey: .currentWeeklyStreak)
        try c.encode(longestWeeklyStreak, forKey: .longestWeeklyStreak)
        try c.encode(blocksCompletedThisWeek, forKey: .blocksCompletedThisWeek)
        try c.encodeIfPresent(lastSessionDate, forKey: .lastSessionDate)
        try c.encodeIfPresent(lastWeekStart, forKey: .lastWeekStart)
        try c.encodeIfPresent(fastestDecisionSpeedSeconds, forKey: .fastestDecisionSpeedSeconds)
        try c.encodeIfPresent(bestPressureEscapePercent, forKey: .bestPressureEscapePercent)
        try c.encodeIfPresent(bestForwardIntentPercent, forKey: .bestForwardIntentPercent)
        try c.encode(totalXP, forKey: .totalXP)
        try c.encode(unlockedBadges, forKey: .unlockedBadges)
        try c.encodeIfPresent(lastUnlockedBadge, forKey: .lastUnlockedBadge)
        try c.encode(badgeTierLevels, forKey: .badgeTierLevels)
        try c.encodeIfPresent(lastBadgeTierUnlocked, forKey: .lastBadgeTierUnlocked)
        try c.encode(sessionStreakCount, forKey: .sessionStreakCount)
        try c.encode(longestSessionStreak, forKey: .longestSessionStreak)
        try c.encode(isPremium, forKey: .isPremium)
        try c.encode(currentStage, forKey: .currentStage)
        try c.encode(stageHistory, forKey: .stageHistory)
        try c.encodeIfPresent(lastStageRecommendation, forKey: .lastStageRecommendation)
        try c.encode(adaptiveTrainingState, forKey: .adaptiveTrainingState)
    }

    /// Update personal best for an activity when a session beats the previous best.
    mutating func updatePersonalBest(session: SessionResult) {
        let activity = session.activityType
        let score = session.correctCount
        let total = session.totalReps
        if let best = personalBests[activity] {
            if score > best.bestCorrect {
                personalBests[activity] = ActivityBest(bestCorrect: score, bestTotal: total)
            }
        } else {
            personalBests[activity] = ActivityBest(bestCorrect: score, bestTotal: total)
        }
    }
}

struct TrainingSession: Codable, Identifiable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let displayMode: DisplayMode
    let colorsUsed: [String] // hex strings
    let numbersUsed: [Int]
    let arrowsUsed: [String]
    let lanesUsed: [String]
    let beepInterval: BeepInterval
    let numberColor: String // hex string
    let arrowColor: String // hex string
    let colorSet: ScanningColorSet
    let actionSet: ActionSet
    let customActions: [CustomAction]
    let criticalScanDelay: Double
    let criticalScanDuration: Double
    let criticalScanResetTime: Double
    let screenProtectionEnabled: Bool
    let soundEnabled: Bool
    
    init(displayMode: DisplayMode, colorsUsed: [String], numbersUsed: [Int], arrowsUsed: [String], lanesUsed: [String], beepInterval: BeepInterval, numberColor: String, arrowColor: String, colorSet: ScanningColorSet, actionSet: ActionSet, customActions: [CustomAction], criticalScanDelay: Double, criticalScanDuration: Double, criticalScanResetTime: Double, screenProtectionEnabled: Bool, soundEnabled: Bool, duration: TimeInterval) {
        self.id = UUID()
        self.date = Date()
        self.duration = duration
        self.displayMode = displayMode
        self.colorsUsed = colorsUsed
        self.numbersUsed = numbersUsed
        self.arrowsUsed = arrowsUsed
        self.lanesUsed = lanesUsed
        self.beepInterval = beepInterval
        self.numberColor = numberColor
        self.arrowColor = arrowColor
        self.colorSet = colorSet
        self.actionSet = actionSet
        self.customActions = customActions
        self.criticalScanDelay = criticalScanDelay
        self.criticalScanDuration = criticalScanDuration
        self.criticalScanResetTime = criticalScanResetTime
        self.screenProtectionEnabled = screenProtectionEnabled
        self.soundEnabled = soundEnabled
    }
}

 