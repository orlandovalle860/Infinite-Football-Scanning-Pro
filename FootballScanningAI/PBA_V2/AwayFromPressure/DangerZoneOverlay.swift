//
//  DangerZoneOverlay.swift
//  FootballScanningAI
//
//  PBA V2 — Red shaded lane at one edge (pressure). GateOutlineOverlay = outline only (open space).
//

import SwiftUI

private let gateOutlineColor = Color.white.opacity(0.45)
private let gateOutlineLineWidth: CGFloat = 1.5

/// Draws a single gate as outline only (transparent interior). Use so players see where options exist.
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

private let pressureWedgeOpacity: CGFloat = 0.75
private let pressureWedgeDepthFraction: CGFloat = 0.14 // how far the wedge extends into the grid

/// Red directional wedge indicating where pressure is coming from. Points toward the center (player).
struct DangerZoneOverlay: View {
    let gate: Gate
    var laneSpan: CGFloat = 0.62
    var insetFraction: CGFloat = 0.18
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            wedgePath(w: w, h: h)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(pressureWedgeOpacity),
                            Color.red.opacity(pressureWedgeOpacity * 0.5),
                            Color.red.opacity(0.15)
                        ],
                        startPoint: wedgeGradientStart,
                        endPoint: wedgeGradientEnd
                    )
                )
                .scaleEffect(pulseScale)
                .transition(.opacity.animation(.easeInOut(duration: 0.12)))
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.04
            }
        }
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
        let laneW = w * laneSpan
        let depth = min(w, h) * pressureWedgeDepthFraction

        switch gate {
        case .up:
            // Base at top, tip points down toward player
            let baseY: CGFloat = 0
            let tipY = baseY + depth
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
            let tipY = baseY - depth
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
            let tipX = baseX + depth
            let top = h / 2 - (h * laneSpan) / 2
            let bottom = h / 2 + (h * laneSpan) / 2
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: top))
                p.addLine(to: CGPoint(x: baseX, y: bottom))
                p.addLine(to: CGPoint(x: tipX, y: h / 2))
                p.closeSubpath()
            }
        case .right:
            let baseX = w
            let tipX = baseX - depth
            let top = h / 2 - (h * laneSpan) / 2
            let bottom = h / 2 + (h * laneSpan) / 2
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: top))
                p.addLine(to: CGPoint(x: baseX, y: bottom))
                p.addLine(to: CGPoint(x: tipX, y: h / 2))
                p.closeSubpath()
            }
        }
    }
}
