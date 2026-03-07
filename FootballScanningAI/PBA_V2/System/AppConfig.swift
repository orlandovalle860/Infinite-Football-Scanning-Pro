//
//  AppConfig.swift
//  FootballScanningAI
//
//  Global configuration. Set testerMode = false before App Store release.
//

import Foundation

struct AppConfig {
    /// When true, all training activities are visible and tappable on the Path screen (no locked states).
    /// Home screen recommendation still follows curriculum order.
    /// Set to false before App Store release.
    static let testerMode = true
}
