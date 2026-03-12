import Foundation
import SwiftUI

// MARK: - Personal Best per activity
struct ActivityBest: Codable {
    var bestCorrect: Int
    var bestTotal: Int
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

 