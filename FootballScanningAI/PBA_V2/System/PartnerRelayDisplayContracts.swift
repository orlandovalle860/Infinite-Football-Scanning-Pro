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
/// **Adoption:** Hold `@StateObject private var relay = PartnerRelayDisplaySession()` (or inject a test double
/// conforming to this protocol). On partner appear (relay mode): set callback, `await relay.startDisplaySession()`.
/// On disappear: `relay.tearDown()`. Read `joinCode` / `socketConnectionState` / `isCoachPaired` for UI, or use
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
