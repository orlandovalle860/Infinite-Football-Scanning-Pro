//
//  TwoMinuteSessionManager.swift
//  FootballScanningAI
//
//  PBA V2 — Manages session creation and coach connection state for the 2-minute test.
//  Coach connects via MultipeerConnectivity; no pairing code. Session is created in Supabase when display loads.
//

import Foundation
import Combine

/// Handles session creation in Supabase and coach connection state for the 2-minute test display.
/// When the display loads: create session in Supabase, start advertising. When the coach connects via Multipeer: set isConnected.
final class TwoMinuteSessionManager: ObservableObject {
    /// Session id after creation; also written to CurrentSessionStore for the save flow.
    @Published private(set) var sessionId: UUID?
    /// True while creating the session in Supabase.
    @Published private(set) var isCreating = false
    /// Non-nil if session creation failed.
    @Published private(set) var creationError: String?
    /// True after the coach device connects via Multipeer. Gates rep counter and activity UI.
    @Published private(set) var isConnected = false

    init() {}

    /// Creates a session in Supabase (no pairing code), then creates a session_activity row. On success, updates CurrentSessionStore.
    func startSession(activity: ActivityKind, blockSize: Int, playerId: UUID?) async {
        guard !isCreating else { return }
        isCreating = true
        creationError = nil
        let sessionIdCreated = await SupabaseSessionService.shared.createSessionForDrill(
            activity: activity,
            blockSize: blockSize,
            playerId: playerId
        )
        var sessionActivityId: UUID?
        if let sid = sessionIdCreated {
            sessionActivityId = await SupabaseSessionService.shared.createSessionActivity(
                sessionId: sid,
                activityId: activity.sessionActivityActivityId,
                blockNumber: 1
            )
        }
        await MainActor.run {
            isCreating = false
            if let sid = sessionIdCreated {
                sessionId = sid
                CurrentSessionStore.shared.setSessionIdOnly(sid)
                if let id = sessionActivityId {
                    CurrentSessionStore.shared.setCurrentSessionActivityId(id)
                }
            } else {
                creationError = "Couldn't create session. Check network."
            }
        }
    }

    /// Call when the coach device connects via Multipeer. Allows test to start.
    func setConnected(_ connected: Bool) {
        isConnected = connected
    }

    /// Reset state when leaving the session without completing (e.g. user leaves screen).
    /// - Parameter preserveCoachConnection: When `true`, keeps ``isConnected`` so relay partner UI can stay in sync across activity transitions (Home → Pathway → next drill) while the shared relay remains paired.
    func clear(preserveCoachConnection: Bool = false) {
        sessionId = nil
        isCreating = false
        creationError = nil
        if !preserveCoachConnection {
            isConnected = false
        }
    }
}
