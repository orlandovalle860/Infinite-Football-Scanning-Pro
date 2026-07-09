//
//  ProgressBarView.swift
//  FootballScanningAI
//
//  Reusable minimal progress bar.
//

import SwiftUI

struct ProgressBarView: View {
    let value: Int
    let maxValue: Int
    @State private var animatedValue: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let targetWidth = maxValue > 0
                ? CGFloat(value) / CGFloat(maxValue) * geo.size.width
                : 0

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: animatedValue)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) {
                    animatedValue = targetWidth
                }
            }
            .onChange(of: value) { _, _ in
                withAnimation(.easeOut(duration: 0.35)) {
                    animatedValue = targetWidth
                }
            }
            .onChange(of: maxValue) { _, _ in
                withAnimation(.easeOut(duration: 0.35)) {
                    animatedValue = targetWidth
                }
            }
        }
        .frame(height: 8)
    }
}
