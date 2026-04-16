//
//  WeeklyReport.swift
//  FootballScanningAI
//
//  PBA V2 — Weekly player report (coach / parent).
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WeeklyReport: Equatable {
    let playerName: String
    let weekRange: String
    let level: SessionPerformanceLevel

    let totalSessions: Int
    let averageScore: Int
    let averageEarlyPercentage: Double
    let averageDecisionOffset: Double

    let scoreTrend: TrendDirection
    let earlyTrend: TrendDirection
    let timingTrend: TrendDirection

    let recentScores: [Int]
    let earlyProgression: [Int]
    let timingProgression: [Double]

    let insight: String
    let focusCue: String
    let recommendedTempo: PassTempo
    let primaryBadge: PlayerBadge?
    let newBadge: PlayerBadge?
    let badgeRow: [PlayerBadge]
}

// MARK: - Week boundaries

/// Splits performances into the current calendar week and the previous calendar week (`referenceNow` defaults to today).
func splitSessionsIntoThisAndPreviousCalendarWeek(
    _ performances: [SessionPerformance],
    referenceNow: Date = Date()
) -> (thisWeek: [SessionPerformance], previousWeek: [SessionPerformance]) {
    let cal = Calendar.current
    guard let thisInterval = cal.dateInterval(of: .weekOfYear, for: referenceNow) else {
        return ([], [])
    }
    guard let previousWeekStart = cal.date(byAdding: .day, value: -7, to: thisInterval.start) else {
        return ([], [])
    }

    let thisWeek = performances.filter { $0.date >= thisInterval.start && $0.date < thisInterval.end }
    let previousWeek = performances.filter { $0.date >= previousWeekStart && $0.date < thisInterval.start }
    return (thisWeek, previousWeek)
}

func calendarWeekRangeLabel(referenceNow: Date = Date()) -> String {
    let cal = Calendar.current
    guard let interval = cal.dateInterval(of: .weekOfYear, for: referenceNow) else {
        return "This Week"
    }
    let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: interval.start, to: end)
}

// MARK: - Generate report

func generateWeeklyReport(
    sessions: [SessionResult],
    playerName: String,
    adaptiveState: AdaptiveTrainingState?,
    unlockedBadges: [PlayerBadge] = [],
    latestUnlockedBadge: PlayerBadge? = nil,
    referenceNow: Date = Date()
) -> WeeklyReport {
    let last7DaysStart = Calendar.current.date(byAdding: .day, value: -7, to: referenceNow) ?? referenceNow
    let weeklySessions = sessions
        .filter { $0.date >= last7DaysStart && $0.date <= referenceNow }
        .sorted(by: { $0.date < $1.date })
    let weekRange = rollingWeekRangeLabel(from: last7DaysStart, to: referenceNow)

    let snapshots = weeklySessions.map(weeklySnapshot)
    let totalSessions = snapshots.count
    let averageScore = totalSessions > 0 ? Int((Double(snapshots.map(\.score).reduce(0, +)) / Double(totalSessions)).rounded()) : 0
    let averageEarlyPct = totalSessions > 0 ? snapshots.map(\.earlyPercentage).reduce(0, +) / Double(totalSessions) : 0
    let averageOffset = totalSessions > 0 ? snapshots.map(\.averageDecisionOffset).reduce(0, +) / Double(totalSessions) : 0

    let first = snapshots.first
    let last = snapshots.last
    let scoreTrend = calculateTrend(values: [Double(first?.score ?? 0), Double(last?.score ?? 0)])
    let earlyTrend = calculateTrend(values: [first?.earlyPercentage ?? 0, last?.earlyPercentage ?? 0])
    let timingTrend = calculateTrend(values: [first?.averageDecisionOffset ?? 0, last?.averageDecisionOffset ?? 0])

    let insight = weeklyInsight(scoreTrend: scoreTrend, earlyTrend: earlyTrend)
    let level = adaptiveState?.currentLevel ?? weeklyLevelFromScore(averageScore)
    let focusCue = weeklyFocusCue(averageScore: averageScore)
    let recommendedTempo = adaptiveState?.currentTempo ?? weeklyTempoFromScore(averageScore)
    let primaryBadge = primaryShareBadge(from: unlockedBadges)
    let badgeRow = Array(unlockedBadges.suffix(3))

    return WeeklyReport(
        playerName: playerName,
        weekRange: weekRange,
        level: level,
        totalSessions: totalSessions,
        averageScore: averageScore,
        averageEarlyPercentage: averageEarlyPct,
        averageDecisionOffset: averageOffset,
        scoreTrend: scoreTrend,
        earlyTrend: earlyTrend,
        timingTrend: timingTrend,
        recentScores: snapshots.suffix(5).map(\.score),
        earlyProgression: snapshots.suffix(5).map { Int(($0.earlyPercentage * 100).rounded()) },
        timingProgression: snapshots.suffix(5).map(\.averageDecisionOffset),
        insight: insight,
        focusCue: focusCue,
        recommendedTempo: recommendedTempo,
        primaryBadge: primaryBadge,
        newBadge: latestUnlockedBadge,
        badgeRow: badgeRow
    )
}

