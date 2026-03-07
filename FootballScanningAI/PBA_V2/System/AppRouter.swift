//
//  AppRouter.swift
//  FootballScanningAI
//
//  Path-based navigation so popToRoot() clears the path and returns to Home.
//

import Combine
import SwiftUI

/// Holds the navigation stack identity. Root view owns this and uses it for .id(); router updates it on popToRoot() so the root re-renders even when called from deep in the stack.
final class NavigationRootId: ObservableObject {
    @Published var id = UUID()
}

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
}

final class AppRouter: ObservableObject {
    @Published var rootId = UUID()
    /// Path-driven stack: when cleared, we're at root. Home button sets path = NavigationPath().
    @Published var path = NavigationPath()

    weak var navigationRootId: NavigationRootId?
    var onPopToRoot: (() -> Void)?

    var pathBinding: Binding<NavigationPath> {
        Binding(get: { [weak self] in self?.path ?? NavigationPath() },
                set: { [weak self] in self?.path = $0 })
    }

    func push(_ route: AppRoute) {
        var p = path
        p.append(route)
        path = p
    }

    /// Call from any screen (e.g. toolbar home button or Leave in alert) to return to Home.
    func popToRoot() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.path = NavigationPath()
            self.onPopToRoot?()
        }
        navigationRootId?.id = UUID()
        rootId = UUID()
        NotificationCenter.default.post(name: .requestPopToRoot, object: nil)
    }
}
