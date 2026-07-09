//
//  LocalUserIdentityStore.swift
//  FootballScanningAI
//
//  Stable anonymous user id for local session analytics when no auth session exists.
//

import Foundation

enum LocalUserIdentityStore {
    static let localUserIdKey = "local_user_id"
    private static let userHasSessionPrefix = "local_user_has_session."

    /// Returns a stable UUID string stored in UserDefaults, creating it on first access.
    static func ensureLocalUserId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: localUserIdKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: localUserIdKey)
        return generated
    }

    /// True when this user has no locally-recorded prior completed session.
    static func isFirstSession(for userId: String) -> Bool {
        !UserDefaults.standard.bool(forKey: userHasSessionKey(for: userId))
    }

    /// Marks that this user has at least one completed session saved.
    static func markHasSession(for userId: String) {
        UserDefaults.standard.set(true, forKey: userHasSessionKey(for: userId))
    }

    private static func userHasSessionKey(for userId: String) -> String {
        userHasSessionPrefix + userId.lowercased()
    }
}
