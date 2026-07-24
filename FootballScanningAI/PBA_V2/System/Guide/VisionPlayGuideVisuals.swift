//
//  VisionPlayGuideVisuals.swift
//  FootballScanningAI
//
//  Guide activity visuals — real Player Display screenshot assets, plus replaceable setup diagrams.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Framed Player Display screenshot / setup visual used on Guide pages.
struct VisionPlayGuideVisualView: View {
    let kind: VisionPlayGuideVisualKind
    /// Soft width cap so the screenshot supports copy instead of dominating the page.
    var maxWidth: CGFloat = 416
    /// Optional height cap (aspect ratio preserved via `scaledToFit`).
    var maxHeight: CGFloat? = nil

    private let cornerRadius: CGFloat = 14

    var body: some View {
        Group {
            if let assetName = kind.imageAssetName, hasImageAsset(named: assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            } else if kind == .partnerModeSetup {
                PartnerModeSetupDiagramView()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: maxWidth)
        .frame(maxHeight: maxHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func hasImageAsset(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return false
        #endif
    }
}

extension VisionPlayGuideVisualKind {
    /// Asset catalog name for a real screenshot / photo when available.
    /// Drop a `GuidePartnerModeSetup` imageset to replace the Partner Mode Setup diagram without layout changes.
    var imageAssetName: String? {
        switch self {
        case .meetTheBall:
            return "GuideMeetTheBall"
        case .awayFromPressure:
            return "GuideAwayFromPressure"
        case .dribbleOrPass:
            return "GuideDribbleOrPass"
        case .soloCalibration:
            return "GuideSoloCalibration"
        case .partnerModeSetup:
            return "GuidePartnerModeSetup"
        case .oneTouchPassing:
            // No captured Player Display screenshot yet.
            return nil
        }
    }
}

// MARK: - Partner Mode Setup diagram (replaceable placeholder)

/// Overhead Partner Mode setup schematic. Replace by adding `GuidePartnerModeSetup` to Assets.
private struct PartnerModeSetupDiagramView: View {
    var body: some View {
        GeometryReader { geo in
            let field = diagramField(in: geo.size)
            let layout = SetupLayout(field: field)

            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.10)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .frame(width: field.width, height: field.height)
                    .position(x: field.midX, y: field.midY)

                // Dimension brackets first (behind markers) so they stay readable
                coachDistanceBracket(layout)
                ipadDistanceBracket(layout)

                receivingZone(layout)
                ballPath(layout)
                playerMotion(layout)
                coachMarker(layout)
                ipadMarker(layout)
            }
        }
        .aspectRatio(1.35, contentMode: .fit)
    }

    private struct FieldRect {
        let origin: CGPoint
        let size: CGSize
        var width: CGFloat { size.width }
        var height: CGFloat { size.height }
        var midX: CGFloat { origin.x + size.width / 2 }
        var midY: CGFloat { origin.y + size.height / 2 }
        var minX: CGFloat { origin.x }
        var maxX: CGFloat { origin.x + size.width }
        var minY: CGFloat { origin.y }
        var maxY: CGFloat { origin.y + size.height }
    }

    /// Shared geometry so markers and dimension lines never fight for the same space.
    private struct SetupLayout {
        let field: FieldRect
        let zone: CGRect
        let coachPoint: CGPoint
        let ipadPoint: CGPoint

        init(field: FieldRect) {
            self.field = field
            let side = min(field.width * 0.40, field.height * 0.34)
            let zone = CGRect(
                x: field.midX - side / 2,
                y: field.minY + field.height * 0.30,
                width: side,
                height: side
            )
            self.zone = zone
            // Coach sits clearly above the zone so the 10–12 yd gap is visible.
            self.coachPoint = CGPoint(
                x: field.midX,
                y: field.minY + (zone.minY - field.minY) * 0.28
            )
            // iPad sits clearly below the zone so the 3–5 yd gap is visible.
            self.ipadPoint = CGPoint(
                x: field.midX,
                y: zone.maxY + (field.maxY - zone.maxY) * 0.62
            )
        }
    }

    private func diagramField(in size: CGSize) -> FieldRect {
        let insetX = size.width * 0.05
        let insetY = size.height * 0.05
        return FieldRect(
            origin: CGPoint(x: insetX, y: insetY),
            size: CGSize(width: size.width - insetX * 2, height: size.height - insetY * 2)
        )
    }

    private func receivingZone(_ layout: SetupLayout) -> some View {
        let zone = layout.zone
        return ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: zone.width, height: zone.height)
                .position(x: zone.midX, y: zone.midY)

            ForEach(0..<4, id: \.self) { i in
                let pt: CGPoint = {
                    switch i {
                    case 0: return CGPoint(x: zone.minX, y: zone.minY)
                    case 1: return CGPoint(x: zone.maxX, y: zone.minY)
                    case 2: return CGPoint(x: zone.minX, y: zone.maxY)
                    default: return CGPoint(x: zone.maxX, y: zone.maxY)
                    }
                }()
                Circle()
                    .fill(Color.orange.opacity(0.95))
                    .frame(width: 7, height: 7)
                    .position(pt)
            }

            Text("5 × 5 yd")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.50))
                .position(x: zone.maxX + 28, y: zone.midY)
        }
    }

    private func coachMarker(_ layout: SetupLayout) -> some View {
        VStack(spacing: 2) {
            Text("Coach")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.80))
            Image(systemName: "figure.stand")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
        }
        .position(layout.coachPoint)
    }

    private func ipadMarker(_ layout: SetupLayout) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.yellow.opacity(0.85), lineWidth: 1.2)
                )
                .frame(width: 28, height: 18)
            Text("iPad")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundColor(.yellow.opacity(0.9))
        }
        .position(layout.ipadPoint)
    }

    /// Ball path runs slightly left of center so the right-side dimension brackets stay clear.
    private func ballPath(_ layout: SetupLayout) -> some View {
        let start = CGPoint(x: layout.coachPoint.x - 10, y: layout.coachPoint.y + 10)
        let end = CGPoint(x: layout.zone.midX - 8, y: layout.zone.midY)
        let mid = CGPoint(
            x: start.x + (end.x - start.x) * 0.42,
            y: start.y + (end.y - start.y) * 0.42
        )

        return ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(
                Color.yellow.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 3])
            )

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 7))
                .foregroundColor(.yellow.opacity(0.65))
                .position(
                    x: start.x + (end.x - start.x) * 0.78,
                    y: start.y + (end.y - start.y) * 0.78
                )

            // Small ball — kept off the dimension brackets
            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: 7, height: 7)
                .position(mid)
        }
    }

    private func playerMotion(_ layout: SetupLayout) -> some View {
        let zone = layout.zone
        let roamA = CGPoint(x: zone.minX + zone.width * 0.20, y: zone.minY + zone.height * 0.58)
        let roamB = CGPoint(x: zone.minX + zone.width * 0.36, y: zone.minY + zone.height * 0.30)
        let roamC = CGPoint(x: zone.minX + zone.width * 0.58, y: zone.minY + zone.height * 0.52)
        let center = CGPoint(x: zone.midX, y: zone.midY)

        return ZStack {
            Path { path in
                path.move(to: roamA)
                path.addQuadCurve(to: roamC, control: roamB)
            }
            .stroke(
                Color.cyan.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round, dash: [3, 3])
            )

            Path { path in
                path.move(to: roamC)
                path.addLine(to: center)
            }
            .stroke(
                Color.cyan.opacity(0.9),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
            )

            Image(systemName: "figure.walk")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.cyan.opacity(0.95))
                .position(roamA)

            Circle()
                .stroke(Color.cyan.opacity(0.85), lineWidth: 1.2)
                .frame(width: 12, height: 12)
                .position(center)

            Text("check")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundColor(.cyan.opacity(0.7))
                .position(x: center.x + zone.width * 0.28, y: center.y + 1)
        }
    }

    /// Side bracket: Coach → front edge of receiving zone.
    private func coachDistanceBracket(_ layout: SetupLayout) -> some View {
        let x = layout.zone.maxX + 22
        let top = layout.coachPoint.y + 8
        let bottom = layout.zone.minY
        return dimensionBracket(
            x: x,
            topY: top,
            bottomY: bottom,
            label: "10–12 yd",
            color: .white.opacity(0.55)
        )
    }

    /// Side bracket: back edge of receiving zone → iPad (makes the 3–5 yd gap obvious).
    private func ipadDistanceBracket(_ layout: SetupLayout) -> some View {
        let x = layout.zone.maxX + 22
        let top = layout.zone.maxY
        let bottom = layout.ipadPoint.y - 14
        return dimensionBracket(
            x: x,
            topY: top,
            bottomY: bottom,
            label: "3–5 yd",
            color: .yellow.opacity(0.75)
        )
    }

    private func dimensionBracket(
        x: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        label: String,
        color: Color
    ) -> some View {
        let midY = (topY + bottomY) / 2
        return ZStack {
            Path { path in
                // Top tick
                path.move(to: CGPoint(x: x - 5, y: topY))
                path.addLine(to: CGPoint(x: x + 5, y: topY))
                // Vertical span
                path.move(to: CGPoint(x: x, y: topY))
                path.addLine(to: CGPoint(x: x, y: bottomY))
                // Bottom tick
                path.move(to: CGPoint(x: x - 5, y: bottomY))
                path.addLine(to: CGPoint(x: x + 5, y: bottomY))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round))

            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(0.92))
                .position(x: x + 28, y: midY)
        }
    }
}
