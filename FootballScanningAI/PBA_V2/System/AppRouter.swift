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
    case dribbleOrPassCoachRemote
    case awayFromPressureCoachRemote
    case oneTouchPassingCoachRemote
    case curriculum
    case progress
    case warmup(DisplayMode)
    case trainingModeSelection(activityTitle: String)
    case twoMinuteSetup(mode: TrainingMode)
    case twoMinuteGetReady(mode: TrainingMode)
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

    /// Coalescing: at most one path update per run-loop iteration to avoid "multiple times per frame" warnings.
    private var pendingPath: NavigationPath?
    private var applyScheduled = false

    var pathBinding: Binding<NavigationPath> {
        Binding(get: { [weak self] in self?.path ?? NavigationPath() },
                set: { [weak self] newValue in
                    guard let self else { return }
                    setPathCoalesced(newValue)
                })
    }

    /// For debugging: number of entries in the path (root not included).
    var pathCount: Int { path.count }

    func push(_ route: AppRoute) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.push(route) }
            return
        }
        MainActor.assumeIsolated {
            var next = pendingPath ?? path
            next.append(route)
            pendingPath = next
            scheduleApply(animation: .easeInOut(duration: 0.35))
        }
    }

    /// Clear the navigation path so the stack returns to root (Home). One tap from any deep screen.
    func popToRoot() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.popToRoot() }
            return
        }
        MainActor.assumeIsolated {
            pendingPath = NavigationPath()
            scheduleApply(animation: .easeInOut(duration: 0.25))
        }
    }

    private func setPathCoalesced(_ newValue: NavigationPath) {
        MainActor.assumeIsolated {
            pendingPath = newValue
            scheduleApply(animation: nil)
        }
    }

    private func scheduleApply(animation: Animation?) {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyScheduled = false
                guard let next = self.pendingPath else { return }
                self.pendingPath = nil
                guard self.path != next else { return }
                if let animation {
                    withAnimation(animation) { self.path = next }
                } else {
                    self.path = next
                }
            }
        }
    }
}
