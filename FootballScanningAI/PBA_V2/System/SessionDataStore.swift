//
//  SessionDataStore.swift
//  FootballScanningAI
//
//  Data layer for PBA session records. All session persistence goes through this abstraction.
//  Current implementation uses UserDefaults; a cloud backend (e.g. Supabase, Firebase) can be
//  added later by providing another implementation without changing ProgressStore or the rest of the app.
//

import Foundation

/// Abstraction for persisting and loading session records. Implementations may use local storage
/// (UserDefaults) or a cloud backend; the app uses this protocol so sync can be added without call-site changes.
protocol SessionDataStore: AnyObject {
    /// Load all session records. Returns an empty array if none exist or on error.
    func loadSessions() -> [SessionRecord]

    /// Replace the stored session list with the given array (full save).
    func saveSessions(_ sessions: [SessionRecord])

    /// Remove all sessions for the given player. Used when a profile is deleted.
    func deleteSessions(forPlayerId playerId: UUID)
}

// MARK: - Local implementation (UserDefaults)

/// Persists session records to UserDefaults. Keeps current behavior; allows adding cloud sync later.
final class LocalSessionDataStore: SessionDataStore {
    private let key = "pba_sessions_v2"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSessions() -> [SessionRecord] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([SessionRecord].self, from: data)
        } catch {
            return []
        }
    }

    func saveSessions(_ sessions: [SessionRecord]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            userDefaults.set(data, forKey: key)
        } catch {
            // Fail silently for MVP; cloud implementation could log or retry
        }
    }

    func deleteSessions(forPlayerId playerId: UUID) {
        let current = loadSessions()
        let filtered = current.filter { $0.playerId != playerId }
        saveSessions(filtered)
    }
}
