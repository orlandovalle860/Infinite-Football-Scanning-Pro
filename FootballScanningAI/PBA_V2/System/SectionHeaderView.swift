//
//  SectionHeaderView.swift
//  FootballScanningAI
//
//  Reusable section title + total metadata header.
//

import SwiftUI

struct SectionHeaderView: View {
    let title: String
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("Total: \(total) reps")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
