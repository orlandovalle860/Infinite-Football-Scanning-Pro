//
//  Player.swift
//  FootballScanningAI
//
//  PBA V2 — Local player (no sign-up); multiple players per device.
//

import Foundation

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
}
