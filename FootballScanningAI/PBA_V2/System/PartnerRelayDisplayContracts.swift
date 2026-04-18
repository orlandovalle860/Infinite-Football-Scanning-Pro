//
//  PartnerRelayDisplayContracts.swift
//  FootballScanningAI
//
//  Lightweight contracts + UI helpers for partner activities using `PartnerRelayDisplaySession`.
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Partner display layout (iPad field screens)

enum PartnerDisplayLayout {
    /// Pushes the drill focal point (center X / ball) down on iPad so top chrome breathes.
    static var drillFocalCenterYOffset: CGFloat {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad ? 52 : 0
        #else
        0
        #endif
    }
}

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
        case .reconnectedRestartingRep:
            Text("Reconnected — restarting rep")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        case .sessionRequiresRejoin:
            EmptyView()
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
        case .connectionRestored, .sessionRestoredSoft, .reconnectedRestartingRep:
            return Color.green.opacity(0.4)
        case .hidden:
            return .clear
        }
    }
}

// MARK: - Passive partner link status (coach + display)

/// Small, non-blocking copy for relay **and** Multipeer. Observes shared singletons so SwiftUI updates on any path.
struct PartnerLinkPassiveStatusLine: View {
    enum Role {
        case coach
        case display
    }

    /// Coach-only: tighter copy under the session header (rep row).
    enum CoachPresentation {
        case standard
        case sessionRepHeader
    }

    /// Display-only: pill badge vs centered status-bar line.
    enum DisplayPresentation {
        case pill
        case statusBar
    }

    let role: Role
    var coachPresentation: CoachPresentation = .standard
    var displayPresentation: DisplayPresentation = .pill

    @ObservedObject private var coordinator = TrainingPartnerConnectionCoordinator.shared
    @ObservedObject private var relayDisplay = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
    @ObservedObject private var multipeer = ConnectionManager.shared
    @ObservedObject private var coachRelay = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService

    var body: some View {
        Group {
            if coordinator.isMidSessionPartnerDisconnect {
                EmptyView()
            } else if let text = statusText {
                switch role {
                case .coach:
                    Text(text)
                        .font(coachPresentation == .sessionRepHeader ? .caption : .subheadline)
                        .fontWeight(.regular)
                        .foregroundColor(.white.opacity(coachPresentation == .sessionRepHeader ? 0.6 : 0.55))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(text)
                case .display:
                    switch displayPresentation {
                    case .pill:
                        Text(text)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.38))
                            .cornerRadius(8)
                            .accessibilityLabel(text)
                    case .statusBar:
                        Text(text)
                            .font(.caption)
                            .fontWeight(.regular)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(text)
                    }
                }
            }
        }
    }

    private var statusText: String? {
        switch role {
        case .coach:
            return PartnerLinkPassiveStatusFormatting.coachLine(
                isPartnerTrainingSessionActive: coordinator.isPartnerTrainingSessionActive,
                relayBanner: coordinator.relayLifecycleBanner,
                multipeerPeerName: multipeer.connectedPeerName,
                multipeerState: multipeer.connectionState,
                coachRelayState: coachRelay.connectionState,
                coachRelayDisplayPeerPresent: coordinator.coachRelayDisplayPeerPresent
            )
        case .display:
            return PartnerLinkPassiveStatusFormatting.displayLine(
                isPartnerTrainingSessionActive: coordinator.isPartnerTrainingSessionActive,
                relayBanner: coordinator.relayLifecycleBanner,
                multipeerPeerName: multipeer.connectedPeerName,
                multipeerState: multipeer.connectionState,
                relaySocket: relayDisplay.socketConnectionState,
                relayCoachPaired: relayDisplay.isCoachPaired
            )
        }
    }
}

