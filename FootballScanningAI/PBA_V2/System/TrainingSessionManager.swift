//
//  TrainingSessionManager.swift
//  FootballScanningAI
//
//  Manages the lifecycle of a training session: session/block start, recording decisions, and finish.
//  Stores sessionId, playerId, activityId, blockNumber, and decisions; integrates with Supabase and CurrentSessionStore.
//

import Foundation
import Combine

/// Manages the lifecycle of a training session. Call startSession when a drill begins, startActivityBlock at the start of each block, recordDecision for each rep, and finishSession when the drill ends.
final class TrainingSessionManager: ObservableObject {
    static let shared = TrainingSessionManager()

    // MARK: - Stored state

    @Published private(set) var sessionId: UUID?
    @Published private(set) var playerId: UUID?
    @Published private(set) var activityId: String
    @Published private(set) var blockNumber: Int
    @Published private(set) var decisions: [TrainingDecisionRecord]

    private var activity: ActivityKind
    private var currentSessionActivityId: UUID?
    private var blockSize: Int

    private init() {
        self.activityId = ""
        self.blockNumber = 1
        self.decisions = []
        self.activity = .awayFromPressure
        self.blockSize = 12
    }

    // MARK: - Lifecycle

    /// Creates a session in Supabase and sets sessionId, playerId, activityId, blockNumber = 1, decisions = [].
    /// Returns the session id on success; nil on failure. Call startActivityBlock() after this to log the first block.
    func startSession(activity: ActivityKind, blockSize: Int, playerId: UUID?) async -> UUID? {
        let id = await SupabaseSessionService.shared.createSessionForDrill(
            activity: activity,
            blockSize: blockSize,
            playerId: playerId
        )
        await MainActor.run {
            if let id = id {
                sessionId = id
                self.playerId = playerId
                activityId = activity.sessionActivityActivityId
                self.activity = activity
                self.blockSize = blockSize
                blockNumber = 1
                decisions = []
                currentSessionActivityId = nil
                CurrentSessionStore.shared.setSessionIdOnly(id)
            }
        }
        return id
    }

    /// Logs the current block in session_activities (session_id, activity_id, block_number, started_at) and updates CurrentSessionStore.
    /// Call at the start of each drill block, before recording decisions. Increments blockNumber after logging.
    /// Returns the session_activity id on success.
    func startActivityBlock() async -> UUID? {
        guard let sessionId = sessionId else { return nil }
        let number = blockNumber
        let id = await SupabaseSessionService.shared.logSessionActivity(
            sessionId: sessionId,
            activityId: activityId,
            blockNumber: number
        )
        await MainActor.run {
            if let id = id {
                currentSessionActivityId = id
                CurrentSessionStore.shared.setCurrentSessionActivityId(id)
                blockNumber = number + 1
            }
        }
        return id
    }

    /// Appends a decision to the in-memory decisions array for this session.
    func recordDecision(_ decision: TrainingDecisionRecord) {
        decisions.append(decision)
    }

    /// Ends the current session: ends session_activity in Supabase, writes session_summary, updates/clears CurrentSessionStore, then clears manager state.
    /// Pass the SessionRecord built from your block results (e.g. from the block summary view). Uses the manager’s decisions array for the summary.
    func finishSession(record: SessionRecord, onSynced: (() -> Void)? = nil) {
        SupabaseSessionService.shared.saveSession(record: record, decisions: decisions, onSynced: { [weak self] in
            self?.clear()
            onSynced?()
        })
    }

    /// Resets all stored state. Called automatically after finishSession; can be called to abandon a session without saving.
    func clear() {
        sessionId = nil
        playerId = nil
        activityId = ""
        blockNumber = 1
        decisions = []
        activity = .awayFromPressure
        blockSize = 12
        currentSessionActivityId = nil
        CurrentSessionStore.shared.clear()
    }

    /// Whether a session is currently active (startSession succeeded and finishSession has not been called).
    var isSessionActive: Bool { sessionId != nil }
}
