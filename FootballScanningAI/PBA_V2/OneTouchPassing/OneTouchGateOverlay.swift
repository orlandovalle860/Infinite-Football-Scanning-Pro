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
    var laneSpan: CGFloat = 0.70
    var insetFraction: CGFloat = 0.22

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
                    let laneW = w * laneSpan
                    let laneH = h * insetFraction
                    let inset = min(w, h) * insetFraction
                    let colors = gradientColors
                    Group {
                        switch gate {
                        case .up:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                                .frame(width: laneW, height: laneH)
                                .position(x: w / 2, y: laneH / 2)
                        case .down:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                                .frame(width: laneW, height: laneH)
                                .position(x: w / 2, y: h - laneH / 2)
                        case .left:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: inset, height: h * laneSpan)
                                .position(x: inset / 2, y: h / 2)
                        case .right:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: colors, startPoint: .trailing, endPoint: .leading))
                                .frame(width: inset, height: h * laneSpan)
                                .position(x: w - inset / 2, y: h / 2)
                        }
                    }
                }
            } else {
                DangerZoneOverlay(gate: gate, style: wedgeStyle)
            }
        }
        .allowsHitTesting(false)
    }
}
