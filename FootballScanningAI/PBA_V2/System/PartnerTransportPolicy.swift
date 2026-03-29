//
//  PartnerTransportPolicy.swift
//  FootballScanningAI
//
//  Single source of truth for coach ↔ display transport (Multipeer vs relay WebSocket).
//

import Foundation

/// Central policy for partner session transport. Partner screens should read ``transportMode(for:trainingMode:)``
/// (display) or ``coachRemoteTransportMode`` (phone Coach Remote) instead of duplicating per-activity transport switches.
enum PartnerTransportPolicy {

    /// PBA partner activities that participate in shared transport rollout.
    enum PartnerActivity: CaseIterable, Sendable {
        case twoMinute
        case dribbleOrPass
        case awayFromPressure
        case oneTouchPassing
    }

    /// Transport for the **display** session: Partner and Wall use relay; Solo has no phone↔iPad session (Multipeer value is unused).
    static func transportMode(for _: PartnerActivity, trainingMode: TrainingMode) -> SessionTransportMode {
        trainingMode.requiresPhoneDisplayRelay ? .relayWebSocket : .multipeer
    }

    /// Phone **Coach Remote** always joins the display via relay when logging from the phone.
    static let coachRemoteTransportMode: SessionTransportMode = .relayWebSocket
}
