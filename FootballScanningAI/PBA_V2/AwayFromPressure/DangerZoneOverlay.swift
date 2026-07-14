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
        let field = WedgeFieldGeometry(fieldWidth: w, fieldHeight: h)
        let s = field.squareSize
        let spanAlong = min(s * 0.58, max(s * 0.38, s * laneSpan))
        let laneThickness = s * insetFraction
        let edgeInset = s * WedgeCueStyle.edgeInsetFraction
        let strokeStyle = StrokeStyle(lineWidth: gateOutlineLineWidth)
        switch gate {
        case .up:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: spanAlong, height: laneThickness)
                .position(x: field.centerX, y: field.originY + edgeInset + laneThickness / 2)
        case .down:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: spanAlong, height: laneThickness)
                .position(x: field.centerX, y: field.originY + s - edgeInset - laneThickness / 2)
        case .left:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: laneThickness, height: spanAlong)
                .position(x: field.originX + edgeInset + laneThickness / 2, y: field.centerY)
        case .right:
            RoundedRectangle(cornerRadius: 8)
                .stroke(gateOutlineColor, style: strokeStyle)
                .frame(width: laneThickness, height: spanAlong)
                .position(x: field.originX + s - edgeInset - laneThickness / 2, y: field.centerY)
        }
    }
}

// MARK: - Pressure wedge (directional, points toward player)

/// Full edge→center reveal duration for the red pressure wedge (seconds). Same for AFP / OTP / DOP. Tunable; keep ≤ 0.35. Uses `easeOut` only (no spring/bounce).
private let pbaPressureWedgeRevealDuration: Double = 0.22

// MARK: - Shared wedge geometry

/// Inner edge (toward field) is this much wider than the base on the sideline — reads as a pressure band, not a sharp arrow.
/// Kept modest so adjacent gates (DOP shows up to three wedges) do not overlap at square corners.
private let wedgeInnerFlare: CGFloat = 1.08

/// Triangular sector from field center through the two corners on this gate's edge — prevents corner overlap when multiple wedges are visible.
struct GateQuadrantClipShape: Shape {
    let gate: Gate
    let fieldWidth: CGFloat
    let fieldHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let field = WedgeFieldGeometry(fieldWidth: fieldWidth, fieldHeight: fieldHeight)
        let cx = field.centerX
        let cy = field.centerY
        let s = field.squareSize
        let oX = field.originX
        let oY = field.originY
        switch gate {
        case .up:
            return Path { p in
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: oX, y: oY))
                p.addLine(to: CGPoint(x: oX + s, y: oY))
                p.closeSubpath()
            }
        case .down:
            return Path { p in
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: oX + s, y: oY + s))
                p.addLine(to: CGPoint(x: oX, y: oY + s))
                p.closeSubpath()
            }
        case .left:
            return Path { p in
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: oX, y: oY + s))
                p.addLine(to: CGPoint(x: oX, y: oY))
                p.closeSubpath()
            }
        case .right:
            return Path { p in
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: oX + s, y: oY))
                p.addLine(to: CGPoint(x: oX + s, y: oY + s))
                p.closeSubpath()
            }
        }
    }
}

enum WedgeCuePath {
    static func path(gate: Gate, style: WedgeCueStyle, fieldWidth w: CGFloat, fieldHeight h: CGFloat) -> Path {
        let field = WedgeFieldGeometry(fieldWidth: w, fieldHeight: h)
        let anchors = WedgeDirectionalAnchors(gate: gate, field: field, style: style)
        let s = field.squareSize
        let halfBase = anchors.halfBase
        let margin = s * 0.04
        let innerHalfLimit = (s / 2) - margin
        let innerHalf = min(halfBase * wedgeInnerFlare, innerHalfLimit)
        let cx = field.centerX
        let cy = field.centerY

        switch gate {
        case .up:
            let baseY = anchors.baseY
            let tipY = anchors.innerTipY
            let leftB = cx - halfBase
            let rightB = cx + halfBase
            let leftI = cx - innerHalf
            let rightI = cx + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: leftB, y: baseY))
                p.addLine(to: CGPoint(x: rightB, y: baseY))
                p.addLine(to: CGPoint(x: rightI, y: tipY))
                p.addLine(to: CGPoint(x: leftI, y: tipY))
                p.closeSubpath()
            }
        case .down:
            let baseY = anchors.baseY
            let tipY = anchors.innerTipY
            let leftB = cx - halfBase
            let rightB = cx + halfBase
            let leftI = cx - innerHalf
            let rightI = cx + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: leftB, y: baseY))
                p.addLine(to: CGPoint(x: rightB, y: baseY))
                p.addLine(to: CGPoint(x: rightI, y: tipY))
                p.addLine(to: CGPoint(x: leftI, y: tipY))
                p.closeSubpath()
            }
        case .left:
            let baseX = anchors.baseX
            let tipX = anchors.innerTipX
            let topB = cy - halfBase
            let botB = cy + halfBase
            let topI = cy - innerHalf
            let botI = cy + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: topB))
                p.addLine(to: CGPoint(x: baseX, y: botB))
                p.addLine(to: CGPoint(x: tipX, y: botI))
                p.addLine(to: CGPoint(x: tipX, y: topI))
                p.closeSubpath()
            }
        case .right:
            let baseX = anchors.baseX
            let tipX = anchors.innerTipX
            let topB = cy - halfBase
            let botB = cy + halfBase
            let topI = cy - innerHalf
            let botI = cy + innerHalf
            return Path { p in
                p.move(to: CGPoint(x: baseX, y: topB))
                p.addLine(to: CGPoint(x: baseX, y: botB))
                p.addLine(to: CGPoint(x: tipX, y: botI))
                p.addLine(to: CGPoint(x: tipX, y: topI))
                p.closeSubpath()
            }
        }
    }
}

