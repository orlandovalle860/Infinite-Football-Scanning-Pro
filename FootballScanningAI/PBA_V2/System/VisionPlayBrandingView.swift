//
//  VisionPlayBrandingView.swift
//  FootballScanningAI
//
//  Shared VisionPlay brand header for home, session chrome, and summaries.
//

import SwiftUI

enum VisionPlayBrandingStyle {
    /// Home + session summary: stacked title and tagline.
    case prominentDark
    /// Timed session container / coach remote: single unobtrusive line.
    case sessionChrome
}

struct VisionPlayBrandingView: View {
    let style: VisionPlayBrandingStyle

    var body: some View {
        switch style {
        case .prominentDark:
            prominentBranding
        case .sessionChrome:
            sessionChromeBranding
        }
    }

    private var prominentBranding: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VisionPlay")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            Text("See the Game")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("VisionPlay. See the Game.")
    }

    private var sessionChromeBranding: some View {
        Text("VisionPlay • See the Game")
            .font(.caption2.weight(.medium))
            .foregroundColor(.white.opacity(0.38))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("VisionPlay. See the Game.")
    }
}
