import Foundation

enum PBASessionFlowPolicy {
    /// UserDefaults key for the last training mode; keep in sync with ``TrainingModeSelectionView`` saves.
    static let pbaLastSelectedTrainingModeKey = "pba.lastSelectedTrainingMode"

    private static let globalLastRoleKey = "pba.lastSelectedDeviceRole"
    private static let twoMinuteLastRoleKey = "twoMinuteTest.lastSelectedDeviceRole"
    private static let awayFromPressureLastRoleKey = "awayFromPressure.lastSelectedDeviceRole"
    private static let dribbleOrPassLastRoleKey = "dribbleOrPass.lastSelectedDeviceRole"
    private static let oneTouchPassingLastRoleKey = "oneTouchPassing.lastSelectedDeviceRole"

    static func shouldSkipConnectionPrompts() -> Bool {
        TrainingPartnerConnectionCoordinator.shared.isConnected
    }

    static func shouldPromptCalibration(for mode: TrainingMode) -> Bool {
        false
    }

    /// Solo local display (no phone relay): choose travel-time override and mark calibration so ``tryStartSoloAutoloop`` is not stuck behind `hasCompletedPassTempoCalibration` when the player has no saved pass-tempo.
    static func soloLocalDisplayInitialTravel(
        mode: TrainingMode,
        nominalTravelSeconds: Double
    ) -> (showPassTempoCalibration: Bool, overrideSeconds: Double, completedCalibration: Bool) {
        let show = shouldPromptCalibration(for: mode)
        if let calibrated = PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds(),
           !shouldPromptCalibration(for: mode) {
            return (show, calibrated, true)
        }
        return (show, nominalTravelSeconds, true)
    }

    static func shouldShowWaitingForCoach(isAwaitingCoachInput: Bool) -> Bool {
        TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive && isAwaitingCoachInput
    }

    static func handleResultsPresented() {
        // Keep result-state data alive while the full summary screen builds and renders.
        // Ending/clearing should happen from explicit exit actions after results are shown.
    }

    /// Resolves the same persisted choice as the training-mode screen (`Partner` / `Wall` / `Solo`), used for route payloads and first-time flows.
    static func lastSelectedTrainingMode() -> TrainingMode {
        let keys = [pbaLastSelectedTrainingModeKey, AppStorageKeys.lastMode]
        for key in keys {
            guard let raw = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            if let mode = TrainingMode(rawValue: raw) { return mode }
            switch raw.lowercased() {
            case "solo": return .solo
            case "partner": return .partner
            case "wall": return .wall
            default: break
            }
        }
        return .solo
    }

    /// Writes canonical PBA key and `lastMode` alias so first-launch / Home always agree.
    static func persistTrainingMode(_ mode: TrainingMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: pbaLastSelectedTrainingModeKey)
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKeys.lastMode)
    }

    /// Existing installs already have a stored training mode; treat first-launch onboarding as done so we do not block Home.
    static func migrateTrainingModeOnboardingIfNeeded() {
        let hasStoredMode = UserDefaults.standard.object(forKey: pbaLastSelectedTrainingModeKey) != nil
            || UserDefaults.standard.object(forKey: AppStorageKeys.lastMode) != nil
        if hasStoredMode, !UserDefaults.standard.bool(forKey: AppStorageKeys.hasLaunchedBefore) {
            UserDefaults.standard.set(true, forKey: AppStorageKeys.hasLaunchedBefore)
        }
    }

    /// Route for a **user-initiated** activity entry (e.g. curriculum, dashboard). `m` is the **saved preference** (segment / ``persistTrainingMode``) — it does not trigger navigation on its own; callers push this route in response to taps.
    static func routeForActivityLaunch(_ activity: ActivityKind) -> AppRoute {
        let m = lastSelectedTrainingMode()
        switch activity {
        case .twoMinuteTest:
            return .twoMinuteGetReady(mode: m)
        case .awayFromPressure:
            return .awayFromPressureSetup(mode: m)
        case .dribbleOrPass:
            return .dribbleOrPassSetup(mode: m)
        case .oneTouchPassing:
            return .oneTouchPassingSetup(mode: m)
        }
    }

    private static func savedRole(for activity: ActivityKind) -> String? {
        if let global = UserDefaults.standard.string(forKey: globalLastRoleKey) {
            return global
        }

        let key: String
        switch activity {
        case .twoMinuteTest:
            key = twoMinuteLastRoleKey
        case .awayFromPressure:
            key = awayFromPressureLastRoleKey
        case .dribbleOrPass:
            key = dribbleOrPassLastRoleKey
        case .oneTouchPassing:
            key = oneTouchPassingLastRoleKey
        }
        return UserDefaults.standard.string(forKey: key)
    }
}