private func primaryShareBadge(from badges: [PlayerBadge]) -> PlayerBadge? {
    let priority: [PlayerBadge] = [.aheadOfPlay, .onFire20, .onFire10, .onFire5, .onFire3, .levelUp, .earlyThinker, .lockedIn]
    for p in priority where badges.contains(p) {
        return p
    }
    return badges.last
}

private struct WeeklySnapshot {
    let score: Int
    let earlyPercentage: Double
    let latePercentage: Double
    let averageDecisionOffset: Double
}

private func weeklySnapshot(from session: SessionResult) -> WeeklySnapshot {
    let score: Int
    if let s = session.decisionTotalScore {
        score = max(0, min(100, Int(s.rounded())))
    } else {
        score = session.estimatedDecisionSpeedScore ?? 0
    }
    let total = session.speedCounts.fast + session.speedCounts.medium + session.speedCounts.slow
    let early = total > 0 ? Double(session.speedCounts.fast) / Double(total) : 0
    let late = total > 0 ? Double(session.speedCounts.slow) / Double(total) : 0
    return WeeklySnapshot(
        score: score,
        earlyPercentage: early,
        latePercentage: late,
        averageDecisionOffset: session.avgDecisionWindowSeconds ?? 0
    )
}

private func rollingWeekRangeLabel(from start: Date, to end: Date) -> String {
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: start, to: end)
}

private func weeklyLevelFromScore(_ score: Int) -> SessionPerformanceLevel {
    switch score {
    case ..<60: return .reactive
    case ..<75: return .developing
    case ..<90: return .advancing
    default: return .elite
    }
}

private func weeklyInsight(scoreTrend: TrendDirection, earlyTrend: TrendDirection) -> String {
    if scoreTrend == .up && earlyTrend == .up {
        return "You're deciding earlier each session — great progress."
    }
    if scoreTrend == .down || earlyTrend == .down {
        return "Refocus on early decision-making."
    }
    return "You’re steady — push for earlier decisions."
}

private func weeklyFocusCue(averageScore: Int) -> String {
    if averageScore >= 85 { return "Push for earlier decisions under pressure." }
    if averageScore >= 70 { return "Commit earlier on each rep." }
    return "Decide earlier before expected arrival."
}

private func weeklyTempoFromScore(_ score: Int) -> PassTempo {
    if score >= 85 { return .gameSpeed }
    if score >= 70 { return .controlled }
    return .controlled
}

private func timingSummary(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "No timing data yet." }
    let labels = values.map { value -> String in
        if value > 0.05 { return String(format: "Early by %.2fs", value) }
        if value < -0.05 { return String(format: "Late by %.2fs", abs(value)) }
        return "On Time"
    }
    return labels.joined(separator: " → ")
}

// MARK: - Export (PDF / email / share — future)

extension WeeklyReport {
    var exportPlainTextSummary: String {
        let lines: [String] = [
            "\(playerName) — Weekly report",
            weekRange,
            "Level: \(level.rawValue)",
            "",
            "Sessions: \(totalSessions)",
            String(format: "Average score: %d", averageScore),
            String(format: "Average early decisions: %.0f%%", averageEarlyPercentage * 100),
            String(format: "Average timing offset: %.2fs", averageDecisionOffset),
            "Score \(scoreTrend.arrowSymbol) · Early \(earlyTrend.arrowSymbol) · Timing \(timingTrend.arrowSymbol)",
            "",
            insight,
            "",
            "Next step: \(focusCue)",
            "Recommended tempo: \(recommendedTempo.displayName)",
            "Primary badge: \(primaryBadge?.title ?? "—")"
        ]
        return lines.joined(separator: "\n")
    }
}

