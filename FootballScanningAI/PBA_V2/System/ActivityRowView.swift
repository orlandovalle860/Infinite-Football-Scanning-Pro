//
//  ActivityRowView.swift
//  FootballScanningAI
//
//  Reusable activity row with label, bar, and value.
//

import SwiftUI

struct ActivityRowView: View {
    let title: String
    let value: Int
    let maxValue: Int
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            ProgressBarView(
                value: value,
                maxValue: maxValue
            )

            HStack {
                Spacer()
                Text("\(value)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                isVisible = true
            }
        }
    }
}
