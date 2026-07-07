//
//  DribbleOrPassGateOverlay.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Red = pressure, Green = teammate. Open (dribble space) = no cue.
//

import SwiftUI

private enum DOPLaneAnimation {
    static let defenderCycleSeconds: Double = 1.0
    static let teammateCycleSeconds: Double = 1.5
    /// Inward travel cap (~7.5% of short screen edge) — stays clear of X.
    static let inwardTravelFraction: CGFloat = 0.075

    static func easeInOutPingPong(phase: CGFloat) -> CGFloat {
        (1 - cos(phase * 2 * .pi)) / 2
    }

    /// Monotonic 0→1 each cycle — lane advances toward center, then resets at the edge.
    static func defenderInwardProgress(phase: CGFloat) -> CGFloat {
        phase
    }

    static func teammatePulseOpacity(phase: CGFloat) -> Double {
        0.72 + 0.20 * Double(easeInOutPingPong(phase: phase))
    }
}

struct DribbleOrPassGateOverlay: View {
    /// Static mini teammate lane for session-start cue (same gradient + shape as gameplay; no animation).
    struct SessionStartInlineTeammateBar: View {
        let length: CGFloat
        var opacity: Double = 0.75

        private var thickness: CGFloat { length * 0.35 }

        var body: some View {
            let colors = [
                Color.green.opacity(0.92),
                Color.green.opacity(0.48),
                Color.green.opacity(0.06)
            ]
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8
            )
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: thickness, height: length)
            .opacity(opacity)
        }
    }

    let gate: Gate
    let content: DribbleOrPassGateContent
    var wedgeStyle: WedgeCueStyle = WedgeCueStyle.style(for: 1)
    var insetFraction: CGFloat = 0.15
    /// When false, opponent cue stays mounted for preload but hidden until revealed (`revealedGates`).
    var isDecisionRevealActive: Bool = true

    /// Cycle anchor for defender inward travel — set on reveal so the bar always starts flush at the screen edge.
    @State private var defenderAnimationAnchor: Date?

    private let innerCornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if content == .open {
                Color.clear
            } else {
                GeometryReader { geo in
                    overlayRect(w: geo.size.width, h: geo.size.height, geo: geo)
                        .opacity(content == .opponent && !isDecisionRevealActive ? 0 : 1)
                }
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .onAppear { syncDefenderAnimationAnchor() }
        .onChange(of: isDecisionRevealActive) { _, _ in syncDefenderAnimationAnchor() }
        .onChange(of: content) { _, _ in syncDefenderAnimationAnchor() }
    }

    private func syncDefenderAnimationAnchor() {
        if content == .opponent, isDecisionRevealActive {
            defenderAnimationAnchor = Date()
        } else {
            defenderAnimationAnchor = nil
        }
    }

    private var gradientColors: [Color] {
        switch content {
        case .opponent:
            let edge = min(0.96, wedgeStyle.opacity + 0.12)
            return [
                Color.red.opacity(edge),
                Color.red.opacity(edge * 0.58),
                Color.red.opacity(0.06)
            ]
        case .teammate:
            return [Color.green.opacity(0.92), Color.green.opacity(0.48), Color.green.opacity(0.06)]
        case .open:
            return []
        }
    }

    /// One bar size for every gate — matches left/right lane dimensions (reference in landscape).
    private func dopBarSize(fieldWidth w: CGFloat, fieldHeight h: CGFloat) -> (length: CGFloat, thickness: CGFloat) {
        let s = min(w, h)
        let thickness = s * insetFraction
        let length = wedgeStyle.spanAlongEdge(for: .left, fieldWidth: w, fieldHeight: h)
        return (length, thickness)
    }

    private func gradientStart(for gate: Gate) -> UnitPoint {
        switch gate {
        case .up: return .top
        case .down: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func gradientEnd(for gate: Gate) -> UnitPoint {
        switch gate {
        case .up: return .bottom
        case .down: return .top
        case .left: return .trailing
        case .right: return .leading
        }
    }

    private func barFrameDimensions(barLength: CGFloat, barThickness: CGFloat) -> (width: CGFloat, height: CGFloat) {
        switch gate {
        case .up, .down: return (barLength, barThickness)
        case .left, .right: return (barThickness, barLength)
        }
    }

    private func barCenter(
        w: CGFloat,
        h: CGFloat,
        barThickness: CGFloat,
        inwardTravel: CGFloat = 0
    ) -> CGPoint {
        switch gate {
        case .left:
            return CGPoint(x: barThickness / 2 + inwardTravel, y: h / 2)
        case .right:
            return CGPoint(x: w - barThickness / 2 - inwardTravel, y: h / 2)
        case .up:
            return CGPoint(x: w / 2, y: barThickness / 2 + inwardTravel)
        case .down:
            return CGPoint(x: w / 2, y: h - barThickness / 2 - inwardTravel)
        }
    }

    @ViewBuilder
    private func gateBar(
        w: CGFloat,
        h: CGFloat,
        barLength: CGFloat,
        barThickness: CGFloat,
        colors: [Color],
        inwardTravel: CGFloat = 0
    ) -> some View {
        let fill = LinearGradient(
            colors: colors,
            startPoint: gradientStart(for: gate),
            endPoint: gradientEnd(for: gate)
        )
        let r = innerCornerRadius
        let dims = barFrameDimensions(barLength: barLength, barThickness: barThickness)
        let center = barCenter(w: w, h: h, barThickness: barThickness, inwardTravel: inwardTravel)

        Group {
            switch gate {
            case .left:
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: r, topTrailingRadius: r)
                    .fill(fill)
            case .right:
                UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .fill(fill)
            case .up:
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0)
                    .fill(fill)
            case .down:
                UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: r)
                    .fill(fill)
            }
        }
        .frame(width: dims.width, height: dims.height)
        .position(x: center.x, y: center.y)
    }

    @ViewBuilder
    private func overlayRect(w: CGFloat, h: CGFloat, geo: GeometryProxy) -> some View {
        let (barLength, barThickness) = dopBarSize(fieldWidth: w, fieldHeight: h)
        let maxInwardTravel = min(w, h) * DOPLaneAnimation.inwardTravelFraction

        Group {
            switch content {
            case .opponent:
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !isDecisionRevealActive)) { timeline in
                    let elapsed = defenderAnimationAnchor.map { timeline.date.timeIntervalSince($0) } ?? 0
                    let phase = CGFloat(
                        elapsed.truncatingRemainder(dividingBy: DOPLaneAnimation.defenderCycleSeconds)
                            / DOPLaneAnimation.defenderCycleSeconds
                    )
                    let travel = DOPLaneAnimation.defenderInwardProgress(phase: phase) * maxInwardTravel
                    gateBar(
                        w: w,
                        h: h,
                        barLength: barLength,
                        barThickness: barThickness,
                        colors: gradientColors,
                        inwardTravel: travel
                    )
                }
            case .teammate:
                TimelineView(.animation(minimumInterval: 1 / 60, paused: false)) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let phase = CGFloat(
                        elapsed.truncatingRemainder(dividingBy: DOPLaneAnimation.teammateCycleSeconds)
                            / DOPLaneAnimation.teammateCycleSeconds
                    )
                    gateBar(
                        w: w,
                        h: h,
                        barLength: barLength,
                        barThickness: barThickness,
                        colors: gradientColors
                    )
                    .opacity(DOPLaneAnimation.teammatePulseOpacity(phase: phase))
                }
            case .open:
                EmptyView()
            }
        }
        .onAppear { logGateClarity(w: w, h: h, spanAlong: barLength, laneThickness: barThickness) }
        .onChange(of: gate) { _, _ in logGateClarity(w: w, h: h, spanAlong: barLength, laneThickness: barThickness) }
        .onChange(of: geo.size.width) { _, _ in logGateClarity(w: w, h: h, spanAlong: barLength, laneThickness: barThickness) }
        .onChange(of: geo.size.height) { _, _ in logGateClarity(w: w, h: h, spanAlong: barLength, laneThickness: barThickness) }
    }

    private func logGateClarity(w: CGFloat, h: CGFloat, spanAlong: CGFloat, laneThickness: CGFloat) {
        let cx: CGFloat
        let cy: CGFloat
        switch gate {
        case .up:
            cx = w / 2
            cy = laneThickness / 2
        case .down:
            cx = w / 2
            cy = h - laneThickness / 2
        case .left:
            cx = laneThickness / 2
            cy = h / 2
        case .right:
            cx = w - laneThickness / 2
            cy = h / 2
        }
        let pos = "center=(\(String(format: "%.1f", cx)),\(String(format: "%.1f", cy))) thicknessPts=\(String(format: "%.2f", laneThickness))"
        WedgeClarityDebugLog.log(side: gate.wedgeClaritySideLabel, widthPts: spanAlong, position: pos)
    }
}
