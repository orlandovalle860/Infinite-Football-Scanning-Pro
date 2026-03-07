//
//  TrainingMode.swift
//  FootballScanningAI
//
//  PBA V2 — Training mode selection: who triggers each rep (Partner = coach remote, Wall = volume, Solo = tap or volume).
//

import Foundation

enum TrainingMode: String, CaseIterable, Hashable {
    case partner = "Partner"
    case wall = "Wall"
    case solo = "Solo"

    var shortDescription: String {
        switch self {
        case .partner: return "Coach remote triggers each rep."
        case .wall: return "You trigger with volume button."
        case .solo: return "You trigger with screen tap or volume."
        }
    }

    var systemImage: String {
        switch self {
        case .partner: return "person.2.fill"
        case .wall: return "square.split.2x2"
        case .solo: return "person.fill"
        }
    }
}
