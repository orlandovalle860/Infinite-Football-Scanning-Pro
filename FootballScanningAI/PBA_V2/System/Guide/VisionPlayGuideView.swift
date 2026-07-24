//
//  VisionPlayGuideView.swift
//  FootballScanningAI
//
//  Guide container — table of contents + reusable page reader.
//

import SwiftUI

struct VisionPlayGuideView: View {
    /// When set, opens directly on that page (e.g. activity ⓘ / Open Guide). Nil opens the contents list.
    var initialPage: VisionPlayGuidePageID? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var path: NavigationPath

    init(initialPage: VisionPlayGuidePageID? = nil) {
        self.initialPage = initialPage
        if let initialPage {
            var initialPath = NavigationPath()
            initialPath.append(initialPage)
            _path = State(initialValue: initialPath)
        } else {
            _path = State(initialValue: NavigationPath())
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VisionPlayGuideContentsView { page in
                path.append(page)
            }
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .navigationDestination(for: VisionPlayGuidePageID.self) { page in
                VisionPlayGuideReaderView(
                    startingPage: page,
                    onClose: { dismiss() }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Contents

private struct VisionPlayGuideContentsView: View {
    let onSelect: (VisionPlayGuidePageID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Text("How to use VisionPlay")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.top, 12)

                Text("A short reference. Jump to any page.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))

                ForEach(VisionPlayGuideSection.allCases) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundColor(.yellow.opacity(0.95))

                        VStack(spacing: 0) {
                            ForEach(Array(section.pages.enumerated()), id: \.element) { index, pageID in
                                let content = VisionPlayGuideCatalog.content(for: pageID)
                                Button {
                                    onSelect(pageID)
                                } label: {
                                    HStack {
                                        Text(content.contentsTitle)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.white.opacity(0.95))
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 12)
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < section.pages.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.12))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Reader (prev/next swaps page in place)

private struct VisionPlayGuideReaderView: View {
    let onClose: () -> Void

    @State private var pageID: VisionPlayGuidePageID

    init(startingPage: VisionPlayGuidePageID, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _pageID = State(initialValue: startingPage)
    }

    private var content: VisionPlayGuidePageContent {
        VisionPlayGuideCatalog.content(for: pageID)
    }

    var body: some View {
        VisionPlayGuidePageView(
            content: content,
            canGoPrevious: pageID.previous != nil,
            canGoNext: pageID.next != nil,
            onPrevious: {
                if let previous = pageID.previous {
                    pageID = previous
                }
            },
            onNext: {
                if let next = pageID.next {
                    pageID = next
                } else {
                    onClose()
                }
            },
            onClose: onClose
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
    }
}
