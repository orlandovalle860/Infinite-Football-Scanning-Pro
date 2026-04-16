//
//  ProgressionView.swift
//  FootballScanningAI
//
//  PBA V2 — Recent sessions list with trend arrows and insight (session summary).
//

import SwiftUI

struct ProgressionView: View {
    let sessions: [SessionPerformance]
    let scoreTrend: TrendDirection
    let windowTrend: TrendDirection
    let accuracyTrend: TrendDirection
    let insight: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress")
                .font(.headline)
                .foregroundColor(.white.opacity(0.95))

            HStack(spacing: 14) {
                trendLabel("Score", scoreTrend)
                trendLabel("Window", windowTrend)
                trendLabel("Accuracy", accuracyTrend)
            }

            Text(insight)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, s in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundColor(.white.opacity(0.5))
                            Text(shortActivity(s.activity))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("Score \(s.score)")
                            Text(String(format: "%.2fs", s.avgDecisionTime))
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }

    private func trendLabel(_ title: String, _ trend: TrendDirection) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundColor(.white.opacity(0.65))
            Text(trend.arrowSymbol)
                .font(.body.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
        }
        .font(.caption)
    }

    private func shortActivity(_ activity: TrainingActivityType) -> String {
        switch activity {
        case .awayFromPressure: return "AFP"
        case .dribbleOrPass: return "DOP"
        case .oneTouchPassing: return "OTP"
        case .twoMinuteTest: return "2m"
        }
    }
}
