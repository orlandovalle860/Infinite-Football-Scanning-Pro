//
//  AppStorageKeys.swift
//  FootballScanningAI
//
//  UserDefaults keys for first-launch training mode + shared mode persistence.
//

import Foundation

enum AppStorageKeys {
    /// After the user picks Solo vs Coach Remote (partner) once, subsequent launches go straight to Home.
    static let hasLaunchedBefore = "pba.hasLaunchedBefore"
    /// Kept in sync with ``PBASessionFlowPolicy.pbaLastSelectedTrainingModeKey`` via ``PBASessionFlowPolicy.persistTrainingMode(_:)``.
    static let lastMode = "lastMode"
    /// One-Touch Passing Solo: cached wall return time (seconds) after inline calibration. Enables instant start on following sessions.
    static let soloReturnTime = "soloReturnTime"
}
