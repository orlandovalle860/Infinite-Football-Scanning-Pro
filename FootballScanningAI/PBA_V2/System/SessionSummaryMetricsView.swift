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
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: visual.icon)
                        .font(.title2.weight(.semibold))
                    Text(visual.title)
                        .font(.title2)
                        .bold()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(visual.color.opacity(0.15))
                .foregroundColor(visual.color)
                .cornerRadius(18)

                Text("Score: \(score)")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
            }

            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    HStack(spacing: 6) {
                        Image(systemName: tag.icon)
                            .font(.caption.weight(.semibold))
                        Text(tag.label)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tag.color.opacity(0.15))
                    .foregroundColor(tag.color)
                    .cornerRadius(12)
                }
            }
            .frame(maxWidth: .infinity)

            summaryDivider

            VStack(spacing: 12) {
                MetricRow(label: "Accuracy", value: "\(Int(accuracy * 100))%")
                MetricRow(label: "Avg Decision Time", value: String(format: "%.2fs", avgDecisionTime))
                MetricRow(label: "Decision Window", value: String(format: "%.2fs", decisionWindow))
                Text(DecisionTimingModel.timingContextLabel)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            summaryDivider

            VStack(alignment: .leading, spacing: 8) {
                MetricRow(label: "Timing Score", value: "\(timingBreakdown.scorePercent) (\(timingBreakdown.scoreBand))")
                MetricRow(label: "Early", value: "\(timingBreakdown.earlyCount)")
                MetricRow(label: "On Time", value: "\(timingBreakdown.onTimeCount)")
                MetricRow(label: "Late", value: "\(timingBreakdown.lateCount)")
                Text(timingBreakdown.averageTimingLabel)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.78))
                Text(timingBreakdown.feedback)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text(timingBreakdown.progressionHint)
                    .font(.caption)
                    .foregroundColor(.cyan.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            summaryDivider

            VStack(alignment: .leading, spacing: 8) {
                MetricRow(label: "Level", value: level)
                Text(shortFeedback)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tempo guidance: \(tempoGuidance)")
                    .font(.caption)
                    .foregroundColor(.cyan.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestion = progressionSuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            summaryDivider

            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            summaryDivider

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
