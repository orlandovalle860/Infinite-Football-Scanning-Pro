//
//  SessionSummaryView.swift
//  FootballScanningAI
//
//  PBA V2 — SCREEN 11 SESSION SUMMARY. Train Another → same activity. Back to Home → HomeDashboardView. Share Report → sheet.
//

import SwiftUI

private func activityDisplayName(_ kind: ActivityKind) -> String {
    switch kind {
    case .twoMinuteTest: return "2-Minute Test"
    case .awayFromPressure: return "Playing Away From Pressure"
    case .dribbleOrPass: return "Dribble or Pass"
    case .oneTouchPassing: return "One-Touch Passing"
    }
}

private func biasLabel(_ gate: Gate?) -> String {
    guard let g = gate else { return "none" }
    switch g {
    case .up: return "Up"
    case .down: return "Down"
    case .left: return "Left"
    case .right: return "Right"
    }
}

struct SessionSummaryView: View {
    let session: SessionResult
    let playerName: String
    /// When true, show "New Personal Best" badge (set when this session just beat the previous best).
    var isNewPersonalBest: Bool = false
    /// New personal bests from this block (decision speed, pressure escape, forward intent). When non-empty, show celebration banner.
    var newPersonalBests: [NewPersonalBest] = []
    /// When set (e.g. from block summary), "Back to Home" calls this to pop to Progress instead of one level.
    var onBackToHome: (() -> Void)? = nil
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var shareReportItems: [Any] = []
    @State private var navigateToTrainAnother = false

    private var activityName: String { activityDisplayName(session.activityType) }
    private var coachInsightText: String { CoachInsightGenerator.coachInsight(for: session) }

    /// Display-only Decision Speed Score (0–100) derived from session correctness and avg reaction time. No backend change.
    private var displayDecisionSpeedScore: Int? {
        guard session.totalReps > 0 else { return nil }
        let ms = Int((session.avgDecisionTime ?? 1.0) * 1000)
        let reactionTimesMs = [Int](repeating: ms, count: session.totalReps)
        let correct = (0..<session.correctCount).map { _ in true } + (0..<(session.totalReps - session.correctCount)).map { _ in false }
        return DecisionSpeedScore.sessionScore(reactionTimesMs: reactionTimesMs, correct: correct)
    }

    private var newPersonalBestBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Personal Best!")
                .font(.headline.weight(.semibold))
                .foregroundColor(.yellow)
            ForEach(Array(newPersonalBests.enumerated()), id: \.offset) { _, best in
                VStack(alignment: .leading, spacing: 2) {
                    Text(best.title)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.95))
                    Text(best.improvementText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var personalBest: ActivityBest? {
        profileManager.currentProfile?.personalBests[session.activityType]
            ?? profileManager.profiles.first(where: { $0.id == session.playerID })?.personalBests[session.activityType]
    }

    private var profiles: [UserProfile] { profileManager.profiles }

    var body: some View {
        if !profiles.contains(where: { $0.id == session.playerID }) {
            deletedPlayerPlaceholder
        } else {
            sessionSummaryContent
        }
    }

    private var deletedPlayerPlaceholder: some View {
        VStack(spacing: 16) {
            Text("Player no longer available.")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var sessionSummaryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                decisionSpeedHeroSection

                performanceStatSections

                if session.activityType == .awayFromPressure {
                    pressureEscapesCard
                }
                biasCard

                coachInsightCard

                buttonsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareReportItems)
        }
        .navigationDestination(isPresented: $navigateToTrainAnother) {
            trainAnotherDestination
        }
    }

