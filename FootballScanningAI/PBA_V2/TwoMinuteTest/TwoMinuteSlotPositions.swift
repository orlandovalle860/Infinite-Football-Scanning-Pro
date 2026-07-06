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
    /// Horizontal: distance from leading/trailing edges of the **usable** rect (fraction of width).
    private static let horizontalEdgeFraction: CGFloat = 0.10

    /// Vertical: distance from top/bottom of the **usable** rect (fraction of height). Landscape uses a slightly
    /// tighter band so the “up” slot reads as upper field; final Y is still clamped so the ball stays on-screen.
    private static func verticalEdgeFraction(isLandscape: Bool) -> CGFloat {
        isLandscape ? 0.085 : 0.095
    }

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
        let scaled = m * 0.24
        return min(max(scaled, 120), 260)
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
        let isLandscape = w > h
        let vFrac = verticalEdgeFraction(isLandscape: isLandscape)
        let hFrac = horizontalEdgeFraction

        let half = ballSideLength / 2
        let m = ballEdgeMargin
        let minCY = t + half + m
        // Nudge the allowed band up when the whole drill is offset downward (iPad), so the bottom slot stays on-screen.
        let maxCY = t + usableH - half - m - max(0, focalContentDownshift)
        let minCX = l + half + m
        let maxCX = l + usableW - half - m

        let cx = l + usableW / 2

        var topY = t + usableH * vFrac
        var bottomY = t + usableH * (1 - vFrac)
        topY = max(topY, minCY)
        bottomY = min(bottomY, maxCY)

        if topY >= bottomY {
            let mid = t + usableH / 2
            let span = max(0, min(mid - minCY, maxCY - mid))
            topY = mid - span
            bottomY = mid + span
        }

        let midY = (topY + bottomY) / 2

        var leftX = l + usableW * hFrac
        var rightX = l + usableW * (1 - hFrac)
        leftX = min(max(leftX, minCX), maxCX)
        rightX = min(max(rightX, minCX), maxCX)

        return LayoutMetrics(cx: cx, topY: topY, bottomY: bottomY, midY: midY, leftX: leftX, rightX: rightX)
    }
}
