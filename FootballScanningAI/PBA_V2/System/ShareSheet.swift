//
//  ShareSheet.swift
//  FootballScanningAI
//
//  PBA V2 — One-tap share via UIActivityViewController (text or image).
//

import SwiftUI
import UIKit

// MARK: - Share card timing (maps from dominant `SpeedBucket`; no scoring changes)

fileprivate enum DecisionTimingCategory {
    case early
    case onTime
    case late
}

private func decisionTimingCategory(from bucket: SpeedBucket) -> DecisionTimingCategory {
    switch bucket {
    case .fast: return .early
    case .medium: return .onTime
    case .slow: return .late
    }
}

private func nextLevelText(timing: DecisionTimingCategory) -> String {
    switch timing {
    case .early:
        return "Maintain early decisions to stay elite"
    case .onTime:
        return "Be earlier on more reps to reach 100"
    case .late:
        return "Decide before the ball arrives to increase your score"
    }
}

// MARK: - Square share card (aligned with in-app session results)

/// Rasterized for `UIActivityViewController` via ``View/asImage()`` — **1080×1080** for social feeds.
struct ShareCardView: View {
    let activityTitle: String
    let score: Int
    /// Performance band from `playerRecommendation.level` (e.g. Reactive … Elite).
    let scoreBandLabel: String
    let correctCount: Int
    let totalReps: Int
    fileprivate let timingCategory: DecisionTimingCategory
    let decisionQualityLine: String
    let timingHeadline: String
    let timingColor: Color
    let coachingLine: String
    private let footerLine = "Perception Before Action"

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12)
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Text(activityTitle)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 56)

                Spacer().frame(height: 44)

                VStack(spacing: 12) {
                    Text("\(score)")
                        .font(.system(size: 132, weight: .bold, design: .rounded))
                        .foregroundColor(score == 100 ? .green : .white)
                        .perfectScoreHighlight(score: score)

                    if score < 100 {
                        Text("\(100 - score) points left — earlier decisions unlock 100")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(scoreBandLabel)
                        .font(.headline)
                        .foregroundColor(score == 100 ? .green : .secondary)

                    if timingCategory != .early {
                        Text("Earlier decisions unlock higher scores")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text("Driven by")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.secondary)

                        if totalReps > 0, correctCount == totalReps {
                            Text("Perfect decisions")
                        } else {
                            Text("\(correctCount)/\(totalReps) correct decisions")
                        }

                        Text("Timing: \(timingHeadline)")
                    }
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                }

                Spacer().frame(height: 40)

                VStack(spacing: 14) {
                    Text("Decision Quality")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Text(decisionQualityLine)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }

                Spacer().frame(height: 40)

                VStack(spacing: 14) {
                    Text("Decision Timing")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    Text(timingHeadline)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(timingColor)
                }

                Spacer().frame(height: 36)

                Text(coachingLine)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 64)

                Spacer().frame(height: 12)

                Text(nextLevelText(timing: timingCategory))
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 56)

                Spacer().frame(height: 40)

                Text(footerLine)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(0.8)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 72)
        }
        .frame(width: 1080, height: 1080)
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
@MainActor
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
        playerRecommendation: PlayerRecommendation
    ) -> String {
        let score = decisionScoreValue(session: session)
        let ratio = "\(session.correctCount)/\(session.totalReps)"
        if score == 100 {
            let activityName = session.activityType.displayName
            return """
\(activityName)

100 (Perfect) | \(ratio) | Early

Can you match this?
"""
        }
        let scoreBandLabel = playerRecommendation.level.rawValue
        let timing = timingHeadlineLabel(dominantTimingBucket(session: session))
        let line = "\(score) (\(scoreBandLabel)) | \(ratio) | \(timing)"
        return "\(line)\n\nCan you beat this?"
    }

    /// Single stats line: `score (Band) | correct/total | Early|On Time|Late` (competitive, minimal).
    static func shareCaptionLine(session: SessionResult, playerRecommendation: PlayerRecommendation) -> String {
        let score = decisionScoreValue(session: session)
        let ratio = "\(session.correctCount)/\(session.totalReps)"
        if score == 100 {
            return "100 (Perfect) | \(ratio) | Early"
        }
        let scoreBandLabel = playerRecommendation.level.rawValue
        let timing = timingHeadlineLabel(dominantTimingBucket(session: session))
        return "\(score) (\(scoreBandLabel)) | \(ratio) | \(timing)"
    }

    static func decisionQualityLine(session: SessionResult) -> String {
        let correct = session.correctCount
        let total = session.totalReps
        if total > 0, correct == total {
            return "Perfect decisions (\(correct) / \(total))"
        }
        return "\(correct) / \(total) correct"
    }

    static func dominantTimingBucket(session: SessionResult) -> SpeedBucket {
        let c = session.speedCounts
        return UniversalBlockSummaryHeadline.resolve(fast: c.fast, medium: c.medium, slow: c.slow).bucket
    }

    static func timingHeadlineLabel(_ bucket: SpeedBucket) -> String {
        switch bucket {
        case .fast: return "Early"
        case .medium: return "On Time"
        case .slow: return "Late"
        }
    }

    static func timingShareColor(_ bucket: SpeedBucket) -> Color {
        switch bucket {
        case .fast: return .green
        case .medium: return .yellow
        case .slow: return .red
        }
    }

    /// Share image only: honest coaching line (perfect score vs accuracy vs commit earlier).
    static func shareCardCoachingLine(session: SessionResult) -> String {
        let score = decisionScoreValue(session: session)
        if score == 100 {
            return "Perfect — early on every rep."
        }
        let correct = session.correctCount
        let total = session.totalReps
        if total > 0, correct == total {
            return "Perfect decisions — decide earlier."
        } else {
            return "Decide earlier."
        }
    }

    private static func shareCardImage(session: SessionResult, playerRecommendation: PlayerRecommendation) -> UIImage {
        let bucket = dominantTimingBucket(session: session)
        let scoreBandLabel = playerRecommendation.level.rawValue
        let timingCat = decisionTimingCategory(from: bucket)
        let card = ShareCardView(
            activityTitle: session.activityType.displayName,
            score: decisionScoreValue(session: session),
            scoreBandLabel: scoreBandLabel,
            correctCount: session.correctCount,
            totalReps: session.totalReps,
            timingCategory: timingCat,
            decisionQualityLine: decisionQualityLine(session: session),
            timingHeadline: timingHeadlineLabel(bucket),
            timingColor: timingShareColor(bucket),
            coachingLine: shareCardCoachingLine(session: session)
        )
        return card.asImage()
    }
}
