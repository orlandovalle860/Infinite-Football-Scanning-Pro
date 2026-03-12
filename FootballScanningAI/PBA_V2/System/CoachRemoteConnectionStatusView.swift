//
//  CoachRemoteConnectionStatusView.swift
//  FootballScanningAI
//
//  Visible connection status indicator for iPad training screen (partner mode).
//  Updates automatically from ConnectionManager.connectionState.
//

import SwiftUI

/// Displays connection status for the iPad when in partner mode.
/// Shows: Searching for Coach Remote | Connecting | Coach Remote Connected | Connection Lost
struct CoachRemoteConnectionStatusView: View {
    let connectionState: ConnectionState

    private var statusText: String {
        switch connectionState {
        case .searching: return "Searching for Coach Remote"
        case .connecting: return "Connecting"
        case .connected: return "Coach Remote Connected"
        case .disconnected: return "Connection Lost"
        }
    }

    private var statusEmoji: String {
        switch connectionState {
        case .searching: return "🔴"
        case .connecting: return "🟡"
        case .connected: return "🟢"
        case .disconnected: return "🔴"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(statusEmoji)
                .font(.subheadline)
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(10)
    }

    private var textColor: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .searching: return .white.opacity(0.9)
        case .disconnected: return .orange
        }
    }

    private var backgroundColor: Color {
        switch connectionState {
        case .connected: return Color.green.opacity(0.15)
        case .connecting: return Color.yellow.opacity(0.12)
        case .searching: return Color.white.opacity(0.08)
        case .disconnected: return Color.orange.opacity(0.15)
        }
    }
}
