//
//  PartnerRelayCheckpointCoachUI.swift
//  FootballScanningAI
//
//  Coach remote: compare display checkpoint after reconnect (does not modify scoring).
//

import Foundation

@MainActor
enum PartnerRelayCheckpointCoachUI {
    /// Handle `partnerSessionCheckpoint` from display; updates coordinator banner on mismatch or soft-resume validation.
    static func handleDisplayCheckpointMessage(
        _ msg: TwoMinuteMessage,
        relayWebSocket: Bool,
        expectedActivityId: String,
        coachSyncRepIndex: Int
    ) {
        guard relayWebSocket else { return }
        guard case .partnerSessionCheckpoint(let sourceRole, let activityId, let displayRep, _, let relaySessionId, _) = msg else { return }
        guard sourceRole == "display" else { return }

        let coordinator = TrainingPartnerConnectionCoordinator.shared
        let activityMatch = activityId == expectedActivityId
        let tracked = coordinator.trackedRelaySessionId
        let relayMatch: Bool = {
            guard let t = tracked, let r = relaySessionId else { return true }
            return t == r
        }()

        RelaySoftResumeDebug.logCheckpointComparison(
            displayRep: displayRep,
            coachRep: coachSyncRepIndex,
            relaySessionMatch: relayMatch,
            activityMatch: activityMatch
        )

        if coordinator.awaitingSoftResumeCheckpointValidation {
            coordinator.applyCoachSoftResumeCheckpointValidation(
                relaySessionMatch: relayMatch,
                activityMatch: activityMatch,
                repMatch: displayRep == coachSyncRepIndex
            )
            return
        }

        guard activityMatch else {
            if let t = tracked, let r = relaySessionId, t != r {
                coordinator.applyRelaySessionIdMismatchFromCheckpoint()
            }
            return
        }

        if let t = tracked, let r = relaySessionId, t != r {
            coordinator.applyRelaySessionIdMismatchFromCheckpoint()
            return
        }

        if displayRep != coachSyncRepIndex {
            guard !coordinator.isTransientLifecycleInterruptionActive() else { return }
            coordinator.setCheckpointDrift(displayRep: displayRep, coachRep: coachSyncRepIndex)
        } else {
            coordinator.clearCheckpointDrift()
        }
    }
}
