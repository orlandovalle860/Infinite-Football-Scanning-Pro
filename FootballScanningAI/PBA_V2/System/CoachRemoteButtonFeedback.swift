//
//  CoachRemoteButtonFeedback.swift
//  FootballScanningAI
//
//  PASS + direction tap feedback. PASS uses shared trigger path (touch + volume) with double-pulse
//  rigid haptics, debounce, and [CoachTrigger-Debug] / [HapticDebug] logs.
//

import SwiftUI
import UIKit

enum CoachPassTriggerSource: String {
    case touch
    case volume
}

/// Shared PASS trigger: haptic first (no network wait), debounce, debug log, then `send`.
enum CoachRemotePassTrigger {
    /// Minimal debounce to reduce accidental double-fires (~150 ms).
    static let debounceSeconds: TimeInterval = 0.15

    private static var lastPassFireAt: [String: TimeInterval] = [:]

    /// Returns `true` if `send` was invoked (not debounced).
    @discardableResult
    static func perform(
        source: CoachPassTriggerSource,
        activity: String,
        repIndex: Int,
        send: () -> Void
    ) -> Bool {
        let key = "\(activity)#\(repIndex)"
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPassFireAt[key], now - last < debounceSeconds {
            print("[CoachTrigger-Debug] suppressed duplicate source=\(source.rawValue) activity=\(activity) repIndex=\(repIndex) deltaSeconds=\(String(format: "%.3f", now - last))")
            return false
        }
        lastPassFireAt[key] = now

        CoachRemoteHaptics.passTriggerDoublePulse(source: source)

        let ts = Date()
        print("[CoachTrigger-Debug] trigger source=\(source.rawValue) timestamp=\(ts.timeIntervalSince1970) activity=\(activity) repIndex=\(repIndex)")

        send()
        return true
    }
}

enum CoachRemoteHaptics {
    /// Second impact ~70 ms after first; total felt pattern stays under ~150 ms. Non-blocking.
    private static let passDoublePulseInterval: TimeInterval = 0.07

    /// Set to `false` to use `.medium` + `.light` instead of `.rigid` + `.rigid` if rigid feels too strong.
    static var passTriggerUsesRigidDouble: Bool = true

    /// Double-pulse PASS confirmation for both touch and volume. First hit is synchronous; second is scheduled on main.
    static func passTriggerDoublePulse(source: CoachPassTriggerSource) {
        let ts = Date()
        let patternLabel = passTriggerUsesRigidDouble ? "double_pulse" : "double_pulse_fallback"
        let stylesLabel = passTriggerUsesRigidDouble ? "rigid+rigid" : "medium+light"
        print("[HapticDebug] trigger source=\(source.rawValue) timestamp=\(ts.timeIntervalSince1970) pattern=\(patternLabel) styles=\(stylesLabel) intervalMs=\(Int(passDoublePulseInterval * 1000))")

        if passTriggerUsesRigidDouble {
            let first = UIImpactFeedbackGenerator(style: .rigid)
            first.prepare()
            first.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + passDoublePulseInterval) {
                let second = UIImpactFeedbackGenerator(style: .rigid)
                second.prepare()
                second.impactOccurred()
            }
        } else {
            let first = UIImpactFeedbackGenerator(style: .medium)
            first.prepare()
            first.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + passDoublePulseInterval) {
                let second = UIImpactFeedbackGenerator(style: .light)
                second.prepare()
                second.impactOccurred()
            }
        }
    }

    /// Light impact for direction taps (non-blocking).
    static func lightImpact() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }
}

/// Large bottom-oriented PASS control: shared trigger path, brief highlight (~125 ms) on touch and optional volume echo.
struct CoachRemotePassPrimaryButton: View {
    let activity: String
    let repIndex: Int
    let send: () -> Void
    /// Increment from parent when volume triggers PASS so the button flashes in sync.
    @Binding var volumeFlashSignal: Int

    @State private var touchFlashOpacity: CGFloat = 0
    @State private var touchScale: CGFloat = 1

    private let cornerRadius: CGFloat = 20

    var body: some View {
        VStack(spacing: 8) {
            Button {
                let fired = CoachRemotePassTrigger.perform(
                    source: .touch,
                    activity: activity,
                    repIndex: repIndex,
                    send: send
                )
                if fired {
                    pulsePassVisual()
                }
            } label: {
                ZStack {
                    Text("PASS")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(Color.yellow)
                        .cornerRadius(cornerRadius)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(red: 1, green: 0.93, blue: 0.48))
                        .opacity(Double(touchFlashOpacity))
                        .allowsHitTesting(false)
                }
                .scaleEffect(touchScale)
            }
            .buttonStyle(.plain)
            Text(CoachRemoteCopy.volumePassHint)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
        .onChange(of: volumeFlashSignal) { _, _ in
            pulsePassVisual()
        }
    }

    private func pulsePassVisual() {
        withAnimation(.easeOut(duration: 0.05)) {
            touchScale = 0.97
            touchFlashOpacity = 0.28
        }
        withAnimation(.easeOut(duration: 0.05).delay(0.05)) {
            touchScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.125) {
            withAnimation(.easeOut(duration: 0.05)) {
                touchFlashOpacity = 0
            }
        }
    }
}

/// Wraps a tappable control with scale + flash. Calls `action` synchronously first, then animates.
struct CoachRemoteFeedbackTap<Label: View>: View {
    enum Kind {
        /// Soft yellow tint flash (PASS) — prefer `CoachRemotePassPrimaryButton` for PASS.
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
