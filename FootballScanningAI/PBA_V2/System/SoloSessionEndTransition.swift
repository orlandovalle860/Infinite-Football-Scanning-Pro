//
//  SoloSessionEndTransition.swift
//  FootballScanningAI
//
//  User-initiated solo session end: haptic, freeze, brief closure, then completion overlay.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum SoloSessionEndTransition {
  private static let overlayDelayNs: UInt64 = 100_000_000

  static func lightImpact() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
  }

  /// Tap/long-press End: haptic → freeze → ~100ms closure → overlay.
  @MainActor
  static func beginUserEnd(
    setEnding: @escaping () -> Void,
    freeze: @escaping () -> Void,
    presentOverlay: @escaping () -> Void,
    clearEnding: @escaping () -> Void
  ) {
    lightImpact()
    setEnding()
    freeze()
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: overlayDelayNs)
      presentOverlay()
      clearEnding()
    }
  }
}

extension View {
  /// Subtle drill dim while the session is closing before the completion overlay.
  @ViewBuilder
  func soloSessionEndingDim(isActive: Bool) -> some View {
    overlay {
      if isActive {
        Color.black.opacity(0.06)
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.1), value: isActive)
  }
}
