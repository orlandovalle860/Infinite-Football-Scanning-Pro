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

/// Full edge→center reveal duration for the red pressure wedge (seconds). Same for AFP / OTP / DOP. Tunable; keep ≤ 0.35. Uses `easeOut` only (no spring/bounce).
private let pbaPressureWedgeRevealDuration: Double = 0.22

/// Inner edge (toward field) is this much wider than the base on the sideline — reads as a pressure band, not a sharp arrow.
private let wedgeInnerFlare: CGFloat = 1.36

/// Red directional wedge indicating where pressure is coming from. Points toward the center (player).
struct DangerZoneOverlay: View {
    let gate: Gate
    var style: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    /// When false, the view can stay mounted for preload (e.g. AFP scan/beep) but stays collapsed and invisible until this becomes true, so the edge→center reveal runs when the player actually sees it.
    var isDecisionRevealActive: Bool = true

    @State private var revealProgress: CGFloat = 0

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
                .onAppear { logWedgeClarity(w: w, h: h) }
                .onChange(of: gate) { _, _ in logWedgeClarity(w: w, h: h) }
                .onChange(of: geo.size.width) { _, _ in logWedgeClarity(w: w, h: h) }
                .onChange(of: geo.size.height) { _, _ in logWedgeClarity(w: w, h: h) }
        }
        .scaleEffect(x: scaleX, y: scaleY, anchor: scaleAnchor)
        .opacity(overlayOpacity)
        /// Explicit animation on `revealProgress` so the edge→center motion still runs when an ancestor uses `.animation(nil, …)` (e.g. OTP/DOP gate cue opacity).
        .animation(.easeOut(duration: pbaPressureWedgeRevealDuration), value: revealProgress)
        .allowsHitTesting(false)
        .onAppear {
            if isDecisionRevealActive {
                runEdgeRevealAnimation()
            } else {
                revealProgress = 0
            }
        }
        .onChange(of: isDecisionRevealActive) { _, active in
            if active {
                runEdgeRevealAnimation()
            } else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { revealProgress = 0 }
            }
        }
        .onChange(of: gate) { _, _ in
            guard isDecisionRevealActive else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { revealProgress = 0 }
                return
            }
            runEdgeRevealAnimation()
        }
    }

    private var overlayOpacity: Double {
        guard isDecisionRevealActive else { return 0 }
        return 0.35 + 0.65 * Double(revealProgress)
    }

    /// Resets without animation, then advances `revealProgress` on the next main run so we escape a parent `.animation(nil, …)` transaction (same frame as cue opacity / phase changes).
    private func runEdgeRevealAnimation() {
        #if DEBUG
        let revealStart = Date()
        print("[WedgeTiming-Debug] reveal duration=\(pbaPressureWedgeRevealDuration)s start=\(revealStart.timeIntervalSince1970)")
        #endif
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { revealProgress = 0 }
        DispatchQueue.main.async {
            revealProgress = 1
            #if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + pbaPressureWedgeRevealDuration) {
                let revealEnd = Date()
                print("[WedgeTiming-Debug] reveal duration=\(pbaPressureWedgeRevealDuration)s start=\(revealStart.timeIntervalSince1970) end=\(revealEnd.timeIntervalSince1970)")
            }
            #endif
        }
    }

    /// Wedge grows from the edge where pressure originates toward the center.
    private var scaleX: CGFloat {
        switch gate {
        case .left: return max(0.02, revealProgress)
        case .right: return max(0.02, revealProgress)
        case .up, .down: return 1
        }
    }

    private var scaleY: CGFloat {
        switch gate {
        case .up, .down: return max(0.02, revealProgress)
        case .left, .right: return 1
        }
    }

    private var scaleAnchor: UnitPoint {
        switch gate {
        case .up: return .top
        case .down: return .bottom
        case .left: return .leading
        case .right: return .trailing
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

    private func logWedgeClarity(w: CGFloat, h: CGFloat) {
        let span = style.spanAlongEdge(for: gate, fieldWidth: w, fieldHeight: h)
        let inset = min(w, h) * WedgeCueStyle.edgeInsetFraction
        let depth = wedgeDepth(w: w, h: h)
        let centerGap = min(w, h) * style.centerGapFraction
        let baseCenter: CGPoint
        let tip: CGPoint
        switch gate {
        case .up:
            let baseY = inset
            let tipY = min(baseY + depth, (h / 2) - centerGap)
            baseCenter = CGPoint(x: w / 2, y: baseY)
            tip = CGPoint(x: w / 2, y: tipY)
        case .down:
            let baseY = h - inset
            let tipY = max(baseY - depth, (h / 2) + centerGap)
            baseCenter = CGPoint(x: w / 2, y: baseY)
            tip = CGPoint(x: w / 2, y: tipY)
        case .left:
            let baseX = inset
            let tipX = min(baseX + depth, (w / 2) - centerGap)
            baseCenter = CGPoint(x: baseX, y: h / 2)
            tip = CGPoint(x: tipX, y: h / 2)
        case .right:
            let baseX = w - inset
            let tipX = max(baseX - depth, (w / 2) + centerGap)
            baseCenter = CGPoint(x: baseX, y: h / 2)
            tip = CGPoint(x: tipX, y: h / 2)
        }
        let pos = "baseCenter=(\(String(format: "%.1f", baseCenter.x)),\(String(format: "%.1f", baseCenter.y))) tip=(\(String(format: "%.1f", tip.x)),\(String(format: "%.1f", tip.y))) insetPts=\(String(format: "%.2f", inset))"
        WedgeClarityDebugLog.log(side: gate.wedgeClaritySideLabel, widthPts: span, position: pos)
    }

    private func wedgePath(w: CGFloat, h: CGFloat) -> Path {
        let span = style.spanAlongEdge(for: gate, fieldWidth: w, fieldHeight: h)
        let depth = wedgeDepth(w: w, h: h)
        let centerGap = min(w, h) * style.centerGapFraction
        let inset = min(w, h) * WedgeCueStyle.edgeInsetFraction
        let halfBase = span / 2
        let margin = min(w, h) * 0.04

        switch gate {
        case .up:
            // Trapezoid: narrow base on top edge, wider band toward the field (not a pointed arrow).
            let baseY = inset
            let tipY = min(baseY + depth, (h / 2) - centerGap)
            let innerHalf = min(halfBase * wedgeInnerFlare, (w / 2) - margin)
            let leftB = w / 2 - halfBase
            let rightB = w / 2 + halfBase
            let leftI = w / 2 - innerHalf
            let rightI = w / 2 + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: leftB, y: baseY))
                p.addLine(to: CGPoint(x: rightB, y: baseY))
                p.addLine(to: CGPoint(x: rightI, y: tipY))
                p.addLine(to: CGPoint(x: leftI, y: tipY))
                p.closeSubpath()
            }
        case .down:
            let baseY = h - inset
            let tipY = max(baseY - depth, (h / 2) + centerGap)
            let innerHalf = min(halfBase * wedgeInnerFlare, (w / 2) - margin)
            let leftB = w / 2 - halfBase
            let rightB = w / 2 + halfBase
            let leftI = w / 2 - innerHalf
            let rightI = w / 2 + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: leftB, y: baseY))
                p.addLine(to: CGPoint(x: rightB, y: baseY))
                p.addLine(to: CGPoint(x: rightI, y: tipY))
                p.addLine(to: CGPoint(x: leftI, y: tipY))
                p.closeSubpath()
            }
        case .left:
            let baseX = inset
            let tipX = min(baseX + depth, (w / 2) - centerGap)
            let innerHalf = min(halfBase * wedgeInnerFlare, (h / 2) - margin)
            let topB = h / 2 - halfBase
            let botB = h / 2 + halfBase
            let topI = h / 2 - innerHalf
            let botI = h / 2 + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: topB))
                p.addLine(to: CGPoint(x: baseX, y: botB))
                p.addLine(to: CGPoint(x: tipX, y: botI))
                p.addLine(to: CGPoint(x: tipX, y: topI))
                p.closeSubpath()
            }
        case .right:
            let baseX = w - inset
            let tipX = max(baseX - depth, (w / 2) + centerGap)
            let innerHalf = min(halfBase * wedgeInnerFlare, (h / 2) - margin)
            let topB = h / 2 - halfBase
            let botB = h / 2 + halfBase
            let topI = h / 2 - innerHalf
            let botI = h / 2 + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: topB))
                p.addLine(to: CGPoint(x: baseX, y: botB))
                p.addLine(to: CGPoint(x: tipX, y: botI))
                p.addLine(to: CGPoint(x: tipX, y: topI))
                p.closeSubpath()
            }
        }
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
