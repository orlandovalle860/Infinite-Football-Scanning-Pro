//
//  EndTrainingDebug.swift
//  FootballScanningAI
//
//  DEBUG logs for explicit partner training end and cross-device invalidation.
//

import Foundation

@MainActor
enum EndTrainingDebug {
    static func log(_ message: String) {
        #if DEBUG
        let c = TrainingPartnerConnectionCoordinator.shared
        let r = c.relayDisplaySession
        let join = r.joinCode ?? "nil"
        let coachConn = c.coachRelayRemoteService.connectionState.rawValue
        let stored = c.lastCoachRelayJoinCode ?? "nil"
        print("[EndTraining-Debug] \(message) | isPartnerTrainingSessionActive=\(c.isPartnerTrainingSessionActive) displayJoinCode=\(join) coachRelayState=\(coachConn) lastCoachRelayJoinCode=\(stored)")
        #endif
    }
}
