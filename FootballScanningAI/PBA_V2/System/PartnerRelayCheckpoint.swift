//
//  PartnerRelayCheckpoint.swift
//  FootballScanningAI
//
//  Partner relay: minimal drill snapshot after reconnect so coach/display can detect drift (not scoring).
//

import Foundation

extension Notification.Name {
    /// Posted on main after `TrainingPartnerConnectionCoordinator` finishes foreground reconnect attempts.
    static let relayForegroundReconnectCompleted = Notification.Name("relayForegroundReconnectCompleted")
    /// Coach join failed with an expired/invalid code; player iPad may recycle the display relay (same process only).
    static let relayDisplayRecycleRelayDueToExpiredJoinCode = Notification.Name("relayDisplayRecycleRelayDueToExpiredJoinCode")
    /// Partner transport restored with the same relay session + drill context; display restarts current rep from `waitingForNextRep`, coach re-sends `nextRep` for the same index.
    static let partnerSoftReconnectRepRestart = Notification.Name("partnerSoftReconnectRepRestart")
    /// Display (iPad): posted before pop-to-root when starting a new partner relay session from disconnect recovery — clears drill timers and rep UI state.
    static let partnerDisplayWillStartNewSessionFromDisconnect = Notification.Name("partnerDisplayWillStartNewSessionFromDisconnect")
    /// Player iPad: after ``TrainingPartnerConnectionCoordinator/startNewPartnerSessionFromDisconnect`` clears the nav stack — present ``CoachRemoteRequiredPromptView`` with the fresh join code.
    static let presentPlayerDisplayJoinPromptAfterStartNewSession = Notification.Name("presentPlayerDisplayJoinPromptAfterStartNewSession")
}

/// User-visible banner for relay lifecycle (reconnect, restored, rejoin).
enum PartnerRelayLifecycleBanner: Equatable {
    case hidden
    case reconnecting
    /// Brief interruption within grace window (soft-resume path).
    case restoringSession
    case connectionRestored
    /// Soft-resume succeeded (validation passed within grace window).
    case sessionRestoredSoft
    /// Same relay session after a brief drop while drilling; current rep restarts from coach `nextRep` (no session reset).
    case reconnectedRestartingRep
    /// Session token or socket could not be restored; user must re-enter join code or restart pairing.
    case sessionRequiresRejoin
    /// Display-reported rep index does not match coach UI after reconnect.
    case checkpointMismatch(hint: String)
}

struct PartnerRelayCheckpointPayload: Equatable {
    let sourceRole: String
    let activityId: String
    let repIndex: Int
    let phaseToken: String
    let relaySessionId: String?

    var debugDescription: String {
        "source=\(sourceRole) activity=\(activityId) rep=\(repIndex) phase=\(phaseToken) session=\(relaySessionId ?? "nil")"
    }
}

/// Engines that can emit a reconnect checkpoint for partner relay (display → coach).
protocol PartnerRelayCheckpointEmitting {
    func partnerRelayCheckpointPayload(activityId: String, relaySessionId: String?) -> PartnerRelayCheckpointPayload
}

@MainActor
enum PartnerRelayCheckpointDisplaySend {
    /// Sends checkpoint to coach when relay is up (after foreground reconnect).
    static func sendIfReady<E: PartnerRelayCheckpointEmitting>(engine: E, activityId: String, relay: PartnerRelayDisplaySession) {
        guard relay.joinCode != nil, relay.socketConnectionState == .connected else { return }
        let p = engine.partnerRelayCheckpointPayload(activityId: activityId, relaySessionId: relay.relaySessionId)
        let msg = TwoMinuteMessage.partnerSessionCheckpoint(
            sourceRole: p.sourceRole,
            activityId: p.activityId,
            repIndex: p.repIndex,
            phaseToken: p.phaseToken,
            relaySessionId: p.relaySessionId,
            timestamp: Date()
        )
        LifecycleReconnectDebug.logResyncPayload("display_tx \(p.debugDescription)")
        relay.sendTwoMinuteMessage(msg)
    }
}
