import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Player iPad (AppRole.player) does not locally push into PBA training flows; Coach Remote starts sessions.
/// When a blocked push is attempted: show pairing prompt only if no coach link; if a link exists, ignore (no prompt, no navigation).
enum CoachRemoteSessionStartGate {
    /// iPad in player display mode — local UI must not push into partner / PBA session flows.
    @MainActor
    static func isPadPlayerRole() -> Bool {
        #if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        #else
        return false
        #endif
        let raw = UserDefaults.standard.string(forKey: AppRole.storageKey) ?? AppRole.player.rawValue
        return AppRole.resolved(from: raw) == .player
    }

    /// Multipeer peer, relay paired, or coach relay WebSocket. Used for **Coach Remote (phone)** and legacy checks — not for iPad display passive routing.
    @MainActor
    static func coachDeviceIsPresent() -> Bool {
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        if ConnectionManager.shared.connectedPeerName != nil { return true }
        if coordinator.relayDisplaySession.isCoachPaired { return true }
        if coordinator.coachRelayRemoteService.connectionState == .connected { return true }
        return false
    }

    /// **iPad display only:** coach link from relay (`peer_joined`) or shared coach relay WebSocket — **no Multipeer**. Drives passive standby / root without any local UI tap.
    @MainActor
    static func iPadDisplayCoachRelayLinkIsLive() -> Bool {
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        if coordinator.relayDisplaySession.isCoachPaired { return true }
        if coordinator.coachRelayRemoteService.connectionState == .connected { return true }
        return false
    }

    /// Partner / PBA session entry routes that must not be started from the iPad player UI.
    @MainActor
    static func shouldBlock(_ route: AppRoute) -> Bool {
        guard route.requiresCoachRemotePhoneToStartOnPad else { return false }
        return isPadPlayerRole()
    }
}

extension AppRoute {
    /// Routes that begin a PBA or 2-Minute **training** flow (not hub / warmups / shell screens).
    var requiresCoachRemotePhoneToStartOnPad: Bool {
        switch self {
        case .twoMinuteRoleSelection, .twoMinuteSetup, .twoMinuteGetReady,
             .awayFromPressureRoleSelection, .awayFromPressureTrainingModeSelection, .awayFromPressureSetup,
             .dribbleOrPassRoleSelection, .dribbleOrPassTrainingModeSelection, .dribbleOrPassSetup,
             .oneTouchPassingRoleSelection, .oneTouchPassingTrainingModeSelection, .oneTouchPassingSetup,
             .trainingModeSelection:
            return true
        case .coachRemote, .twoMinuteCoachRemote, .dribbleOrPassCoachRemote, .awayFromPressureCoachRemote, .oneTouchPassingCoachRemote,
             .curriculum, .progress, .achievements, .warmupHub, .warmup, .debugMenu:
            return false
        }
    }
}

extension AppRouter {
    /// On iPad (AppRole.player), blocked training routes: prompt only when not connected; when connected, no-op (no prompt, no push).
    @MainActor
    func pushRespectingCoachRemotePadGate(_ route: AppRoute, coachRemotePrompt: CoachRemoteRequiredPromptController) {
        if CoachRemoteSessionStartGate.shouldBlock(route) {
            if CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive() {
                return
            }
            coachRemotePrompt.present(pendingRoute: nil)
            return
        }
        push(route)
    }
}
