//
//  PlayerReport.swift
//  FootballScanningAI
//
//  PBA V2 — Player report for session summaries (coach/parent-friendly).
//

import Foundation
import SwiftUI

struct PlayerReport: Equatable {
    let playerName: String
    let level: PlayerLevel
    let score: Int
    let accuracy: Double
    let decisionWindow: Double
    let trendWindow: TrendDirection
    let trendAccuracy: TrendDirection
    let profile: String
    let insight: String
    let nextFocus: String
}

func generatePlayerReport(
    playerName: String,
    progression: PlayerProgression,
    score: Int,
    accuracy: Double,
    decisionWindow: Double,
    trendWindow: TrendDirection,
    trendAccuracy: TrendDirection,
    recommendation: LevelRecommendation
) -> PlayerReport {

    let profile: String
    let insight: String

    if decisionWindow > 0 && accuracy >= 0.75 {
        profile = "Fast and Accurate"
        insight = "You are anticipating pressure and executing well."
    } else if decisionWindow > 0 {
        profile = "Fast but Inconsistent"
        insight = "Speed is improving, but accuracy needs work."
    } else if accuracy >= 0.75 {
        profile = "Accurate but Late"
        insight = "You read the game well but react too late."
    } else {
        profile = "Reactive"
        insight = "You are reacting after pressure arrives."
    }

    return PlayerReport(
        playerName: playerName,
        level: progression.currentLevel,
        score: score,
        accuracy: accuracy,
        decisionWindow: decisionWindow,
        trendWindow: trendWindow,
        trendAccuracy: trendAccuracy,
        profile: profile,
        insight: insight,
        nextFocus: recommendation.focus
    )
}

// MARK: - Export (share / email / future PDF)

extension PlayerReport {
    /// Single plain-text block for UIActivityViewController, mail body, or future PDF generation.
    var exportPlainTextSummary: String {
        let wArrow = trendWindow.arrowSymbol
        let aArrow = trendAccuracy.arrowSymbol
        let lines: [String] = [
            "\(playerName) — Player report",
            "Level: \(level.rawValue)",
            "",
            "Score: \(score)",
            String(format: "Accuracy: %.0f%%", accuracy * 100),
            String(format: "Decision window: %.2fs", decisionWindow),
            "Window trend: \(wArrow) · Accuracy trend: \(aArrow)",
            "",
            "Profile: \(profile)",
            insight,
            "",
            "Next focus: \(nextFocus)"
        ]
        return lines.joined(separator: "\n")
    }
}

/// Session-summary report (PBA block). Distinct from `PlayerReportView` in `PlayerReportView.swift`, which uses `PlayerReportContent` for 2-minute test / progress flows.
struct SessionPlayerReportView: View {
    let report: PlayerReport

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    Text(report.playerName)
                        .font(.title)
                        .bold()

                    Text("Level: \(report.level.rawValue)")
                        .font(.headline)

                    Divider()

                    VStack {
                        Text("Score: \(report.score)")
                        Text("Accuracy: \(Int(report.accuracy * 100))%")
                        Text(String(format: "Decision Window: %.2fs", report.decisionWindow))
                        Text(DecisionTimingModel.timingContextLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    Text("Profile: \(report.profile)")

                    Text(report.insight)
                        .multilineTextAlignment(.center)

                    Divider()

                    Text("Next Focus")
                        .font(.headline)

                    Text(report.nextFocus)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Player report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share report")
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [report.exportPlainTextSummary])
            }
        }
    }
}

#Preview("Session player report") {
    SessionPlayerReportView(
        report: generatePlayerReport(
            playerName: "Alex",
            progression: PlayerProgression(
                currentLevel: .anticipating,
                avgDecisionWindow: 0.08,
                avgAccuracy: 0.72
            ),
            score: 82,
            accuracy: 0.78,
            decisionWindow: 0.12,
            trendWindow: .up,
            trendAccuracy: .stable,
            recommendation: getLevelRecommendation(level: .anticipating)
        )
    )
}