/// Top chrome for iPad/display drills: centered coach link line, then rep + tempo stacked top-leading (de-emphasized).
struct PartnerDisplaySessionTopChrome: View {
    var showCoachConnectionLine: Bool
    var showRepAndTempo: Bool
    var repLine: String
    var tempoLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showCoachConnectionLine {
                PartnerLinkPassiveStatusLine(role: .display, displayPresentation: .statusBar)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            if showRepAndTempo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repLine)
                        .font(.caption.monospacedDigit())
                        .fontWeight(.regular)
                        .foregroundColor(.white.opacity(0.6))
                    Text(tempoLine)
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, showCoachConnectionLine ? 16 : 12)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Full-screen scrim mid-drill when the partner link drops; either side can start fresh without ending the whole pairing run or restarting the app.
struct PartnerMidSessionDisconnectRecoveryOverlay: View {
    @ObservedObject private var coordinator = TrainingPartnerConnectionCoordinator.shared
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if coordinator.isMidSessionPartnerDisconnect {
                ZStack {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                    VStack(spacing: 20) {
                        VStack(spacing: 6) {
                            Text(primaryMessage)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Text("Session ended")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        Text(subtitleMessage)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                        Button {
                            if CoachRemoteSessionStartGate.isPadPlayerRole() {
                                Task {
                                    await coordinator.startNewPartnerSessionFromDisconnect(router: router)
                                }
                            } else {
                                coordinator.handleCoachEnterCodeAfterDisplayUnavailable(router: router)
                            }
                        } label: {
                            Text(primaryActionTitle)
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.yellow)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
                }
                .transition(.opacity)
            }
        }
    }

    private var primaryMessage: String {
        CoachRemoteSessionStartGate.isPadPlayerRole()
            ? "Remote disconnected"
            : "Display unavailable"
    }

    private var subtitleMessage: String {
        CoachRemoteSessionStartGate.isPadPlayerRole()
            ? "Start a new relay session on this iPad. The coach will need the new join code."
            : "Return to the join screen and enter the code shown on the iPad."
    }

    private var primaryActionTitle: String {
        CoachRemoteSessionStartGate.isPadPlayerRole()
            ? "Start New Session"
            : "Enter Code"
    }
}

private enum PartnerLinkPassiveStatusFormatting {
    static func coachLine(
        isPartnerTrainingSessionActive: Bool,
        relayBanner: PartnerRelayLifecycleBanner,
        multipeerPeerName: String?,
        multipeerState: ConnectionState,
        coachRelayState: ConnectionState,
        coachRelayDisplayPeerPresent: Bool
    ) -> String? {
        guard isPartnerTrainingSessionActive else { return nil }
        switch relayBanner {
        case .reconnecting, .restoringSession:
            return "Reconnecting..."
        default:
            break
        }
        if multipeerPeerName != nil {
            return "Connected to iPad"
        }
        if coachRelayState == .connected && coachRelayDisplayPeerPresent {
            return "Connected to iPad"
        }
        if coachRelayState == .connected && !coachRelayDisplayPeerPresent {
            return "Reconnecting..."
        }
        if coachRelayState == .searching || coachRelayState == .connecting {
            return "Reconnecting..."
        }
        if multipeerState == .searching || multipeerState == .connecting {
            return "Reconnecting..."
        }
        return "Disconnected"
    }

    static func displayLine(
        isPartnerTrainingSessionActive: Bool,
        relayBanner: PartnerRelayLifecycleBanner,
        multipeerPeerName: String?,
        multipeerState: ConnectionState,
        relaySocket: ConnectionState,
        relayCoachPaired: Bool
    ) -> String? {
        guard isPartnerTrainingSessionActive else { return nil }
        if multipeerPeerName != nil {
            return "Connected to coach"
        }
        switch relayBanner {
        case .reconnecting, .restoringSession:
            return "Waiting for coach..."
        default:
            break
        }
        if relaySocket == .connected && relayCoachPaired {
            return "Connected to coach"
        }
        if relaySocket == .searching || relaySocket == .connecting || (relaySocket == .connected && !relayCoachPaired) {
            return "Waiting for coach..."
        }
        if multipeerState == .searching || multipeerState == .connecting {
            return "Waiting for coach..."
        }
        return "Connection lost"
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
