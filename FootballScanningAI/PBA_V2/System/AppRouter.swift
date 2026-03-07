//
//  AppRouter.swift
//  FootballScanningAI
//
//  Path-based navigation. popToRoot() clears the path and returns to Home.
//

import Combine
import SwiftUI

/// Route enum for path-based navigation. Clearing path returns to root.
enum AppRoute: Hashable {
    case twoMinuteRoleSelection
    case coachRemote
    case twoMinuteCoachRemote
    case curriculum
    case progress
    case warmup(DisplayMode)
    case trainingModeSelection(activityTitle: String)
    case twoMinuteSetup(mode: TrainingMode)
    case twoMinuteGetReady(mode: TrainingMode, difficulty: TestDifficulty)
    /// Path from curriculum Train: role selection for each activity (avoids nested navigationDestination on curriculum).
    case awayFromPressureRoleSelection
    case awayFromPressureTrainingModeSelection
    case awayFromPressureSetup(mode: TrainingMode)
    case dribbleOrPassRoleSelection
    case dribbleOrPassTrainingModeSelection
    case dribbleOrPassSetup(mode: TrainingMode)
    case oneTouchPassingRoleSelection
    case oneTouchPassingTrainingModeSelection
    case oneTouchPassingSetup(mode: TrainingMode)
    /// Tester mode only: debug menu reachable from Home via toolbar.
    case debugMenu
}

final class AppRouter: ObservableObject {
    /// Path-driven stack: when cleared, we're at root. Home button clears path.
    @Published var path = NavigationPath()

    var pathBinding: Binding<NavigationPath> {
        Binding(get: { [weak self] in self?.path ?? NavigationPath() },
                set: { [weak self] in self?.path = $0 })
    }

    /// For debugging: number of entries in the path (root not included).
    var pathCount: Int { path.count }

    func push(_ route: AppRoute) {
        withAnimation(.easeInOut(duration: 0.35)) {
            var p = path
            p.append(route)
            path = p
        }
    }

    /// Clear the navigation path so the stack returns to root (Home). One tap from any deep screen.
    func popToRoot() {
        withAnimation(.easeInOut(duration: 0.25)) {
            path = NavigationPath()
        }
    }
}
