//
//  SoloSessionCompleteOverlay.swift
//  FootballScanningAI
//
//  Solo session end: minimal post-session feedback overlay.
//

import SwiftUI

extension View {
    /// Full-screen solo session complete overlay (not navigation).
    @ViewBuilder
    func soloSessionCompleteOverlay(
        isPresented: Bool,
        elapsedSeconds: TimeInterval,
        repCount: Int,
        repTarget: Int? = nil,
        onDone: @escaping () -> Void
    ) -> some View {
        ZStack {
            self
            if isPresented {
                PostSessionFeedbackView(
                    repCount: repCount,
                    durationSeconds: elapsedSeconds,
                    repTarget: repTarget,
                    onDone: onDone
                )
                .transition(.opacity)
                .zIndex(300)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
}

/// Backward-compatible name for any remaining references.
typealias SoloTimeBasedSessionCompleteView = PostSessionFeedbackView
