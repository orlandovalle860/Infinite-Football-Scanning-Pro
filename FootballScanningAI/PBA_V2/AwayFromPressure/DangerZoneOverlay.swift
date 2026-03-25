//
//  DangerZoneOverlay.swift
//  FootballScanningAI
//
//  PBA V2 — Red wedge = where pressure comes from; correct play is the opposite gate (turn away into space).
//

import SwiftUI

private let gateOutlineColor = Color.white.opacity(0.45)
private let gateOutlineLineWidth: CGFloat = 1.5

/// Draws a single gate as outline only (transparent interior). Shows all four possible exits; only one is correct per rep (opposite the red wedge).
struct GateOutlineOverlay: View {
    let gate: Gate
    var laneSpan: CGFloat = 0.62
    var insetFraction: CGFloat = 0.18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            outlineRect(w: w, h: h)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func outlineRect(w: CGFloat, h: CGFloat) -> some View {
        let laneW = w * laneSpan
        let laneH = h * insetFraction
        let inset = min(w, h) * insetFraction
        let strokeStyle = StrokeStyle(lineWidth: gateOutlineLineWidth)
        switch gate {
        case .up:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: laneW, height: laneH)
                .position(x: w / 2, y: laneH / 2)
        case .down:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: laneW, height: laneH)
                .position(x: w / 2, y: h - laneH / 2)
        case .left:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: inset, height: h * laneSpan)
                .position(x: inset / 2, y: h / 2)
        case .right:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: inset, height: h * laneSpan)
                .position(x: w - inset / 2, y: h / 2)
        }
    }
}

// MARK: - Pressure wedge (directional, points toward player)

private let pressureWedgeFadeInSeconds: Double = 0.06

/// Red directional wedge indicating where pressure is coming from. Points toward the center (player).
struct DangerZoneOverlay: View {
    let gate: Gate
    var style: WedgeCueStyle = WedgeCueStyle.style(for: 1)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            wedgePath(w: w, h: h)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(style.opacity),
                            Color.red.opacity(style.opacity * 0.92),
                            Color.red.opacity(style.opacity * 0.72)
                        ],
                        startPoint: wedgeGradientStart,
                        endPoint: wedgeGradientEnd
                    )
                )
                .transition(.opacity.animation(.linear(duration: pressureWedgeFadeInSeconds)))
        }
        .allowsHitTesting(false)
    }

    private var wedgeGradientStart: UnitPoint {
        switch gate {
        case .up: return .top
        case .down: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var wedgeGradientEnd: UnitPoint {
        switch gate {
        case .up: return .bottom
        case .down: return .top
        case .left: return .trailing
        case .right: return .leading
        }
    }

    private func wedgePath(w: CGFloat, h: CGFloat) -> Path {
        let laneW = wedgeLaneWidth(w: w, h: h)
        let depth = wedgeDepth(w: w, h: h)
        let centerGap = min(w, h) * style.centerGapFraction

        switch gate {
        case .up:
            // Base at top, tip points down toward player
            let baseY: CGFloat = 0
            let tipY = min(baseY + depth, (h / 2) - centerGap)
            let left = w / 2 - laneW / 2
            let right = w / 2 + laneW / 2
            return Path { p in
                p.move(to: CGPoint(x: left, y: baseY))
                p.addLine(to: CGPoint(x: right, y: baseY))
                p.addLine(to: CGPoint(x: w / 2, y: tipY))
                p.closeSubpath()
            }
        case .down:
            let baseY = h
            let tipY = max(baseY - depth, (h / 2) + centerGap)
            let left = w / 2 - laneW / 2
            let right = w / 2 + laneW / 2
            return Path { p in
                p.move(to: CGPoint(x: left, y: baseY))
                p.addLine(to: CGPoint(x: right, y: baseY))
                p.addLine(to: CGPoint(x: w / 2, y: tipY))
                p.closeSubpath()
            }
        case .left:
            let baseX: CGFloat = 0
            let tipX = min(baseX + depth, (w / 2) - centerGap)
            let top = h / 2 - (h * style.laneSpan) / 2
            let bottom = h / 2 + (h * style.laneSpan) / 2
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: top))
                p.addLine(to: CGPoint(x: baseX, y: bottom))
                p.addLine(to: CGPoint(x: tipX, y: h / 2))
                p.closeSubpath()
            }
        case .right:
            let baseX = w
            let tipX = max(baseX - depth, (w / 2) + centerGap)
            let top = h / 2 - (h * style.laneSpan) / 2
            let bottom = h / 2 + (h * style.laneSpan) / 2
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: top))
                p.addLine(to: CGPoint(x: baseX, y: bottom))
                p.addLine(to: CGPoint(x: tipX, y: h / 2))
                p.closeSubpath()
            }
        }
    }

    /// In landscape, top/bottom wedges can dominate the field because width is much larger than height.
    /// Reduce their span/depth adaptively so pressure is clear without drowning side-space options.
    private func wedgeLaneWidth(w: CGFloat, h: CGFloat) -> CGFloat {
        let base = w * style.laneSpan
        guard gate == .up || gate == .down else { return base }
        let safeW = max(w, 1)
        let aspect = h / safeW // < 1 in landscape
        let reduction = max(0.62, min(1.0, aspect * 0.95))
        return base * reduction
    }

    private func wedgeDepth(w: CGFloat, h: CGFloat) -> CGFloat {
        let base = min(w, h) * style.depthFraction
        guard gate == .up || gate == .down else { return base }
        let safeW = max(w, 1)
        let aspect = h / safeW // < 1 in landscape
        let reduction = max(0.70, min(1.0, aspect * 1.10))
        return base * reduction
    }
}
