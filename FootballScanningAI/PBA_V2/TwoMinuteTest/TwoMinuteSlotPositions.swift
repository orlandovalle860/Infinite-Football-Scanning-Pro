//
//  TwoMinuteSlotPositions.swift
//  FootballScanningAI
//
//  PBA V2 — Same positions as Dribble or Pass (Middle Up/Down/Left/Right). Used so the ball appears where players would be.
//

import CoreGraphics
import UIKit

enum TwoMinuteSlotPositions {
    /// Returns the four gate positions matching Dribble or Pass getPlayerPosition logic (same safe area + responsive size).
    static func positionsForCurrentScreen() -> [Gate: CGPoint] {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        var safeAreaTop: CGFloat = 0, safeAreaBottom: CGFloat = 0, safeAreaLeft: CGFloat = 0, safeAreaRight: CGFloat = 0
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            safeAreaTop = window.safeAreaInsets.top
            safeAreaBottom = window.safeAreaInsets.bottom
            safeAreaLeft = window.safeAreaInsets.left
            safeAreaRight = window.safeAreaInsets.right
        }

        let imageSize = responsiveImageSize(screenWidth: screenWidth, screenHeight: screenHeight)
        let halfImageSize = imageSize / 2
        let isLandscape = screenWidth > screenHeight

        let top = CGPoint(x: screenWidth / 2, y: safeAreaTop + halfImageSize + 20)
        let bottom = CGPoint(x: screenWidth / 2, y: screenHeight - safeAreaBottom - halfImageSize - 20)
        let left: CGPoint
        let right: CGPoint
        if isLandscape {
            left = CGPoint(x: max(safeAreaLeft + halfImageSize + 20, halfImageSize + 40), y: screenHeight / 2)
            right = CGPoint(x: min(screenWidth - safeAreaRight - halfImageSize - 20, screenWidth - halfImageSize - 20), y: screenHeight / 2)
        } else {
            left = CGPoint(x: halfImageSize + 20, y: screenHeight / 2)
            right = CGPoint(x: screenWidth - halfImageSize - 20, y: screenHeight / 2)
        }

        return [.up: top, .down: bottom, .left: left, .right: right]
    }

    static func centerPosition() -> CGPoint {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        return CGPoint(x: w / 2, y: h / 2)
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
