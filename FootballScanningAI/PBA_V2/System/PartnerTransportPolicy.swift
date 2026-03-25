//
//  PartnerTransportPolicy.swift
//  FootballScanningAI
//
//  Single source of truth for coach ↔ display transport (Multipeer vs relay WebSocket).
//

import Foundation

/// Central policy for partner session transport. Partner screens should read ``transportMode(for:)``
/// instead of duplicating `#if DEBUG` / Release switches per activity.
enum PartnerTransportPolicy {

    /// PBA partner activities that participate in shared transport rollout.
    enum PartnerActivity: CaseIterable, Sendable {
        case twoMinute
        case dribbleOrPass
        case awayFromPressure
        case oneTouchPassing
    }

    /// Which ``SessionTransportMode`` to use for the given partner activity.
    ///
    /// **Current behavior:** DEBUG builds use relay WebSocket; Release uses Multipeer.
    /// Per-activity branches can diverge here later (e.g. feature flags, Remote Config) without touching drill UI.
    static func transportMode(for activity: PartnerActivity) -> SessionTransportMode {
        #if DEBUG
        return .relayWebSocket
        #else
        return .multipeer
        #endif
    }
}
