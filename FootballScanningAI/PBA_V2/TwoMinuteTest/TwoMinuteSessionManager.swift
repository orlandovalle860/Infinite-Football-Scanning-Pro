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
    /// When not signed in (e.g. new user after sign-out), cloud insert is not possible; uses a local-only session id so relay + drill can still run.
    func startSession(activity: ActivityKind, blockSize: Int, playerId: UUID?, mode: TrainingMode) async {
        guard !isCreating else { return }
        isCreating = true
        creationError = nil
        let analyticsMode = SessionAnalyticsMode.from(trainingMode: mode)
        let sessionIdCreated = await SupabaseSessionService.shared.createSessionForDrill(
            activity: activity,
            blockSize: blockSize,
            playerId: playerId,
            mode: analyticsMode
        )
        var sessionActivityId: UUID?
        var segmentId: UUID?
        if let sid = sessionIdCreated {
            let block = await SupabaseSessionService.shared.openSessionActivityBlock(
                sessionId: sid,
                activityId: activity.sessionActivityActivityId,
                blockNumber: 1
            )
            sessionActivityId = block.sessionActivityId
            segmentId = block.segmentId
        }
        let noSupabaseAuth = await MainActor.run { AuthManager.shared.currentSession == nil }
        await MainActor.run {
            isCreating = false
            if let sid = sessionIdCreated {
                sessionId = sid
                CurrentSessionStore.shared.setSessionIdOnly(
                    sid,
                    mode: analyticsMode,
                    startAnalyticsClock: mode.requiresPhoneDisplayRelay,
                    supabaseStartedAt: Date()
                )
                if let id = sessionActivityId {
                    CurrentSessionStore.shared.setCurrentSessionActivityId(id)
                }
                if let segmentId {
                    CurrentSessionStore.shared.setCurrentSessionActivitySegmentId(
                        segmentId,
                        activityId: activity.sessionActivityActivityId
                    )
                }
                creationError = nil
            } else if noSupabaseAuth {
                let localId = UUID()
                sessionId = localId
                CurrentSessionStore.shared.clear()
                CurrentSessionStore.shared.setSessionIdOnly(
                    localId,
                    mode: SessionAnalyticsMode.from(trainingMode: mode),
                    startAnalyticsClock: mode.requiresPhoneDisplayRelay
                )
                creationError = nil
                print("[TwoMinuteSession] local-only session id=\(localId.uuidString) (no Supabase auth); relay/drill proceed without cloud session row")
            } else {
                creationError = UserFacingErrorMessage.connectionIssueRetry
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