struct WeeklyReportView: View {
    let report: WeeklyReport

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var showFormatPicker = false
    @State private var shareItems: [Any] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(report.playerName) — Weekly Report")
                            .font(.title2.weight(.bold))
                        Text("Sessions Completed: \(report.totalSessions)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(report.averageScore)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text(progressHighlightLabel(for: report.averageScore))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Score Trend")
                            .font(.headline)
                        Text(parentScoreTrendText)
                            .font(.title3.weight(.semibold))
                        Text(scoreTrendLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Decision Timing")
                            .font(.headline)
                        Text(parentTimingTrendText)
                            .font(.subheadline.weight(.semibold))
                        Text("Deciding earlier before the ball arrives")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Insight")
                            .font(.headline)
                        Text(report.insight)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next Focus")
                            .font(.headline)
                        Text("Decide before the ball reaches halfway")
                        Text("Say: \"Know your move before the ball gets to you\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Weekly report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFormatPicker = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share weekly report")
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: shareItems)
            }
            .confirmationDialog("Share Progress", isPresented: $showFormatPicker, titleVisibility: .visible) {
                Button("Square (1:1)") {
                    shareAsImage(.square)
                }
                Button("Story (9:16)") {
                    shareAsImage(.story)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var parentScoreTrendText: String {
        let values = Array(report.recentScores.suffix(4))
        guard !values.isEmpty else { return "No sessions yet." }
        return values.map(String.init).joined(separator: " → ")
    }

    private var scoreTrendLabel: String {
        switch report.scoreTrend {
        case .up: return "Improving each session"
        case .stable: return "Steady progress"
        case .down: return "Keep building each session"
        }
    }

    private var parentTimingTrendText: String {
        let values = Array(report.timingProgression.suffix(4))
        guard !values.isEmpty else { return "No timing data yet." }
        if values.count == 1 {
            return timingPhrase(values[0])
        }
        return "\(timingPhrase(values.first!)) → \(timingPhrase(values.last!))"
    }

    private func progressHighlightLabel(for score: Int) -> String {
        switch score {
        case 90...100: return "Excellent Progress"
        case 75...89: return "Strong Progress"
        case 60...74: return "Developing Progress"
        default: return "Building Progress"
        }
    }

    private func timingPhrase(_ value: Double) -> String {
        if value >= 0 {
            return String(format: "Early by %.2fs", value)
        }
        return String(format: "Late by %.2fs", abs(value))
    }

    private func shareAsImage(_ format: WeeklyShareFormat) {
        #if canImport(UIKit)
        if let image = WeeklyReportShareExporter.exportImage(report: report, format: format) {
            // Optional default caption for social posts.
            UIPasteboard.general.string = "Improving my decision timing ⚽️"
            shareItems = [image]
            showShare = true
            return
        }
        #endif
        shareItems = [report.exportPlainTextSummary]
        showShare = true
    }
}

private enum WeeklyShareFormat {
    case square
    case story

    var size: CGSize {
        switch self {
        case .square: return CGSize(width: 1080, height: 1080)
        case .story: return CGSize(width: 1080, height: 1920)
        }
    }
}

private struct WeeklyReportShareCardView: View {
    let report: WeeklyReport
    let format: WeeklyShareFormat

    private let bgBase = Color(red: 11/255, green: 15/255, blue: 26/255) // #0B0F1A
    private let secondaryText = Color.gray.opacity(0.85)

    private var scoreText: String { "\(report.averageScore)" }
    private var scoreLabel: String {
        switch report.averageScore {
        case 90...100: return "Excellent Progress"
        case 75...89: return "Strong Progress"
        case 60...74: return "Developing Progress"
        default: return "Building Progress"
        }
    }
    private var scoreTrend: String {
        let values = Array(report.recentScores.suffix(4))
        guard !values.isEmpty else { return "No sessions yet" }
        return values.map(String.init).joined(separator: " → ")
    }
    private var nextFocusLine: String { "Decide before the ball reaches halfway" }
    private var levelText: String { report.level.rawValue }
    private var isLevelUpState: Bool { report.newBadge == .levelUp }
    private var shareBadge: PlayerBadge? { report.newBadge ?? report.primaryBadge }
    private var shareBadgeText: String? {
        guard let badge = shareBadge else { return nil }
        return "⚡ \(badge.title)"
    }
    private var accentColor: Color {
        switch report.scoreTrend {
        case .up: return Color(red: 34/255, green: 197/255, blue: 94/255) // #22C55E
        case .stable: return Color(red: 250/255, green: 204/255, blue: 21/255) // #FACC15
        case .down: return Color(red: 239/255, green: 68/255, blue: 68/255) // #EF4444
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [bgBase, bgBase.opacity(0.96), Color.black.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: format == .story ? 34 : 22) {
                VStack(spacing: 8) {
                    Text(report.playerName)
                        .font(.system(size: format == .story ? 48 : 42, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("Weekly Progress")
                        .font(.system(size: format == .story ? 34 : 28, weight: .semibold))
                        .foregroundColor(secondaryText)
                }

                VStack(spacing: 4) {
                    if isLevelUpState {
                        Text("LEVEL UP")
                            .font(.system(size: format == .story ? 26 : 20, weight: .black))
                            .foregroundColor(accentColor)
                            .tracking(1.4)
                        Text(levelText)
                            .font(.system(size: format == .story ? 126 : 94, weight: .black))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: accentColor.opacity(0.45), radius: format == .story ? 22 : 14, x: 0, y: 0)
                    } else {
                        Text("Level: \(levelText)")
                            .font(.system(size: format == .story ? 110 : 84, weight: .black))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: accentColor.opacity(0.45), radius: format == .story ? 22 : 14, x: 0, y: 0)
                    }
                }

                VStack(spacing: format == .story ? 18 : 12) {
                    shareLine(title: "Score", value: "\(scoreText) — \(scoreLabel)")
                    shareLine(title: "Score Trend", value: scoreTrend)
                    shareLine(title: "Insight", value: report.insight)
                    shareLine(title: "Next Focus", value: nextFocusLine)
                    if let badgeText = shareBadgeText {
                        shareLine(title: "Badge", value: badgeText)
                    }
                }

                Spacer(minLength: 0)

                Text("PBA Training")
                    .font(.system(size: format == .story ? 28 : 24, weight: .bold))
                    .foregroundColor(secondaryText)
            }
            .padding(.horizontal, format == .story ? 82 : 74)
            // Leave space for social overlays (username/stickers UI).
            .padding(.top, format == .story ? 190 : 80)
            .padding(.bottom, format == .story ? 170 : 70)
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private func shareLine(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: format == .story ? 20 : 16, weight: .bold))
                .foregroundColor(secondaryText)
                .tracking(1.2)
            Text(value)
                .font(.system(size: format == .story ? 32 : 26, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum WeeklyReportShareExporter {
    static func exportImage(report: WeeklyReport, format: WeeklyShareFormat) -> UIImage? {
        #if canImport(UIKit)
        let view = WeeklyReportShareCardView(report: report, format: format)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(format.size)
        return renderer.uiImage
        #else
        return nil
        #endif
    }
}

#Preview("Weekly report") {
    WeeklyReportView(
        report: generateWeeklyReport(
            sessions: [
                SessionResult(
                    date: Date(),
                    playerID: UUID(),
                    activityType: .awayFromPressure,
                    correctCount: 8,
                    totalReps: 10,
                    speedCounts: SessionSpeedCounts(fast: 4, medium: 4, slow: 2),
                    avgDecisionTime: 1.0
                )
            ],
            playerName: "Alex",
            adaptiveState: AdaptiveTrainingState(
                currentTempo: .gameSpeed,
                currentLevel: .advancing,
                recentScores: [74, 79, 82],
                recommendation: "Stay here and push for earlier decisions",
                focus: "commit earlier"
            ),
            unlockedBadges: [.earlyThinker, .onFire3, .aheadOfPlay],
            latestUnlockedBadge: .aheadOfPlay
        )
    )
}
