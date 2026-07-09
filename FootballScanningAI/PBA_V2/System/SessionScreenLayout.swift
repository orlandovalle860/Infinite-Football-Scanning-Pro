//
//  SessionScreenLayout.swift
//  FootballScanningAI
//
//  Option A: full-screen session wrapper only. Chrome (timer + End) stays on
//  soloSessionTimerOverlay — do not add it here.
//

import SwiftUI

/// Shared full-bleed container for in-session display views.
///
/// Gameplay layout uses GeometryReader + safeAreaInsets. Do not modify layout here.
/// Apply `.soloSessionTimerOverlay` (and other overlays) *after* wrapping with this view.
struct SessionScreenLayout<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Visual bleed only — does not shrink GeometryReader or shift gameplay math.
            content
                .ignoresSafeArea()
        }
    }
}
