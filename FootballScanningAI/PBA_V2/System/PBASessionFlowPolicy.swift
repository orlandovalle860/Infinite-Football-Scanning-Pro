import Foundation

enum PBASessionFlowPolicy {
    private static let twoMinuteLastRoleKey = "twoMinuteTest.lastSelectedDeviceRole"

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
            if UserDefaults.standard.string(forKey: twoMinuteLastRoleKey) == "coachRemote" {
                return .coachRemote
            }
            return .trainingModeSelection(activityTitle: "2-Minute Test")
        case .awayFromPressure:
            return skipRole ? .awayFromPressureTrainingModeSelection : .awayFromPressureRoleSelection
        case .dribbleOrPass:
            return skipRole ? .dribbleOrPassTrainingModeSelection : .dribbleOrPassRoleSelection
        case .oneTouchPassing:
            return skipRole ? .oneTouchPassingTrainingModeSelection : .oneTouchPassingRoleSelection
        }
    }
}
