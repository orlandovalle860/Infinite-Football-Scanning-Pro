import Foundation
import SwiftUI
import Combine

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
    }
    
    func addProfile(name: String, email: String? = nil) {
        let newProfile = UserProfile(name: name, email: email)
        profiles.append(newProfile)
        saveProfiles()
    }
    
    func switchToProfile(_ profile: UserProfile) {
        currentProfile = profile
        isProfileCreated = true
        saveProfiles()
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
    
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            userDefaults.set(encoded, forKey: profilesKey)
        }
        
        if let currentProfile = currentProfile {
            userDefaults.set(currentProfile.id.uuidString, forKey: currentProfileIdKey)
        }
        
        userDefaults.set(isProfileCreated, forKey: isProfileCreatedKey)
    }
    
    private func loadProfiles() {
        // Load all profiles
        if let data = userDefaults.data(forKey: profilesKey),
           let loadedProfiles = try? JSONDecoder().decode([UserProfile].self, from: data) {
            profiles = loadedProfiles
        }
        
        // Load current profile
        if let currentProfileIdString = userDefaults.string(forKey: currentProfileIdKey),
           let currentProfileId = UUID(uuidString: currentProfileIdString),
           let profile = profiles.first(where: { $0.id == currentProfileId }) {
            currentProfile = profile
            isProfileCreated = true
        } else if let firstProfile = profiles.first {
            // If no current profile is set, use the first one
            currentProfile = firstProfile
            isProfileCreated = true
        } else {
            isProfileCreated = false
        }
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
