import Combine
import SwiftUI

/// Presents the fullscreen “use your phone as Coach Remote” message when an iPad in
/// player display mode (AppRole.player) attempts to start a training flow locally.
@MainActor
final class CoachRemoteRequiredPromptController: ObservableObject {
    @Published var isPresented = false
    /// Player-route to open automatically once a coach link is live (relay paired / Multipeer / coach relay socket).
    @Published private(set) var pendingSessionRoute: AppRoute?

    func present(pendingRoute: AppRoute? = nil) {
        pendingSessionRoute = pendingRoute
        isPresented = true
        Task { @MainActor in
            await TrainingPartnerConnectionCoordinator.shared.warmUpCoachLinkSurfaceOnPlayerDisplayIfNeeded()
        }
    }

    func dismiss() {
        isPresented = false
        pendingSessionRoute = nil
    }

    /// Called when the cover is dismissed (gesture or programmatic) so stale routes are not auto-pushed later.
    func clearPendingSessionAfterDismiss() {
        pendingSessionRoute = nil
    }

    /// Dismisses the prompt and pushes the blocked training route once the coach is present.
    func performAutoEnterPendingSession(router: AppRouter) {
        guard let route = pendingSessionRoute else { return }
        pendingSessionRoute = nil
        isPresented = false
        DispatchQueue.main.async {
            router.push(route)
        }
    }
}
