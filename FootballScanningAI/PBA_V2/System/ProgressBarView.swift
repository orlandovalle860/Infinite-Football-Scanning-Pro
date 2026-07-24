//
//  ProgressBarView.swift
//  FootballScanningAI
//
//  Reusable minimal progress bar.
//  Fills proportionally: value / maxValue of the track width.
//

import SwiftUI

struct ProgressBarView: View {
    let value: Int
    let maxValue: Int

    /// Relative fill within the current section (0...1).
    private var fraction: CGFloat {
        guard maxValue > 0 else { return 0 }
        return min(1, max(0, CGFloat(value) / CGFloat(maxValue)))
    }

    var body: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * fraction

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}
