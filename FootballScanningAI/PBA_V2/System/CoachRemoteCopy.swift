//
//  CoachRemoteCopy.swift
//  FootballScanningAI
//
//  Shared coach-remote UI copy and small layout components. Does not affect relay payloads.
//

import SwiftUI

// MARK: - Copy

enum CoachRemoteCopy {
    /// Ready state — headline when connected and waiting for NEXT REP.
    static let readyForNextRep = "Ready for next rep"

    /// PASS step — timing input (after cue on Display).
    static let passTimingInstruction = "When the cue happens, tap PASS"

    /// Direction step — coach records outcome; app scores correctness.
    static let playerDecisionQuestion = "What did the player choose?"

    /// Away From Pressure — coach logs the player’s turn; correct = opposite the red pressure (single gate per rep).
    static let awayFromPressurePlayerDecisionPrompt = "Log their turn away from pressure (opposite the red is correct)."

    /// Subtle note: volume still triggers PASS (hardware path unchanged).
    static let volumePassHint = "Volume keys also send PASS"

    /// Multipeer setup — one short line.
    static let multipeerSetupHint = "Same Wi‑Fi · allow Local Network · Display on session screen"

    /// Legacy combined prompt (avoid for new layouts; prefer `playerDecisionQuestion` + `CoachRemoteIncorrectPadButton`).
    static let logPlayerDecisionPrompt = "Tap the direction they chose, or ✕ if wrong."
}

// MARK: - Subtle connection status (not the primary focus)

struct CoachRemoteConnectionStatusBar: View {
    let isRelay: Bool
    let peerDisplayName: String?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green.opacity(0.7))
                .frame(width: 6, height: 6)
            Text(statusLine)
                .font(.caption)
                .foregroundColor(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        if isRelay { return "Connected · relay" }
        if let n = peerDisplayName, !n.isEmpty { return "Connected · \(n)" }
        return "Connected"
    }
}

// MARK: - De-emphasized center control (still sends `incorrectDecision`)

struct CoachRemoteIncorrectPadButton: View {
    let action: () -> Void

    var body: some View {
        CoachRemoteFeedbackTap(kind: .direction, clipCornerRadius: 10, action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .accessibilityLabel("Other outcome")
    }
}
