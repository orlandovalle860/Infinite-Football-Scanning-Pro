//
//  CoachRemoteDirectionZoneInput.swift
//  FootballScanningAI
//
//  Full-screen coach direction input: tap anywhere → Gate. Shared across coach remote activities.
//

import SwiftUI
import UIKit

// MARK: - Debug

enum DirectionInputDebugLog {
    static func logAccepted(activity: String, gate: Gate, tapLocation: CGPoint, in size: CGSize, timestamp: Date = Date()) {
        let nx = size.width > 0 ? tapLocation.x / size.width : 0
        let ny = size.height > 0 ? tapLocation.y / size.height : 0
        print("[DirectionInput-Debug] activity=\(activity) status=accepted direction=\(gate.rawValue) tap=(x:\(String(format: "%.1f", tapLocation.x)),y:\(String(format: "%.1f", tapLocation.y))) size=(w:\(String(format: "%.1f", size.width)),h:\(String(format: "%.1f", size.height))) normalized=(x:\(String(format: "%.4f", nx)),y:\(String(format: "%.4f", ny))) centerDeadZoneHit=false timestamp=\(timestamp.timeIntervalSince1970)")
    }

    static func logIgnoredCenterDeadZone(activity: String, tapLocation: CGPoint, in size: CGSize, timestamp: Date = Date()) {
        let nx = size.width > 0 ? tapLocation.x / size.width : 0
        let ny = size.height > 0 ? tapLocation.y / size.height : 0
        print("[DirectionInput-Debug] activity=\(activity) status=ignored direction=nil tap=(x:\(String(format: "%.1f", tapLocation.x)),y:\(String(format: "%.1f", tapLocation.y))) size=(w:\(String(format: "%.1f", size.width)),h:\(String(format: "%.1f", size.height))) normalized=(x:\(String(format: "%.4f", nx)),y:\(String(format: "%.4f", ny))) centerDeadZoneHit=true timestamp=\(timestamp.timeIntervalSince1970)")
    }
}

// MARK: - Hit testing → Gate

enum CoachRemoteDirectionZoneResolver {
    /// Top and bottom bands are vertical-priority zones.
    private static let verticalBandFraction: CGFloat = 0.33
    /// Circular center dead zone radius as a fraction of `min(width, height)`.
    static let centerDeadZoneRadiusFraction: CGFloat = 0.06

    enum Result {
        case accepted(Gate)
        case ignoredCenterDeadZone
    }

    static func resolve(from location: CGPoint, in size: CGSize) -> Result {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let cx = w / 2
        let cy = h / 2
        let deadZoneRadius = min(w, h) * centerDeadZoneRadiusFraction
        let dx = location.x - cx
        let dy = location.y - cy
        if (dx * dx + dy * dy) <= (deadZoneRadius * deadZoneRadius) {
            return .ignoredCenterDeadZone
        }

        let topBandMaxY = h * verticalBandFraction
        let bottomBandMinY = h * (1 - verticalBandFraction)
        if location.y <= topBandMaxY {
            return .accepted(.up)
        }
        if location.y >= bottomBandMinY {
            return .accepted(.down)
        }
        return location.x < cx ? .accepted(.left) : .accepted(.right)
    }
}

// MARK: - Haptics

extension CoachRemoteHaptics {
    /// Single clear impact for direction zone taps (no network wait).
    static func directionZonePulse() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        g.impactOccurred()
    }
}

// MARK: - SwiftUI layer

/// Invisible full-screen hit target with faint directional hints. Place **behind** instruction chrome;
/// keep PASS / other controls in a foreground layer with hit testing where needed.
struct CoachRemoteFullScreenDirectionZones: View {
    /// Short name for `[DirectionInput-Debug]` (e.g. `awayFromPressure`).
    let activity: String
    let onGate: (Gate) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                CoachRemoteDirectionZoneHints()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let p = value.startLocation
                        switch CoachRemoteDirectionZoneResolver.resolve(from: p, in: size) {
                        case .accepted(let gate):
                            CoachRemoteHaptics.directionZonePulse()
                            DirectionInputDebugLog.logAccepted(activity: activity, gate: gate, tapLocation: p, in: size)
                            onGate(gate)
                        case .ignoredCenterDeadZone:
                            DirectionInputDebugLog.logIgnoredCenterDeadZone(activity: activity, tapLocation: p, in: size)
                        }
                    }
            )
        }
    }
}

/// Subtle on-screen mapping (low contrast, not tappable).
private struct CoachRemoteDirectionZoneHints: View {
    private let hintOpacity: Double = 0.22

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                label(systemName: "arrow.up", text: "Forward")
                    .position(x: w / 2, y: h * 0.12)
                label(systemName: "arrow.down", text: "Back")
                    .position(x: w / 2, y: h * 0.88)
                label(systemName: "arrow.left", text: "Left")
                    .position(x: w * 0.12, y: h / 2)
                label(systemName: "arrow.right", text: "Right")
                    .position(x: w * 0.88, y: h / 2)
            }
            .allowsHitTesting(false)
        }
    }

    private func label(systemName: String, text: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundColor(.white.opacity(hintOpacity))
    }
}