    /// 1. Decision Speed Score as main visual: large score, then "New Personal Best" / percentile, then Next Target.
    private var decisionSpeedHeroSection: some View {
        VStack(spacing: 12) {
            Text("\(playerName) • \(activityName)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)

            if let score = displayDecisionSpeedScore {
                Text("\(score)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Decision Speed Score")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.8))

                if !newPersonalBests.isEmpty {
                    newPersonalBestBanner
                } else if isNewPersonalBest {
                    Text("New Personal Best")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.yellow)
                }

                Text("Next Target: \(score + 1)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.yellow.opacity(0.95))
            } else {
                Text("—")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Text("Decision Speed Score")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                if !newPersonalBests.isEmpty { newPersonalBestBanner }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// 2. Performance stats in clean sections: Average Reaction Time, Correct Decisions, First Touch Accuracy.
    private var performanceStatSections: some View {
        let prev = progressStore.previous(session.activityType, playerId: session.playerID)
        return VStack(spacing: 16) {
            statSection(
                label: "Average Reaction Time",
                value: session.avgDecisionTime.map { String(format: "%.2fs", $0) } ?? "—",
                improvement: reactionTimeImprovement(previous: prev)
            )
            statSection(
                label: "Correct Decisions",
                value: "\(session.correctCount) / \(session.totalReps)",
                improvement: correctDecisionsImprovement(previous: prev)
            )
            if session.firstTouchMatchCount != nil || session.firstTouchCounts != nil {
                let pct = session.totalReps > 0 ? Int(round(Double(session.firstTouchMatchCount ?? 0) / Double(session.totalReps) * 100)) : 0
                statSection(
                    label: "First Touch Accuracy",
                    value: "\(pct)%",
                    improvement: nil
                )
            }
        }
    }

    private func reactionTimeImprovement(previous: SessionRecord?) -> String? {
        guard let curr = session.avgDecisionTime, let prevSec = previous?.avgLatency else { return nil }
        let diff = prevSec - curr
        if diff > 0.01 { return "↓ \(String(format: "%.2f", diff))s faster" }
        if diff < -0.01 { return "↑ \(String(format: "%.2f", -diff))s slower" }
        return nil
    }

    private func correctDecisionsImprovement(previous: SessionRecord?) -> String? {
        guard let prev = previous else { return nil }
        let diff = session.correctCount - prev.correct
        if diff > 0 { return "+\(diff) since last session" }
        if diff < 0 { return "\(diff) since last session" }
        return nil
    }

    private func statSection(label: String, value: String, improvement: String?) -> some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.75))
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                if let improvement = improvement, !improvement.isEmpty {
                    Text(improvement)
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.95))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var correctCard: some View {
        card {
            VStack(spacing: 8) {
                Text("\(session.correctCount) / \(session.totalReps)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Correct Decisions")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Pressure Escapes: reps where the player successfully escaped (correct direction + exited that gate). AFP only.
    private var pressureEscapesCard: some View {
        card {
            VStack(spacing: 8) {
                Text("\(session.correctCount) / \(session.totalReps)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Pressure Escapes")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var personalBestCard: some View {
        card {
            VStack(spacing: 8) {
                Text("Personal Best")
                    .font(.headline)
                    .foregroundColor(.white)
                if let best = personalBest {
                    Text("\(best.bestCorrect) / \(best.bestTotal)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                } else {
                    Text("First session recorded")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var decisionSpeedCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Decision Speed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let avg = session.avgDecisionTime {
                    Text(String(format: "%.2fs", avg))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    if let band = DecisionSpeedBand.band(forSeconds: avg) {
                        Text(band.label)
                            .font(.caption.weight(.medium))
                            .foregroundColor(band.color)
                        Text(band.explanation)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                HStack(spacing: 12) {
                    pill("Fast", value: session.speedCounts.fast)
                    pill("Medium", value: session.speedCounts.medium)
                    pill("Slow", value: session.speedCounts.slow)
                }
                Text("Goal: more Fast, fewer Slow")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func pill(_ label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12))
        .cornerRadius(20)
    }

    private var biasCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                if let bias = session.biasDirection {
                    Text("Bias: favors \(biasLabel(bias))")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text("Scan the whole field before receiving.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text("Good: using the whole field.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }

    private var firstTouchCard: some View {
        Group {
            if session.firstTouchCounts != nil || session.firstTouchMatchCount != nil || session.lateAdjustments != nil {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        if session.firstTouchMatchCount != nil || session.firstTouchCounts != nil {
                            Text("First Touch Accuracy: \(session.firstTouchMatchCount ?? 0) / \(session.totalReps)")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        if let late = session.lateAdjustments {
                            Text("Late Adjustments: \(late)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
            }
        }
    }

    /// Coach Feedback: highlighted card so it stands apart from stats.
    private var coachInsightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach Feedback")
                .font(.headline.weight(.semibold))
                .foregroundColor(.yellow)
            Text(coachInsightText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1.5)
        )
        .cornerRadius(14)
    }

    private var buttonsSection: some View {
        VStack(spacing: 12) {
            Button {
                navigateToTrainAnother = true
            } label: {
                Text("Train Another Block")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                router.popToRoot()
            } label: {
                Text("Back to Home")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                var items: [Any] = []
                if let image = SessionReportExporter.exportImage(session: session, playerName: playerName) {
                    items.append(image)
                }
                if let pdfURL = SessionReportExporter.exportPDF(session: session, playerName: playerName) {
                    items.append(pdfURL)
                }
                if items.isEmpty {
                    items.append(shareText)
                }
                shareReportItems = items
                showShare = !items.isEmpty
            } label: {
                Text("Share Report")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 8)
    }

    private var shareText: String {
        var lines: [String] = [
            "\(playerName) — Session Summary",
            activityName,
            "Correct: \(session.correctCount)/\(session.totalReps)",
            "Speed: Fast \(session.speedCounts.fast) / Med \(session.speedCounts.medium) / Slow \(session.speedCounts.slow)",
            "Bias: \(session.biasDirection != nil ? biasLabel(session.biasDirection) : "none")",
            "Coach Insight: \(coachInsightText)"
        ]
        if let avg = session.avgDecisionTime {
            lines.insert("Avg decision time: \(String(format: "%.2f", avg))s", at: 4)
        }
        if session.firstTouchMatchCount != nil || session.firstTouchCounts != nil {
            lines.insert("First Touch Accuracy: \(session.firstTouchMatchCount ?? 0)/\(session.totalReps)", at: lines.count - 1)
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var trainAnotherDestination: some View {
        switch session.activityType {
        case .twoMinuteTest:
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .awayFromPressure:
            AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: session.difficulty ?? .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .dribbleOrPass:
            DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: session.difficulty ?? .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .oneTouchPassing:
            OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: session.difficulty ?? .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        SessionSummaryView(
            session: SessionResult(
                playerID: UUID(),
                activityType: .awayFromPressure,
                correctCount: 9,
                totalReps: 12,
                speedCounts: SessionSpeedCounts(fast: 4, medium: 5, slow: 3),
                avgDecisionTime: 1.4,
                biasDirection: .left,
                directionCounts: [.left: 5, .right: 3, .up: 2, .down: 2],
                difficulty: .standard
            ),
            playerName: "Orlando",
            profileManager: UserProfileManager(),
            settingsViewModel: SettingsViewModel()
        )
        .environmentObject(ProgressStore())
        .environmentObject(PlayerStore())
        .environmentObject(PopToRootTrigger())
        .environmentObject(AppRouter())
    }
}
