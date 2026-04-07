//
//  PartnerRelayDisplayContracts.swift
//  FootballScanningAI
//
//  Lightweight contracts + UI helpers for partner activities using `PartnerRelayDisplaySession`.
//

import Combine
import SwiftUI

// MARK: - Display relay contract

/// Display-side relay surface: join code, socket lifecycle, coach paired (`peer_joined` / `peer_left`),
/// and start/stop. Activities wire `onCoachPairingChanged` into their session / pairing model.
///
/// **Adoption:** Use ``TrainingPartnerConnectionCoordinator.shared.relayDisplaySession`` for partner training so
/// relay + join code persist across activity changes; call `await relay.startDisplaySessionIfNeeded()` on each
/// activity display. Tear down only via ``TrainingPartnerConnectionCoordinator.endPartnerTrainingSession(reason:)`` (e.g.
/// explicit Leave training, coach hub end, or `popToRoot(endingPartnerSession: true)`). iOS background only **suspends** relay.
/// `onDisappear` or plain Home navigation. Read `joinCode` / `socketConnectionState` /
/// `isCoachPaired` for UI, or use
/// ``PartnerRelayDisplayUI/statusConnectionState(socketState:isCoachPairedWithRelay:)`` for a single status `ConnectionState`.
protocol PartnerRelayDisplayControlling: AnyObject, ObservableObject {
    var joinCode: String? { get }
    var socketConnectionState: ConnectionState { get }
    /// `true` after relay control `peer_joined`, cleared on `peer_left` or socket disconnect.
    var isCoachPaired: Bool { get }
    var onCoachPairingChanged: ((Bool) -> Void)? { get set }

    func startDisplaySession() async
    func tearDown()
}

extension PartnerRelayDisplaySession: PartnerRelayDisplayControlling {}

// MARK: - UI mapping (shared pattern)

enum PartnerRelayDisplayUI {
    /// Maps relay socket state + whether the activity considers the coach paired (usually mirrored from
    /// `onCoachPairingChanged`) into one `ConnectionState` for ``CoachRemoteConnectionStatusView`` and similar.
    ///
    /// Rule: socket disconnected → `.disconnected`; coach paired → `.connected`; else `.connecting`
    /// (relay socket up but waiting for `peer_joined`).
    static func statusConnectionState(
        socketState: ConnectionState,
        isCoachPairedWithRelay: Bool
    ) -> ConnectionState {
        if socketState == .disconnected { return .disconnected }
        if isCoachPairedWithRelay { return .connected }
        return .connecting
    }
}

// MARK: - Join code banner (DEBUG relay)

// MARK: - Relay lifecycle (foreground reconnect)

/// Top banner for partner WebSocket reconnect / resync (coach + display).
struct PartnerRelayLifecycleBannerOverlay: View {
    @ObservedObject private var coordinator = TrainingPartnerConnectionCoordinator.shared

    var body: some View {
        Group {
            if case .hidden = coordinator.relayLifecycleBanner {
                EmptyView()
            } else {
                VStack {
                    bannerLabel
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(bannerBackground)
                        .cornerRadius(12)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var bannerLabel: some View {
        switch coordinator.relayLifecycleBanner {
        case .hidden:
            EmptyView()
        case .reconnecting:
            Text("Reconnecting…")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        case .restoringSession:
            Text("Restoring session…")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        case .connectionRestored:
            Text("Connection restored")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        case .sessionRestoredSoft:
            Text("Session restored")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        case .sessionRequiresRejoin:
            VStack(alignment: .center, spacing: 6) {
                Text("Session ended — rejoin required")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text("Enter the join code from the display again, or restart partner training from the hub.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        case .checkpointMismatch(let hint):
            Text(hint)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
    }

    private var bannerBackground: Color {
        switch coordinator.relayLifecycleBanner {
        case .sessionRequiresRejoin, .checkpointMismatch:
            return Color.red.opacity(0.42)
        case .reconnecting, .restoringSession:
            return Color.blue.opacity(0.5)
        case .connectionRestored, .sessionRestoredSoft:
            return Color.green.opacity(0.4)
        case .hidden:
            return .clear
        }
    }
}

/// Shows the relay join code for coach entry; hide when `joinCode` is nil.
struct PartnerRelayJoinCodeBanner: View {
    let joinCode: String?

    var body: some View {
        if let code = joinCode {
            VStack(spacing: 6) {
                Text("Relay join code")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.cyan.opacity(0.9))
                Text(code)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(12)
                Text("Enter on coach iPhone: Relay DEBUG")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 4)
        }
    }
}
