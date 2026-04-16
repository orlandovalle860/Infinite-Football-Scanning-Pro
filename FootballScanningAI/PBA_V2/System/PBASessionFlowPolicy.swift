import Foundation

enum PBASessionFlowPolicy {
    private static let globalLastRoleKey = "pba.lastSelectedDeviceRole"
    private static let twoMinuteLastRoleKey = "twoMinuteTest.lastSelectedDeviceRole"
    private static let awayFromPressureLastRoleKey = "awayFromPressure.lastSelectedDeviceRole"
    private static let dribbleOrPassLastRoleKey = "dribbleOrPass.lastSelectedDeviceRole"
    private static let oneTouchPassingLastRoleKey = "oneTouchPassing.lastSelectedDeviceRole"

    static func shouldSkipConnectionPrompts() -> Bool {
        TrainingPartnerConnectionCoordinator.shared.isConnected
    }

    static func shouldPromptCalibration(for mode: TrainingMode) -> Bool {
        PartnerPassTempoCalibrationStore.requiresCalibration(for: mode)
    }

    static func shouldShowWaitingForCoach(isAwaitingCoachInput: Bool) -> Bool {
        TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive && isAwaitingCoachInput
    }

    static func handleResultsPresented() {
        // Keep result-state data alive while the full summary screen builds and renders.
        // Ending/clearing should happen from explicit exit actions after results are shown.
    }

    static func routeForActivityLaunch(_ activity: ActivityKind) -> AppRoute {
        let skipRole = shouldSkipConnectionPrompts()
        switch activity {
        case .twoMinuteTest:
            guard skipRole else { return .twoMinuteRoleSelection }
            if savedRole(for: activity) == "coachRemote" {
                return .coachRemote
            }
            return .trainingModeSelection(activityTitle: "2-Minute Test")
        case .awayFromPressure:
            guard skipRole else { return .awayFromPressureRoleSelection }
            if savedRole(for: activity) == "coachRemote" {
                return .awayFromPressureCoachRemote
            }
            return .awayFromPressureTrainingModeSelection
        case .dribbleOrPass:
            guard skipRole else { return .dribbleOrPassRoleSelection }
            if savedRole(for: activity) == "coachRemote" {
                return .dribbleOrPassCoachRemote
            }
            return .dribbleOrPassTrainingModeSelection
        case .oneTouchPassing:
            guard skipRole else { return .oneTouchPassingRoleSelection }
            if savedRole(for: activity) == "coachRemote" {
                return .oneTouchPassingCoachRemote
            }
            return .oneTouchPassingTrainingModeSelection
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
