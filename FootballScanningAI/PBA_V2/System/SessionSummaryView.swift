//
//  SessionSummaryView.swift
//  FootballScanningAI
//
//  PBA V2 — SCREEN 11 SESSION SUMMARY. Train Another → same activity. Back to Home → HomeDashboardView. Share Report → sheet.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    /// New personal bests from this block (decision speed, away-from-pressure accuracy, forward intent). When non-empty, show celebration banner.
    var newPersonalBests: [NewPersonalBest] = []
    /// XP earned from this completed session.
    var xpEarned: Int = 0
    /// Newly unlocked badges from this completed session.
    var newlyUnlockedBadges: [PlayerBadge] = []
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
    @State private var navigateToProgress = false
    @State private var animatedXPEarned: Int = 0
    @State private var showBadgeUnlockAnimation = false

    private var activityName: String { activityDisplayName(session.activityType) }
    private var avgReactionTimeSecondsDisplay: String {
        String(format: "%.2fs", session.avgDecisionTime ?? 0)
    }
    private var accuracyPercentValue: Int {
        guard session.totalReps > 0 else { return 0 }
        return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100.0))
    }
    private var accuracyDisplayText: String {
        "\(session.correctCount)/\(session.totalReps) (\(accuracyPercentValue)%)"
    }
    private var forwardThinkingStats: (choices: Int, opportunities: Int, percent: Int)? {
        guard let opp = session.forwardOpportunityCount, opp > 0,
              let choice = session.forwardChoiceCount else { return nil }
        let pct = Int(round(Double(choice) / Double(opp) * 100.0))
        return (choice, opp, pct)
    }
    private var primaryMetricLabel: String {
        switch session.activityType {
        case .awayFromPressure: return "Correct first decisions"
        case .dribbleOrPass: return "Decision correctness"
        case .oneTouchPassing: return "Decision window"
        case .twoMinuteTest: return "Balanced score"
        }
    }
    private var primaryMetricValue: String {
        switch session.activityType {
        case .awayFromPressure, .dribbleOrPass:
            return accuracyDisplayText
        case .oneTouchPassing:
            return session.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—"
        case .twoMinuteTest:
            let window = session.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—"
            return "\(accuracyPercentValue)% · \(window)"
        }
    }
    private var progressionMessage: String? {
        let progress = GuidedCurriculumEngine.currentProgress(playerId: session.playerID)
        let accuracy = Double(accuracyPercentValue)
        let avg = session.avgDecisionTime ?? 9
        let forwardPct = forwardThinkingStats?.percent
        switch progress.stage {
        case 1:
            if accuracy >= 65, avg <= 1.35 { return "You're close to Stage 2." }
        case 2:
            if accuracy >= 65, avg <= 1.20, (forwardPct ?? 0) >= 35 { return "You're close to Stage 3." }
        default:
            if accuracy >= 70, avg <= 1.05 { return "You're close to the next loop." }
        }
        return nil
    }

    /// Display-only Decision Speed Score (0–100); same formula as stored session score.
    private var displayDecisionSpeedScore: Int? { session.estimatedDecisionSpeedScore }

    /// Compact celebration above the narrative (badges + PB); avoids duplicating full banners inside hero.
    private var sessionCelebrationStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !newPersonalBests.isEmpty {
                newPersonalBestBanner
            } else if isNewPersonalBest {
                Text("New Personal Best")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(12)
            }
            if !newlyUnlockedBadges.isEmpty {
                badgesUnlockedBanner
            }
        }
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
        .opacity(showBadgeUnlockAnimation ? 1 : 0)
        .scaleEffect(showBadgeUnlockAnimation ? 1.0 : 0.94)
    }

    private var badgesUnlockedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badge Unlocked!")
                .font(.headline.weight(.semibold))
                .foregroundColor(.yellow)
            ForEach(newlyUnlockedBadges, id: \.rawValue) { badge in
                Text("• \(badge.title)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.08))
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

    /// Session before this one (same activity + player) for trend lines; nil if first session.
    private var previousSessionRecord: SessionRecord? {
        progressStore.previous(session.activityType, playerId: session.playerID)
    }

    private var postSessionNarrative: PBAPostSessionNarrative {
        PBAPostSessionNarrativeBuilder.fromSessionResult(
            session,
            previousSession: previousSessionRecord,
            progressStore: progressStore
        )
    }

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
                if !newPersonalBests.isEmpty || isNewPersonalBest || !newlyUnlockedBadges.isEmpty {
                    sessionCelebrationStrip
                }

                PBAPostSessionNarrativeStack(narrative: postSessionNarrative)

                xpFeedbackCard

                yourNumbersSection

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
            runFeedbackAnimations()
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareReportItems)
        }
        .navigationDestination(isPresented: $navigateToTrainAnother) {
            trainAnotherDestination
        }
        .navigationDestination(isPresented: $navigateToProgress) {
            PBAProgressView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    /// E. Your numbers — reference metrics after the debrief (no tier labels that fight the headline).
    private var yourNumbersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your numbers")
                .font(.title3.weight(.bold))
                .foregroundColor(.white.opacity(0.95))
            Text("\(playerName) · \(activityName)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
            Text("Reference only — your coach debrief is above.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 12) {
                yourNumbersRow(label: primaryMetricLabel, value: primaryMetricValue)
                if session.activityType != .oneTouchPassing {
                    yourNumbersRow(label: "Decision window", value: session.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")
                }
                if session.activityType != .awayFromPressure && session.activityType != .dribbleOrPass {
                    yourNumbersRow(label: "Correct decisions", value: accuracyDisplayText)
                }
                yourNumbersRow(
                    label: "Tempo mix",
                    value: "Fast \(session.speedCounts.fast) · Med \(session.speedCounts.medium) · Slow \(session.speedCounts.slow)"
                )
                if let score = displayDecisionSpeedScore {
                    yourNumbersRow(label: "Decision Speed Score", value: "\(score)")
                }
                if let f = forwardThinkingStats {
                    yourNumbersRow(label: "Forward choices", value: "\(f.choices) / \(f.opportunities) (\(f.percent)%)")
                }
                if let bias = session.biasDirection {
                    yourNumbersRow(label: "Field bias", value: biasLabel(bias))
                } else {
                    yourNumbersRow(label: "Field bias", value: "Balanced")
                }
                if let best = personalBest {
                    yourNumbersRow(label: "Your best (this activity)", value: "\(best.bestCorrect) / \(best.bestTotal)")
                }
            }

            if let delta = yourNumbersDeltaCaption {
                Text(delta)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func yourNumbersRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.78))
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Short delta line for E (trend detail lives in the debrief stack).
    private var yourNumbersDeltaCaption: String? {
        guard let prev = previousSessionRecord else { return nil }
        var parts: [String] = []
        if let c = session.avgDecisionWindowSeconds, let p = prev.avgDecisionWindowSeconds {
            let diff = c - p
            if diff > 0.02 {
                parts.append(String(format: "Δ window: +%.2fs", diff))
            } else if diff < -0.02 {
                parts.append(String(format: "Δ window: %.2fs", diff))
            } else {
                parts.append("Δ window: flat")
            }
        }
        let dc = session.correctCount - prev.correct
        if dc > 0 {
            parts.append("Δ correct: +\(dc)")
        } else if dc < 0 {
            parts.append("Δ correct: \(dc)")
        } else {
            parts.append("Δ correct: same")
        }
        return parts.joined(separator: " · ")
    }

    /// 4) XP feedback + progression cue.
    private var xpFeedbackCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XP Feedback")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow)
            Text("+\(animatedXPEarned) XP this session")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.95))
            if let msg = progressionMessage {
                Text(msg)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    private var buttonsSection: some View {
        VStack(spacing: 12) {
            Button {
                navigateToTrainAnother = true
            } label: {
                Text("Train Again")
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
            "Coach insight: \(postSessionNarrative.coachInsight)"
        ]
        if let window = session.avgDecisionWindowSeconds {
            lines.insert("Decision window: \(DecisionTimingModel.summaryText(windowSeconds: window))", at: 4)
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
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .dribbleOrPass:
            DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .oneTouchPassing:
            OneTouchPassingRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
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

    private func runFeedbackAnimations() {
        animatedXPEarned = 0
        if xpEarned > 0 {
            Task { @MainActor in
                let steps = min(24, max(8, xpEarned / 8))
                for step in 1...steps {
                    let progress = Double(step) / Double(steps)
                    animatedXPEarned = Int((Double(xpEarned) * progress).rounded())
                    try? await Task.sleep(nanoseconds: 18_000_000)
                }
                animatedXPEarned = xpEarned
            }
        }

        showBadgeUnlockAnimation = false
        if !newlyUnlockedBadges.isEmpty {
            withAnimation(.easeOut(duration: 0.2).delay(0.06)) {
                showBadgeUnlockAnimation = true
            }
            triggerBadgeHaptic()
        }
    }

    private func triggerBadgeHaptic() {
#if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
#endif
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