/// Fill-only wedge cue (no reveal animation). Used for DOP green teammate cues.
struct WedgeFillOverlay: View {
    let gate: Gate
    var style: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    var fillColor: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            WedgeCuePath.path(gate: gate, style: style, fieldWidth: w, fieldHeight: h)
                .fill(fillColor)
                .clipShape(GateQuadrantClipShape(gate: gate, fieldWidth: w, fieldHeight: h))
                .onAppear { logWedgeClarity(w: w, h: h) }
                .onChange(of: gate) { _, _ in logWedgeClarity(w: w, h: h) }
                .onChange(of: geo.size.width) { _, _ in logWedgeClarity(w: w, h: h) }
                .onChange(of: geo.size.height) { _, _ in logWedgeClarity(w: w, h: h) }
        }
        .allowsHitTesting(false)
    }

    private func logWedgeClarity(w: CGFloat, h: CGFloat) {
        let field = WedgeFieldGeometry(fieldWidth: w, fieldHeight: h)
        let anchors = WedgeDirectionalAnchors(gate: gate, field: field, style: style)
        let span = anchors.span
        let baseCenter = CGPoint(x: anchors.baseX, y: anchors.baseY)
        let tip = CGPoint(x: anchors.innerTipX, y: anchors.innerTipY)
        let pos = "baseCenter=(\(String(format: "%.1f", baseCenter.x)),\(String(format: "%.1f", baseCenter.y))) tip=(\(String(format: "%.1f", tip.x)),\(String(format: "%.1f", tip.y))) insetPts=\(String(format: "%.2f", anchors.edgeInset))"
        WedgeClarityDebugLog.log(side: gate.wedgeClaritySideLabel, widthPts: span, position: pos)
    }
}

/// Red directional wedge indicating where pressure is coming from. Points toward the center (player).
struct DangerZoneOverlay: View {
    let gate: Gate
    var style: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    /// When set, uses a solid fill instead of the default red gradient (DOP only).
    var solidFillColor: Color? = nil
    /// When false, the view can stay mounted for preload (e.g. AFP scan/beep) but stays collapsed and invisible until this becomes true, so the edge→center reveal runs when the player actually sees it.
    var isDecisionRevealActive: Bool = true

    @State private var revealProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let field = WedgeFieldGeometry(fieldWidth: w, fieldHeight: h)
            let anchors = WedgeDirectionalAnchors(gate: gate, field: field, style: style)
            Group {
                if let solidFillColor {
                    WedgeCuePath.path(gate: gate, style: style, fieldWidth: w, fieldHeight: h)
                        .fill(solidFillColor)
                } else {
                    WedgeCuePath.path(gate: gate, style: style, fieldWidth: w, fieldHeight: h)
                        .fill(
                            LinearGradient(
                                colors: TrainingCueColors.pressureWedgeGradient(),
                                startPoint: wedgeGradientStart,
                                endPoint: wedgeGradientEnd
                            )
                        )
                }
            }
            .clipShape(GateQuadrantClipShape(gate: gate, fieldWidth: w, fieldHeight: h))
            .scaleEffect(x: scaleX, y: scaleY, anchor: wedgeScaleAnchor(anchors: anchors, viewWidth: w, viewHeight: h))
            .opacity(overlayOpacity)
            .animation(.easeOut(duration: pbaPressureWedgeRevealDuration), value: revealProgress)
            .onAppear { logWedgeClarity(w: w, h: h) }
            .onChange(of: gate) { _, _ in logWedgeClarity(w: w, h: h) }
            .onChange(of: geo.size.width) { _, _ in logWedgeClarity(w: w, h: h) }
            .onChange(of: geo.size.height) { _, _ in logWedgeClarity(w: w, h: h) }
        }
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
        // Fully opaque once revealed; edge→center growth still comes from `revealProgress` scale.
        return revealProgress > 0 ? 1 : 0
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

    /// Scale anchor at the square edge (not the screen bezel) for edge→center reveal.
    private func wedgeScaleAnchor(anchors: WedgeDirectionalAnchors, viewWidth w: CGFloat, viewHeight h: CGFloat) -> UnitPoint {
        switch gate {
        case .up, .down:
            return UnitPoint(x: 0.5, y: anchors.baseY / h)
        case .left, .right:
            return UnitPoint(x: anchors.baseX / w, y: 0.5)
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
        let field = WedgeFieldGeometry(fieldWidth: w, fieldHeight: h)
        let anchors = WedgeDirectionalAnchors(gate: gate, field: field, style: style)
        let span = anchors.span
        let baseCenter = CGPoint(x: anchors.baseX, y: anchors.baseY)
        let tip = CGPoint(x: anchors.innerTipX, y: anchors.innerTipY)
        let pos = "baseCenter=(\(String(format: "%.1f", baseCenter.x)),\(String(format: "%.1f", baseCenter.y))) tip=(\(String(format: "%.1f", tip.x)),\(String(format: "%.1f", tip.y))) insetPts=\(String(format: "%.2f", anchors.edgeInset))"
        WedgeClarityDebugLog.log(side: gate.wedgeClaritySideLabel, widthPts: span, position: pos)
    }
}
