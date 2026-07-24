//
//  VisionPlayGuidePageView.swift
//  FootballScanningAI
//
//  Reusable Guide page layout — title, optional visual, short copy, prev/next/close.
//  Tuned so each page reads on one screen without scrolling at default sizes.
//

import SwiftUI

struct VisionPlayGuidePageView: View {
    let content: VisionPlayGuidePageContent
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    private var isActivityPage: Bool {
        content.visual != nil
            && content.id != .soloMode
            && content.id != .partnerModeSetup
    }
    private var isPartnerPage: Bool { content.id == .partnerMode }
    private var isSoloPage: Bool { content.id == .soloMode }
    private var isPartnerSetupPage: Bool { content.id == .partnerModeSetup }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let page = pageContent(availableHeight: geo.size.height, availableWidth: geo.size.width)
                // Prefer a single-screen layout; fall back to scroll only for very large Dynamic Type / tiny heights.
                ViewThatFits(in: .vertical) {
                    page
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    ScrollView {
                        page
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }

            navigationFooter
        }
        .background(guideBackground)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: onClose)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private func pageContent(availableHeight: CGFloat, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: isActivityPage || isPartnerSetupPage ? 10 : 16) {
            Text(content.title)
                .font(.system(size: isActivityPage || isPartnerSetupPage ? 24 : 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            if let visual = content.visual {
                let screenshotMaxHeight: CGFloat = {
                    if isPartnerSetupPage {
                        // Visual-first page — give the setup diagram most of the teaching space.
                        return availableHeight * 0.48
                    }
                    if isActivityPage || isSoloPage {
                        return availableHeight * 0.28
                    }
                    return availableHeight * 0.34
                }()
                VisionPlayGuideVisualView(
                    kind: visual,
                    maxWidth: min(isPartnerSetupPage ? 520 : 416, availableWidth - 56),
                    maxHeight: max(120, screenshotMaxHeight)
                )
            }

            if isPartnerPage {
                partnerBlocks
            } else {
                standardBlocks
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Standard blocks (Welcome, Solo, Activities)

    private var standardBlocks: some View {
        VStack(alignment: .leading, spacing: isActivityPage || isPartnerSetupPage ? 8 : 14) {
            ForEach(content.blocks) { block in
                guideBlock(block, emphasis: .standard)
            }
        }
    }

    // MARK: - Partner: Player → Coach → Timing as a clear sequence

    private var partnerBlocks: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(content.blocks.enumerated()), id: \.element.id) { index, block in
                let isTiming = block.heading?.lowercased() == "timing"
                let isLast = index == content.blocks.count - 1

                guideBlock(block, emphasis: isTiming ? .timing : .role)

                if !isLast {
                    if isTiming == false,
                       content.blocks[index + 1].heading?.lowercased() == "timing" {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                            .padding(.vertical, 14)
                    } else {
                        Spacer()
                            .frame(height: 12)
                    }
                }
            }
        }
    }

    private enum BlockEmphasis {
        case standard
        case role
        case timing
    }

    @ViewBuilder
    private func guideBlock(_ block: VisionPlayGuideTextBlock, emphasis: BlockEmphasis) -> some View {
        VStack(alignment: .leading, spacing: emphasis == .timing ? 6 : 5) {
            if let heading = block.heading {
                Text(heading.uppercased())
                    .font(headingFont(emphasis))
                    .tracking(headingTracking(emphasis))
                    .foregroundColor(.yellow.opacity(emphasis == .timing ? 1.0 : 0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            ForEach(Array(block.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(bodyFont(emphasis))
                    .foregroundColor(.white.opacity(emphasis == .timing ? 0.95 : 0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.9)
            }

            if !block.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(block.bullets.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .font(bodyFont(emphasis))
                                .foregroundColor(.white.opacity(0.40))
                            Text(line)
                                .font(bodyFont(emphasis))
                                .foregroundColor(.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                                .minimumScaleFactor(0.9)
                        }
                    }
                }
            }
        }
    }

    private func headingFont(_ emphasis: BlockEmphasis) -> Font {
        switch emphasis {
        case .standard:
            return .footnote.weight(.bold)
        case .role:
            return .footnote.weight(.bold)
        case .timing:
            return .subheadline.weight(.bold)
        }
    }

    private func headingTracking(_ emphasis: BlockEmphasis) -> CGFloat {
        switch emphasis {
        case .standard: return 1.0
        case .role: return 1.1
        case .timing: return 1.4
        }
    }

    private func bodyFont(_ emphasis: BlockEmphasis) -> Font {
        switch emphasis {
        case .standard:
            if isPartnerSetupPage { return .footnote }
            return isActivityPage ? .subheadline : .callout
        case .role:
            return .subheadline
        case .timing:
            return .callout
        }
    }

    private var navigationFooter: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(canGoPrevious ? 0.10 : 0.04))
                    .foregroundColor(.white.opacity(canGoPrevious ? 0.92 : 0.28))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!canGoPrevious)

            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text(canGoNext ? "Next" : "Done")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if canGoNext {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canGoNext ? Color.yellow : Color.white.opacity(0.10))
                .foregroundColor(canGoNext ? .black : .white.opacity(0.92))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.35)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var guideBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.1),
                Color(red: 0.1, green: 0.1, blue: 0.15)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
