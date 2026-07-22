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
    /// True after the user's first training session completes (delayed login funnel).
    static let hasCompletedFirstSession = FirstSessionOnboardingStore.hasCompletedFirstSessionKey
    /// Kept in sync with ``PBASessionFlowPolicy.pbaLastSelectedTrainingModeKey`` via ``PBASessionFlowPolicy.persistTrainingMode(_:)``.
    static let lastMode = "lastMode"
    /// Legacy device-wide solo wall return time (pre–per-player). Migrated once into ``soloReturnTimeKey(playerId:)``.
    static let soloReturnTime = "soloReturnTime"
    /// Transient: next solo display session should force inline wall calibration (consumed on appear).
    static let soloForceInlineCalibration = "pba.soloWallCalibration.forceInline"
    /// Last session duration choice (`3min`, `free`). Legacy `5min`/`10min`/`15min`/`20min` migrate to `3min`.
    static let lastSessionDuration = "lastSessionDuration"
    /// Last solo training style (`quick`, `action`).
    static let lastTrainingStyle = "lastTrainingStyle"

    /// Per-player solo wall return time (seconds) after inline calibration.
    static func soloReturnTimeKey(playerId: UUID) -> String {
        "soloReturnTime.\(playerId.uuidString.lowercased())"
    }
}

/// Resolves the active local player for device-scoped calibration caches.
enum CalibrationPlayerScope {
    private static let selectedKey = "pba_selected_player_v1"
    private static let lastSelectedKey = "pba_last_selected_player_v1"

    static func activePlayerId() -> UUID? {
        for key in [lastSelectedKey, selectedKey] {
            if let raw = UserDefaults.standard.string(forKey: key),
               let id = UUID(uuidString: raw) {
                return id
            }
        }
        return nil
    }
}
