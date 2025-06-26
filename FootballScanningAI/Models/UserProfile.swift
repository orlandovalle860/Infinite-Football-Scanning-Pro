import Foundation
import SwiftUI

// MARK: - User Profile Model
struct UserProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var email: String?
    var dateCreated: Date
    var lastActive: Date
    
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
    
    init(name: String, email: String? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.dateCreated = Date()
        self.lastActive = Date()
        
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

