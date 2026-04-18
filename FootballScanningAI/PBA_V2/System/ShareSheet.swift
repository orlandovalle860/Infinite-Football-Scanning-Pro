//
//  ShareSheet.swift
//  FootballScanningAI
//
//  PBA V2 — One-tap share via UIActivityViewController (text or image).
//

import SwiftUI
import UIKit

/// Rasterized for `UIActivityViewController` via ``View/asImage()``.
struct ShareCardView: View {
    let activity: String
    let score: Int
    let level: String
    let accuracy: Int
    let avgTime: Double
    let fast: Int
    let onTime: Int
    let late: Int

    var body: some View {
        VStack(spacing: 20) {
            Text(activity)
                .font(.subheadline)
                .foregroundColor(.gray)

            Text("\(score)")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: Color.white.opacity(0.2), radius: 10)

            Text(level)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.white)

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Text("🎯 \(accuracy)%")
                    Text(String(format: "⏱ %.1fs", avgTime))
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.95))

                HStack(spacing: 16) {
                    Text("⚡ \(fast)")
                    Text("✓ \(onTime)")
                    Text("• \(late)")
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.95))
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)

            Text("Can you beat this?")
                .font(.headline)
                .foregroundColor(.yellow)

            Text("PBA Training")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(28)
        .frame(width: 320)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.9),
                    Color.black.opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Block session share (plain text + ShareCard image)

struct BlockShareSheetPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Single builder for block-result sharing used by ``SessionSummaryScreenView`` and Display (iPad) results.
enum SessionBlockShare {
    static func activityItems(
        session: SessionResult,
        playerName: String,
        playerRecommendation: PlayerRecommendation
    ) -> [Any] {
        [
            plainText(session: session, playerName: playerName, playerRecommendation: playerRecommendation),
            shareCardImage(session: session, playerRecommendation: playerRecommendation)
        ]
    }

    static func decisionScoreValue(session: SessionResult) -> Int {
        if let score = session.decisionTotalScore {
            return max(0, min(100, Int(score.rounded())))
        }
        return session.estimatedDecisionSpeedScore ?? 0
    }

    static func plainText(
        session: SessionResult,
        playerName _: String,
        playerRecommendation _: PlayerRecommendation
    ) -> String {
        let activityTitle = activityTitle(for: session.activityType)
        let score = decisionScoreValue(session: session)
        let accPct = accuracyPercent(session: session)
        let avgReaction = String(format: "%.2fs", session.avgDecisionTime ?? 0)
        return [
            activityTitle,
            "",
            "\(score) | \(accPct)% | \(avgReaction)",
            "",
            "Can you beat this?"
        ].joined(separator: "\n")
    }

    private static func activityTitle(for kind: ActivityKind) -> String {
        switch kind {
        case .twoMinuteTest: return "2-Minute Test"
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        }
    }

    private static func accuracyPercent(session: SessionResult) -> Int {
        guard session.totalReps > 0 else { return 0 }
        return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100.0))
    }

    private static func shareCardImage(session: SessionResult, playerRecommendation: PlayerRecommendation) -> UIImage {
        ShareCardView(
            activity: activityTitle(for: session.activityType),
            score: decisionScoreValue(session: session),
            level: playerRecommendation.level.rawValue,
            accuracy: accuracyPercent(session: session),
            avgTime: max(0, session.avgDecisionTime ?? 0),
            fast: session.speedCounts.fast,
            onTime: session.speedCounts.medium,
            late: session.speedCounts.slow
        ).asImage()
    }
}
