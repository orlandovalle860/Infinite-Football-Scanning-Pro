//
//  ActivitySessionStartCueView.swift
//  FootballScanningAI
//
//  One-shot session-start coaching line: fade in, hold, fade out (~3.5s total).
//

import SwiftUI

enum ActivitySessionStartCueInlineVisual: Equatable {
    case imageAsset(String)
    case awayFromPressureDefenderLane
    case dribbleOrPassTeammateLane
}

struct ActivitySessionStartCueContent: Equatable {
    let leadingText: String
    var inlineVisual: ActivitySessionStartCueInlineVisual? = nil
    var trailingText: String = ""
}

struct ActivitySessionStartCueView: View {
    let content: ActivitySessionStartCueContent
    var inlineVisualSideLength: CGFloat = 28
    var onFinished: () -> Void = {}

    /// Gap between cue text and the top of the center marker (pt).
    static let spacingAboveCenterMarker: CGFloat = 100

    /// Inline cue visual opacity (stimulus uses full opacity when revealed).
    static let inlineVisualOpacity: Double = 0.75

    private static let fadeInDuration: TimeInterval = 0.5
    private static let holdDuration: TimeInterval = 2.5
    private static let fadeOutDuration: TimeInterval = 0.5

    @State private var displayOpacity = 0.0

    var body: some View {
        cueLabel
            .opacity(displayOpacity)
            .allowsHitTesting(false)
            .onAppear(perform: runPresentation)
    }

    private var cueLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(content.leadingText)
            if let visual = content.inlineVisual {
                inlineVisualView(visual)
            }
            if !content.trailingText.isEmpty {
                Text(content.trailingText)
            }
        }
        .font(.title2.weight(.semibold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func inlineVisualView(_ visual: ActivitySessionStartCueInlineVisual) -> some View {
        switch visual {
        case .imageAsset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: inlineVisualSideLength, height: inlineVisualSideLength)
                .shadow(radius: 2)
                .opacity(Self.inlineVisualOpacity)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[.bottom] * 0.82
                }
        case .awayFromPressureDefenderLane:
            AwayFromPressureGateOverlay.SessionStartInlineDefenderBar(
                length: inlineVisualSideLength,
                opacity: Self.inlineVisualOpacity
            )
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.bottom] * 0.82
            }
        case .dribbleOrPassTeammateLane:
            DribbleOrPassGateOverlay.SessionStartInlineTeammateBar(
                length: inlineVisualSideLength,
                opacity: Self.inlineVisualOpacity
            )
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.bottom] * 0.82
            }
        }
    }

    /// Scales inline visuals smaller than the gameplay stimulus.
    static func inlineVisualSideLength(relativeTo gameplayReference: CGFloat) -> CGFloat {
        min(max(gameplayReference * 0.28, 26), 44)
    }

    private func runPresentation() {
        displayOpacity = 0
        withAnimation(.easeIn(duration: Self.fadeInDuration)) {
            displayOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeInDuration + Self.holdDuration) {
            withAnimation(.easeOut(duration: Self.fadeOutDuration)) {
                displayOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOutDuration) {
                onFinished()
            }
        }
    }
}

struct SessionStartCueHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
