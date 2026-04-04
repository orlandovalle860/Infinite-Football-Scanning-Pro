//
//  OneTouchGateOverlay.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Gate as green (available) or red (covered). Pass to any green.
//

import SwiftUI

struct OneTouchGateOverlay: View {
    let gate: Gate
    let isGreen: Bool  // true = available (safe pass), false = covered (pressure — use same style as Playing Away From Pressure)
    /// Matches ``WedgeDifficultyEngine`` / Playing Away From Pressure red wedge sizing.
    var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    var insetFraction: CGFloat = 0.22
    /// Same as AFP: when false, red wedge stays mounted for preload but collapsed until the cue is revealed (`revealedGates`).
    var isDecisionRevealActive: Bool = true

    private var gradientColors: [Color] {
        if isGreen {
            return [Color.green.opacity(0.78), Color.green.opacity(0.22), Color.green.opacity(0)]
        } else {
            return [] // Red (pressure) is drawn by DangerZoneOverlay.
        }
    }

    var body: some View {
        Group {
            if isGreen {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let spanAlong = wedgeStyle.spanAlongEdge(for: gate, fieldWidth: w, fieldHeight: h)
                    let edgeInset = min(w, h) * WedgeCueStyle.edgeInsetFraction
                    let laneH = h * insetFraction
                    let inset = min(w, h) * insetFraction
                    let colors = gradientColors
                    Group {
                        switch gate {
                        case .up:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                                .frame(width: spanAlong, height: laneH)
                                .position(x: w / 2, y: laneH / 2 + edgeInset)
                        case .down:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                                .frame(width: spanAlong, height: laneH)
                                .position(x: w / 2, y: h - laneH / 2 - edgeInset)
                        case .left:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: inset, height: spanAlong)
                                .position(x: edgeInset + inset / 2, y: h / 2)
                        case .right:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .trailing, endPoint: .leading))
                                .frame(width: inset, height: spanAlong)
                                .position(x: w - edgeInset - inset / 2, y: h / 2)
                        }
                    }
                    .onAppear { logGreenGateClarity(w: w, h: h, edgeInset: edgeInset, spanAlong: spanAlong) }
                    .onChange(of: gate) { _, _ in logGreenGateClarity(w: w, h: h, edgeInset: edgeInset, spanAlong: spanAlong) }
                    .onChange(of: geo.size.width) { _, _ in logGreenGateClarity(w: w, h: h, edgeInset: edgeInset, spanAlong: spanAlong) }
                    .onChange(of: geo.size.height) { _, _ in logGreenGateClarity(w: w, h: h, edgeInset: edgeInset, spanAlong: spanAlong) }
                }
            } else {
                DangerZoneOverlay(gate: gate, style: wedgeStyle, isDecisionRevealActive: isDecisionRevealActive)
            }
        }
        .allowsHitTesting(false)
    }

    private func logGreenGateClarity(w: CGFloat, h: CGFloat, edgeInset: CGFloat, spanAlong: CGFloat) {
        let cx: CGFloat
        let cy: CGFloat
        let laneH = h * insetFraction
        let inset = min(w, h) * insetFraction
        switch gate {
        case .up:
            cx = w / 2
            cy = laneH / 2 + edgeInset
        case .down:
            cx = w / 2
            cy = h - laneH / 2 - edgeInset
        case .left:
            cx = edgeInset + inset / 2
            cy = h / 2
        case .right:
            cx = w - edgeInset - inset / 2
            cy = h / 2
        }
        let pos = "center=(\(String(format: "%.1f", cx)),\(String(format: "%.1f", cy))) insetPts=\(String(format: "%.2f", edgeInset))"
        WedgeClarityDebugLog.log(side: gate.wedgeClaritySideLabel, widthPts: spanAlong, position: pos)
    }
}
