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
    /// Transient: next solo display session should force inline wall calibration (consumed on appear).
    static let soloForceInlineCalibration = "pba.soloWallCalibration.forceInline"
    /// Last solo session duration choice (`10min`, `15min`, `20min`, `free`).
    static let lastSessionDuration = "lastSessionDuration"
    /// Last solo training style (`quick`, `action`).
    static let lastTrainingStyle = "lastTrainingStyle"
}
