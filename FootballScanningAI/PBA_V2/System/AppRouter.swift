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
    case achievements
    case warmupHub
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
#if DEBUG
    /// Tester Tools: debug menu from Home toolbar (not in Release).
    case debugMenu
#endif
}

@MainActor
final class AppRouter: ObservableObject {
    /// Typed stack (newest / deepest route is last). Prefer this over `NavigationPath` so
    /// `NavigationStack(path:)` updates stay stable and Xcode logs fewer
    /// “NavigationAuthority bound path tried to update multiple times per frame” warnings.
    @Published var path: [AppRoute] = []

    /// Two-way binding for `NavigationStack(path:)` — updates must stay on the main actor / main thread.
    var pathBinding: Binding<[AppRoute]> {
        Binding(
            get: { self.path },
            set: { newValue in
                if Thread.isMainThread {
                    guard self.path != newValue else { return }
                    self.path = newValue
                } else {
                    DispatchQueue.main.async {
                        guard self.path != newValue else { return }
                        self.path = newValue
                    }
                }
            }
        )
    }

    /// For debugging: number of entries in the path (root not included).
    var pathCount: Int { path.count }

    func push(_ route: AppRoute) {
        if Thread.isMainThread {
            withAnimation(.easeInOut(duration: 0.35)) {
                path.append(route)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.path.append(route)
                }
            }
        }
    }

    /// Clear the navigation path so the stack returns to root (Home). One tap from any deep screen.
    ///
    /// **Partner relay / Multipeer:** By default this does **not** end the partner training session, so the same
    /// join code and transport can be reused after Home → Pathway → another partner activity. Call with
    /// `endingPartnerSession: true` only when the user explicitly abandons training (e.g. “Leave” in a drill alert).
    func popToRoot(endingPartnerSession: Bool = false) {
        if endingPartnerSession {
            #if DEBUG
            PartnerPersistDebug.log("AppRouter.popToRoot(endingPartnerSession:true) — ending partner training session")
            #endif
            TrainingPartnerConnectionCoordinator.shared.endPartnerTrainingSession(reason: "AppRouter.popToRoot(endingPartnerSession:true)")
        } else {
            #if DEBUG
            let active = TrainingPartnerConnectionCoordinator.shared.isPartnerTrainingSessionActive
            print("[Multipeer] TrainingPartnerSession: popToRoot — preserving pairing (navigation only); isPartnerTrainingSessionActive=\(active)")
            PartnerPersistDebug.log("AppRouter.popToRoot — navigation only (preserve pairing if active); isPartnerTrainingSessionActive=\(active)")
            #endif
        }
        if Thread.isMainThread {
            withAnimation(.easeInOut(duration: 0.25)) {
                path.removeAll(keepingCapacity: false)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.path.removeAll(keepingCapacity: false)
                }
            }
        }
    }

    /// Pops one level (e.g. activity coach remote → Coach Remote hub). No-op if the stack is empty.
    func popLast() {
        guard !path.isEmpty else { return }
        if Thread.isMainThread {
            withAnimation(.easeInOut(duration: 0.25)) {
                _ = path.popLast()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    _ = self.path.popLast()
                }
            }
        }
    }
}
