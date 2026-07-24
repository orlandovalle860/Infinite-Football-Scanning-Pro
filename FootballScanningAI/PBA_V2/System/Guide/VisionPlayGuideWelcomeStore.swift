//
//  VisionPlayGuideWelcomeStore.swift
//  FootballScanningAI
//
//  One-time Guide introduction sheet — discover once, never block training.
//

import Foundation

enum VisionPlayGuideWelcomeStore {
    static let hasSeenKey = "pba.hasSeenVisionPlayGuideWelcome"

    static var hasSeen: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenKey) }
    }

    static func markSeen() {
        hasSeen = true
    }
}
