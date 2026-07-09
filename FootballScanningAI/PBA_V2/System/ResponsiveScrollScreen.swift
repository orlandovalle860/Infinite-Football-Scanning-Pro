//
//  ResponsiveScrollScreen.swift
//  FootballScanningAI
//
//  Centers content when vertical space allows; scrolls when space is limited (e.g. landscape).
//

import SwiftUI

struct ResponsiveScrollScreen<Content: View>: View {
    var horizontalPadding: CGFloat
    var bottomPadding: CGFloat
    var maxContentWidth: CGFloat
    let content: Content

    init(
        horizontalPadding: CGFloat = 28,
        bottomPadding: CGFloat = 32,
        maxContentWidth: CGFloat = 420,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.bottomPadding = bottomPadding
        self.maxContentWidth = maxContentWidth
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack {
                    content
                }
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, max(bottomPadding, geometry.safeAreaInsets.bottom))
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
    }
}
