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
        false
    }

    static func shouldShowWaitingForCoach(isAwaitingCoachInput: Bool) -> Bool {
        TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive && isAwaitingCoachInput
    }

    static func handleResultsPresented() {
        // Keep result-state data alive while the full summary screen builds and renders.
        // Ending/clearing should happen from explicit exit actions after results are shown.
    }

    static func routeForActivityLaunch(_ activity: ActivityKind) -> AppRoute {
        switch activity {
        case .twoMinuteTest:
            return .twoMinuteGetReady(mode: .partner)
        case .awayFromPressure:
            return .awayFromPressureSetup(mode: .partner)
        case .dribbleOrPass:
            return .dribbleOrPassSetup(mode: .partner)
        case .oneTouchPassing:
            return .oneTouchPassingSetup(mode: .partner)
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
