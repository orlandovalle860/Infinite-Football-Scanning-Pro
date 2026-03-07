//
//  PlayerReportView.swift
//  FootballScanningAI
//
//  PBA V2 — Player Report: decision style, strength, needs improvement, training recommendation.
//

import SwiftUI

struct PlayerReportView: View {
    let content: PlayerReportContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Player Report")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Decision Style: \(content.decisionStyle)")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                }

                reportSection(title: "Strength", text: content.strength)
                reportSection(title: "Needs Improvement", text: content.needsImprovement)
                reportSection(title: "Training Recommendation", text: content.trainingRecommendation)

                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private func reportSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
