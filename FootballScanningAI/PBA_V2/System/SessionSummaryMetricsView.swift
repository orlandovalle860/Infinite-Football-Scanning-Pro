//
//  SessionSummaryMetricsView.swift
//  FootballScanningAI
//
//  PBA V2 — Premium session summary layout (metrics, coaching, next focus).
//

import SwiftUI

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.62))
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

struct SessionSummaryView: View {
    let score: Int
    let visual: FeedbackVisual
    let tags: [FeedbackTag]
    let accuracy: Double
    let avgDecisionTime: Double
    let decisionWindow: Double
    let level: String
    let shortFeedback: String
    let message: String
    let nextFocus: String
    let tempoGuidance: String
    let progressionSuggestion: String?
    var earlyCount: Int = 0
    var onTimeCount: Int = 0
    var lateCount: Int = 0

    private var timingBreakdown: TimingScoreBreakdown {
        TimingScoreSystem.makeBreakdown(
            early: earlyCount,
            onTime: onTimeCount,
            late: lateCount,
            averageDecisionOffset: decisionWindow
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Score: \(score)")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                Text("Level: \(level)")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
            }

            summaryDivider

            Text(message)
                .font(.body.weight(.semibold))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            summaryDivider

            VStack(spacing: 10) {
                MetricRow(label: "Accuracy", value: "\(Int(accuracy * 100))%")
                MetricRow(label: "Avg Time", value: String(format: "%.1fs", avgDecisionTime))
            }

            summaryDivider

            VStack(alignment: .leading, spacing: 10) {
                Text("Timing")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                MetricRow(label: "Early", value: "\(timingBreakdown.earlyCount)")
                MetricRow(label: "On Time", value: "\(timingBreakdown.onTimeCount)")
                MetricRow(label: "Late", value: "\(timingBreakdown.lateCount)")
            }

            VStack(spacing: 8) {
                Text("Next Focus")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                Text(nextFocus)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
    }

    private var summaryDivider: some View {
        Divider()
            .background(Color.white.opacity(0.18))
    }
}
