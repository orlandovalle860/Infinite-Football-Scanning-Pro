//
//  CoachRemoteButtonFeedback.swift
//  FootballScanningAI
//
//  Non-blocking press feedback for coach remote taps (~100ms visual + light haptic).
//  Does not delay actions or transport.
//

import SwiftUI
import UIKit

enum CoachRemoteHaptics {
    /// Light impact for PASS and direction taps (non-blocking).
    static func lightImpact() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }
}

/// Wraps a tappable control with scale + flash. Calls `action` synchronously first, then animates.
struct CoachRemoteFeedbackTap<Label: View>: View {
    enum Kind {
        /// Soft yellow tint flash (PASS).
        case pass
        /// Light blue tint flash (direction / pad).
        case direction
    }

    let kind: Kind
    let clipCornerRadius: CGFloat
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var scale: CGFloat = 1
    @State private var flashOpacity: CGFloat = 0

    var body: some View {
        Button {
            CoachRemoteHaptics.lightImpact()
            action()
            pulseVisual()
        } label: {
            ZStack {
                label()
                RoundedRectangle(cornerRadius: clipCornerRadius)
                    .fill(flashColor)
                    .opacity(Double(flashOpacity))
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: clipCornerRadius))
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
    }

    private var flashColor: Color {
        switch kind {
        case .pass:
            return Color(red: 1, green: 0.93, blue: 0.48)
        case .direction:
            return Color(red: 0.62, green: 0.76, blue: 0.98)
        }
    }

    private func pulseVisual() {
        withAnimation(.easeOut(duration: 0.05)) {
            scale = 0.96
            flashOpacity = kind == .pass ? 0.26 : 0.18
        }
        withAnimation(.easeOut(duration: 0.05).delay(0.05)) {
            scale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.05)) {
                flashOpacity = 0
            }
        }
    }
}
