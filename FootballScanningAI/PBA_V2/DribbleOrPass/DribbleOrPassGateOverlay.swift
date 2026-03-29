//
//  DribbleOrPassGateOverlay.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Red = pressure, Green = teammate. Open (dribble space) = no outline.
//

import SwiftUI

struct DribbleOrPassGateOverlay: View {
    let gate: Gate
    let content: DribbleOrPassGateContent
    /// Matches ``WedgeDifficultyEngine`` / Playing Away From Pressure red wedge sizing.
    var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    var laneSpan: CGFloat = 0.70
    var insetFraction: CGFloat = 0.22

    var body: some View {
        Group {
            if content == .open {
                Color.clear
            } else if content == .opponent {
                DangerZoneOverlay(gate: gate, style: wedgeStyle)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    overlayRect(w: w, h: h)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var gradientColors: [Color] {
        switch content {
        case .opponent:
            return [] // Red is drawn by DangerZoneOverlay (same as Playing Away From Pressure).
        case .teammate:
            return [Color.green.opacity(0.78), Color.green.opacity(0.22), Color.green.opacity(0)]
        case .open:
            return []
        }
    }

    @ViewBuilder
    private func overlayRect(w: CGFloat, h: CGFloat) -> some View {
        let laneW = w * laneSpan
        let laneH = h * insetFraction
        let inset = min(w, h) * insetFraction
        let colors = gradientColors

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
