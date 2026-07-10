//
//  TwoMinuteSlotPositions.swift
//  FootballScanningAI
//
//  PBA V2 — Same positions as Dribble or Pass (Middle Up/Down/Left/Right). Used so the ball appears where players would be.
//

import CoreGraphics
import SwiftUI
import UIKit

enum TwoMinuteSlotPositions {
    /// Shared inset from each edge of the usable rect, as a fraction of the **shorter** side.
    /// Using the shorter side keeps left/right and up/down margins visually equal in landscape
    /// (where width ≫ height), so the ball reads centered on all four sides.
    private static let edgeInsetFraction: CGFloat = 0.10

    private static let ballEdgeMargin: CGFloat = 6

    /// Positions for the 2-minute layout **in the same coordinate space** as `GeometryReader` content (size + safeAreaInsets).
    /// Use this from `GeometryReader { geo in … }` so the ball and center X align; do not mix with `UIScreen` alone.
    ///
    /// `ballSideLength` must match the rendered ball frame so slot **centers** keep the full ball inside the usable rect.
    /// - Parameter focalContentDownshift: Same value as the drill view’s `offset(y:)` (e.g. ``PartnerDisplayLayout/drillFocalCenterYOffset``) so slot math accounts for the shift and the bottom ball is not clipped in landscape.
    static func positions(in size: CGSize, safeAreaInsets: EdgeInsets, ballSideLength: CGFloat, focalContentDownshift: CGFloat = 0) -> [Gate: CGPoint] {
        let m = layoutMetrics(size: size, safeAreaInsets: safeAreaInsets, ballSideLength: ballSideLength, focalContentDownshift: focalContentDownshift)
        return [
            .up: CGPoint(x: m.cx, y: m.topY),
            .down: CGPoint(x: m.cx, y: m.bottomY),
            .left: CGPoint(x: m.leftX, y: m.midY),
            .right: CGPoint(x: m.rightX, y: m.midY),
        ]
    }

    /// Legacy: full-screen coordinates (can disagree with a `GeometryReader` inside navigation). Prefer `positions(in:safeAreaInsets:ballSideLength:)`.
    static func positionsForCurrentScreen() -> [Gate: CGPoint] {
        let b = UIScreen.main.bounds
        var top: CGFloat = 0, bottom: CGFloat = 0, leading: CGFloat = 0, trailing: CGFloat = 0
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            top = window.safeAreaInsets.top
            bottom = window.safeAreaInsets.bottom
            leading = window.safeAreaInsets.left
            trailing = window.safeAreaInsets.right
        }
        let insets = EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
        let side = ballSideLength(in: b.size, safeAreaInsets: insets)
        return positions(in: b.size, safeAreaInsets: insets, ballSideLength: side, focalContentDownshift: 0)
    }

    /// Soccer ball side length: scales with the playable area so 11" vs 13" (and split view) stay consistent.
    /// ~24% of the shorter usable dimension, clamped so very small or very large layouts stay readable.
    static func ballSideLength(in size: CGSize, safeAreaInsets: EdgeInsets) -> CGFloat {
        let w = size.width
        let h = size.height
        let t = safeAreaInsets.top
        let b = safeAreaInsets.bottom
        let l = safeAreaInsets.leading
        let r = safeAreaInsets.trailing
        let usableW = w - l - r
        let usableH = h - t - b
        let m = min(usableW, usableH)
        let isLandscape = w > h
        let fraction: CGFloat = isLandscape ? 0.21 : 0.24
        let scaled = m * fraction
        let maxSide: CGFloat = isLandscape ? 235 : 260
        return min(max(scaled, 120), maxSide)
    }

    /// Center of the playable band (matches the diamond’s vertical/horizontal midlines).
    static func centerPosition(in size: CGSize, safeAreaInsets: EdgeInsets, ballSideLength: CGFloat, focalContentDownshift: CGFloat = 0) -> CGPoint {
        let m = layoutMetrics(size: size, safeAreaInsets: safeAreaInsets, ballSideLength: ballSideLength, focalContentDownshift: focalContentDownshift)
        return CGPoint(x: m.cx, y: m.midY)
    }

    private struct LayoutMetrics {
        let cx: CGFloat
        let topY: CGFloat
        let bottomY: CGFloat
        let midY: CGFloat
        let leftX: CGFloat
        let rightX: CGFloat
    }

    private static func layoutMetrics(size: CGSize, safeAreaInsets: EdgeInsets, ballSideLength: CGFloat, focalContentDownshift: CGFloat) -> LayoutMetrics {
        let w = size.width
        let h = size.height
        let t = safeAreaInsets.top
        let b = safeAreaInsets.bottom
        let l = safeAreaInsets.leading
        let r = safeAreaInsets.trailing

        let usableW = w - l - r
        let usableH = h - t - b
        let downshift = max(0, focalContentDownshift)

        let half = ballSideLength / 2
        let m = ballEdgeMargin
        let minCY = t + half + m
        // After the drill `offset(y: downshift)`, the bottom slot moves toward the physical edge —
        // reserve that space so the ball stays fully on-screen.
        let maxCY = t + usableH - half - m - downshift
        let minCX = l + half + m
        let maxCX = l + usableW - half - m

        // True screen center horizontally so left/right short ends match even when
        // leading/trailing safe areas differ (notch vs home indicator in landscape).
        let cx = w / 2
        // Visual center in pre-offset coordinates: after `offset(y: downshift)` this lands on
        // the usable-rect center, so up/down stay balanced on screen.
        let midY = t + usableH / 2 - downshift

        // Equal absolute inset on all four sides (based on the shorter usable side) so landscape
        // short ends match the long-side margins instead of looking cramped or skewed.
        let edgeInset = min(usableW, usableH) * edgeInsetFraction

        var topY = midY - (usableH / 2 - edgeInset)
        var bottomY = midY + (usableH / 2 - edgeInset)
        var leftX = cx - (usableW / 2 - edgeInset)
        var rightX = cx + (usableW / 2 - edgeInset)

        topY = max(topY, minCY)
        bottomY = min(bottomY, maxCY)
        leftX = min(max(leftX, minCX), maxCX)
        rightX = min(max(rightX, minCX), maxCX)

        // Re-symmetrize after clamping so one tight edge cannot skew the diamond.
        let halfV = max(0, min(midY - topY, bottomY - midY))
        topY = midY - halfV
        bottomY = midY + halfV
        let halfH = max(0, min(cx - leftX, rightX - cx))
        leftX = cx - halfH
        rightX = cx + halfH

        return LayoutMetrics(cx: cx, topY: topY, bottomY: bottomY, midY: midY, leftX: leftX, rightX: rightX)
    }
}
