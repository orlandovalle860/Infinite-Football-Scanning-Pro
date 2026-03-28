//
//  CoachPersistDebug.swift
//  FootballScanningAI
//
//  Targeted DEBUG logs for coach relay persistence (join reuse across activity coach screens).
//

import Foundation

@MainActor
enum CoachPersistDebug {
    /// Relay coach remote lifecycle and join state (shared coordinator + join field snapshot).
    static func log(_ message: String, joinField: String = "", peerJoined: Bool = false) {
        #if DEBUG
        let c = TrainingPartnerConnectionCoordinator.shared
        let r = c.coachRelayRemoteService
        let stored = c.lastCoachRelayJoinCode ?? "nil"
        print("[CoachPersist-Debug] \(message) | isPartnerTrainingSessionActive=\(c.isPartnerTrainingSessionActive) lastCoachRelayJoinCode=\(stored) remoteConnectionState=\(r.connectionState.rawValue) joinField=\(joinField) peerJoined=\(peerJoined)")
        #endif
    }
}
