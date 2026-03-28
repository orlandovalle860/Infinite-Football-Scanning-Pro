//
//  PartnerPersistDebug.swift
//  FootballScanningAI
//
//  Targeted diagnostics for partner relay persistence (Home → Pathway → next activity).
//

import Foundation

@MainActor
enum PartnerPersistDebug {
    /// Consistent snapshot for relay persistence debugging.
    static func log(_ message: String) {
        #if DEBUG
        let c = TrainingPartnerConnectionCoordinator.shared
        let r = c.relayDisplaySession
        let transport = r.hasRelayTransportForDiagnostics
        print(
            "[PartnerPersist-Debug] \(message) | isPartnerTrainingSessionActive=\(c.isPartnerTrainingSessionActive) joinCode=\(r.joinCode ?? "nil") socket=\(r.socketConnectionState.rawValue) transport=\(transport) isCoachPaired=\(r.isCoachPaired)"
        )
        #endif
    }
}
