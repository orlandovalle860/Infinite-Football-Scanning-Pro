//
//  PartnerRelayPartnerStartViews.swift
//  FootballScanningAI
//
//  Shared display + coach UI for relay partner start (join code, minimal taps, auto-focus).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Join code length (server may vary; auto-submit uses this)

enum PartnerRelayCoachJoinKeyboard {
    /// Ensures the join-code field loses focus when transitioning to “Connected” / calibration.
    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

enum PartnerRelayJoinCodeConfig {
    /// Expected join code length for auto-submit after typing (HTTP API uses short alphanumeric codes).
    static let expectedCharacterCount: Int = 6
    /// Matches coach remote `start*CoachRelayJoin` banner while HTTP/WebSocket join is in progress.
    static let joiningStatusBannerText: String = "Joining relay…"
}

// MARK: - Display: prominent waiting overlay

/// Full-screen dimmed overlay: join code as soon as available, compact “getting code” state when `joinCode` is nil.
/// Use when `partnerTransportMode == .relayWebSocket` and waiting for coach pairing.
struct PartnerRelayDisplayWaitingOverlay: View {
    let joinCode: String?
    var activityTitle: String = "Training"
    /// Optional: show a subtle second line while the display’s DB session is still being created (e.g. Two Minute).
    var isDatabaseSessionCreating: Bool = false
    var scrimOpacity: CGFloat = 0.58
    var onExitSession: (() -> Void)? = nil
    @State private var showTimeoutHelper = false

    var body: some View {
        ZStack {
            Color.black.opacity(scrimOpacity)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                Text(activityTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .textCase(.uppercase)
                    .tracking(1)

                Text("Scan")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.96))
                    .multilineTextAlignment(.center)

                if let code = joinCode, !code.isEmpty {
                    VStack(spacing: 8) {
                        Text("Join code")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text(code)
                            .font(.system(size: 52, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.yellow.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                                    )
                            )
                    }
                    .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    Text(joinCode == nil ? "Waiting for coach..." : "Waiting to connect...")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white.opacity(0.88))
                    if joinCode != nil {
                        Text("Enter this join code on the coach device")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    if showTimeoutHelper {
                        VStack(spacing: 4) {
                            Text("Having trouble connecting?")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Make sure both devices are on the same WiFi")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            Text("or connected to the same hotspot")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 6)
                    }
                    if isDatabaseSessionCreating && joinCode != nil {
                        Text("Saving session…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.45))
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            PartnerPersistDebug.log("PartnerRelayDisplayWaitingOverlay onAppear (join-code / waiting UI)")
            showTimeoutHelper = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                showTimeoutHelper = true
            }
        }
    }
}

/// Two Minute (and similar): relay waiting + optional Supabase session error with retry.
struct PartnerRelayDisplayWaitingWithSessionErrorOverlay: View {
    let joinCode: String?
    var activityTitle: String = "Training"
    var isDatabaseSessionCreating: Bool
    var databaseSessionError: String?
    var onRetryDatabaseSession: () -> Void
    var onExitSession: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if let err = databaseSessionError, !err.isEmpty {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    if let code = joinCode, !code.isEmpty {
                        Text(code)
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.cyan.opacity(0.22))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                                    )
                            )
                    }
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            } else {
                PartnerRelayDisplayWaitingOverlay(
                    joinCode: joinCode,
                    activityTitle: activityTitle,
                    isDatabaseSessionCreating: isDatabaseSessionCreating,
                    scrimOpacity: 0.58,
                    onExitSession: onExitSession
                )
            }
        }
    }
}

// MARK: - Coach: join code field + primary action

/// Relay path on coach iPhone: auto-focus, optional auto-submit at ``PartnerRelayJoinCodeConfig/expectedCharacterCount``.
struct PartnerRelayCoachJoinSection: View {
    @Binding var joinCodeInput: String
    @FocusState.Binding var joinFieldFocused: Bool
    var joinBusy: Bool
    var joinBanner: String?
    /// Called when user taps Join or submits; also after auto-enter when code length matches.
    var onJoin: () -> Void

    @State private var lastAutoSubmittedCode: String?

    private var joinErrorText: String? {
        guard !joinBusy, let b = joinBanner?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty else {
            return nil
        }
        if Self.isJoiningBannerText(b) { return nil }
        return b
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Partner (relay)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.cyan.opacity(0.95))

            Text("Enter the code shown on the display")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Code", text: $joinCodeInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                .focused($joinFieldFocused)
                .submitLabel(.join)
                .onSubmit { onJoin() }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(joinErrorText != nil ? Color.orange.opacity(0.95) : Color.clear, lineWidth: 2)
                )
                .onAppear {
                    DispatchQueue.main.async {
                        joinFieldFocused = true
                    }
                }

            Text("Both devices must be on the same WiFi\nor connected to the same phone hotspot.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Join starts automatically when the code is complete, or press Join on the keyboard.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if joinBusy {
                HStack(alignment: .center, spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.95)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Joining…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.95))
                        Text("Connecting to the display. This may take a few seconds.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.12))
                .cornerRadius(10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Joining. Connecting to the display.")
            }

            if let err = joinErrorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't join")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.orange.opacity(0.98))
                    Text(err)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                )
                .cornerRadius(10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Join failed. \(err)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .onChange(of: joinCodeInput) { _, newValue in
            normalizeJoinCodeInput(newValue)
            if normalizedCode(from: joinCodeInput).count < PartnerRelayJoinCodeConfig.expectedCharacterCount {
                lastAutoSubmittedCode = nil
            }
            tryAutoSubmitIfNeeded()
        }
        .onChange(of: joinBusy) { wasBusy, nowBusy in
            if wasBusy && !nowBusy {
                // Defer one run loop so `joinBanner` matches the finished attempt (error vs cleared).
                DispatchQueue.main.async {
                    handleJoinFinishedTransition()
                }
            }
        }
    }

    /// When join attempt ends: on failure, clear auto-submit guard and refocus for quick correction (no transport changes).
    private func handleJoinFinishedTransition() {
        guard let b = joinBanner?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty else { return }
        guard !Self.isJoiningBannerText(b) else { return }
        lastAutoSubmittedCode = nil
        DispatchQueue.main.async {
            joinFieldFocused = true
        }
    }

    private static func isJoiningBannerText(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t == PartnerRelayJoinCodeConfig.joiningStatusBannerText { return true }
        if t.localizedCaseInsensitiveContains("joining relay") { return true }
        return false
    }

    private func normalizeJoinCodeInput(_ newValue: String) {
        let normalized = normalizedCode(from: newValue)
        if normalized != joinCodeInput {
            joinCodeInput = normalized
        }
    }

    private func normalizedCode(from s: String) -> String {
        let upper = s.uppercased()
        let filtered = upper.filter { $0.isLetter || $0.isNumber }
        return String(filtered.prefix(PartnerRelayJoinCodeConfig.expectedCharacterCount))
    }

    private func tryAutoSubmitIfNeeded() {
        let code = normalizedCode(from: joinCodeInput)
        guard code.count == PartnerRelayJoinCodeConfig.expectedCharacterCount else { return }
        guard !joinBusy else { return }
        guard code != lastAutoSubmittedCode else { return }
        lastAutoSubmittedCode = code
        onJoin()
    }

}
