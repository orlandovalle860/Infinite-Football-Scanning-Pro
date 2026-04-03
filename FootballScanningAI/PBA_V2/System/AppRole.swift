//
//  AppRole.swift
//  FootballScanningAI
//
//  Persistent device mode: player Home vs Coach Remote hub as root.
//

import Foundation

enum AppRole: String, CaseIterable {
    case player = "player"
    case coachRemote = "coachRemote"

    /// `AppStorage` / `UserDefaults` key (must stay stable).
    static let storageKey = "app_role"

    static func resolved(from raw: String) -> AppRole {
        AppRole(rawValue: raw) ?? .player
    }
}

enum AppRoleDebug {
    static func log(_ message: String) {
        print("[AppRole-Debug] \(message)")
    }
}
