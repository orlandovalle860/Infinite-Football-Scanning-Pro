//
//  PassTempo.swift
//  FootballScanningAI
//
//  Tempo-based pass speed model for timing windows.
//

import Foundation

enum PassTempo: String, Codable {
    case controlled   // beginner
    case gameSpeed    // intermediate
    case elite        // advanced

    var velocityMetersPerSecond: Double {
        switch self {
        case .controlled: return 6.0
        case .gameSpeed: return 8.0
        case .elite: return 10.0
        }
    }

    var displayName: String {
        switch self {
        case .controlled: return "Controlled"
        case .gameSpeed: return "Game Speed"
        case .elite: return "Elite"
        }
    }

    func expectedBallTravelTime(distanceMeters: Double = 11.0) -> Double {
        distanceMeters / velocityMetersPerSecond
    }
}

extension TestDifficulty {
    var passTempo: PassTempo {
        switch self {
        case .beginner: return .controlled
        case .standard: return .gameSpeed
        case .advanced: return .elite
        }
    }
}
