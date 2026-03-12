//
//  CurrentSessionStore.swift
//  FootballScanningAI
//
//  PBA V2 — On the display device: when a session/drill starts we create a session row and store id + session_activity id here.
//  Completion flow and events/decisions use these ids. Cleared when session ends.
//

import Foundation
import Combine

/// Holds the current display session id and session_activity id (iPad only). Set when session/drill starts, cleared when session ends.
final class CurrentSessionStore: ObservableObject {
    static let shared = CurrentSessionStore()

    @Published private(set) var sessionId: UUID?
    /// Id of the row in session_activities for the current drill. Events and decisions use session_activity_id = currentSessionActivityId.
    @Published private(set) var currentSessionActivityId: UUID?

    private init() {}

    /// Call when a drill starts. Sets sessionId so the block save and decisions update the same row.
    func setSessionIdOnly(_ id: UUID) {
        sessionId = id
    }

    /// Call when a drill starts after inserting into session_activities; saves the returned id so events and decisions link to the correct block.
    func setCurrentSessionActivityId(_ id: UUID) {
        currentSessionActivityId = id
    }

    func clear() {
        sessionId = nil
        currentSessionActivityId = nil
    }
}
