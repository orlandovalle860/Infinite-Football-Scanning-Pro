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
    /// Positions for the 2-minute layout **in the same coordinate space** as `GeometryReader` content (size + safeAreaInsets).
    /// Use this from `GeometryReader { geo in … }` so the ball and center X align; do not mix with `UIScreen` alone.
    static func positions(in size: CGSize, safeAreaInsets: EdgeInsets) -> [Gate: CGPoint] {
        let w = size.width
        let h = size.height
        let safeTop = safeAreaInsets.top
        let safeBottom = safeAreaInsets.bottom
        let safeLeading = safeAreaInsets.leading
        let safeTrailing = safeAreaInsets.trailing

        let imageSize = responsiveImageSize(screenWidth: w, screenHeight: h)
        let halfImageSize = imageSize / 2
        let isLandscape = w > h

        // Horizontal center of the layout rect; vertical center for left/right slots.
        let midX = w / 2
        let midY = h / 2

        let top = CGPoint(x: midX, y: safeTop + halfImageSize + 20)
        let bottom = CGPoint(x: midX, y: h - safeBottom - halfImageSize - 20)
        let left: CGPoint
        let right: CGPoint
        if isLandscape {
            left = CGPoint(x: max(safeLeading + halfImageSize + 20, halfImageSize + 40), y: midY)
            right = CGPoint(x: min(w - safeTrailing - halfImageSize - 20, w - halfImageSize - 20), y: midY)
        } else {
            left = CGPoint(x: safeLeading + halfImageSize + 20, y: midY)
            right = CGPoint(x: w - safeTrailing - halfImageSize - 20, y: midY)
        }

        return [.up: top, .down: bottom, .left: left, .right: right]
    }

    /// Legacy: full-screen coordinates (can disagree with a `GeometryReader` inside navigation). Prefer `positions(in:safeAreaInsets:)`.
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
        return positions(in: b.size, safeAreaInsets: insets)
    }

    static func centerPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private static func responsiveImageSize(screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let isLandscape = screenWidth > screenHeight
        if isIPad {
            return isLandscape ? screenHeight * 0.30 : screenWidth * 0.30
        }
        return isLandscape ? screenHeight * 0.20 : screenWidth * 0.29
    }
}
