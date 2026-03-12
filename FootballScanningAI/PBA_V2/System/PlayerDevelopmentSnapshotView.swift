//
//  PlayerDevelopmentSnapshotView.swift
//  FootballScanningAI
//
//  PBA V2 — Simple summary of a player's decision-making development for coaches and parents.
//

import SwiftUI

/// One metric row: current value, improvement vs baseline, progress bar. Optional band label + explanation (e.g. Decision Speed).
struct SnapshotMetricRow: View {
    let label: String
    let currentDisplay: String
    let improvementText: String?
    let progress: Double
    let improved: Bool?
    var bandLabel: String? = nil
    var bandColor: Color? = nil
    var explanationText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(currentDisplay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            if let band = bandLabel, !band.isEmpty {
                Text(band)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(bandColor ?? .white.opacity(0.9))
            }
            if let exp = explanationText, !exp.isEmpty {
                Text(exp)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            if let text = improvementText, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundColor(improved == true ? .green : (improved == false ? .orange : .white.opacity(0.7)))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: max(0, geo.size.width * min(1, max(0, progress))), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

struct PlayerDevelopmentSnapshotView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    private var activeProfile: UserProfile? { profileManager.currentProfile }
    private var playerId: UUID? { activeProfile?.id }
    private var last5: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: playerId) }
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    private var lastAFPSessionResult: SessionResult? {
        profileManager.recentTrainSessions(limit: 20).first { $0.activityType == .awayFromPressure }
    }
    private var decisionConsistencyForRecommendation: DecisionConsistencyLabel? {
        DecisionConsistencyLabel.from(session: chartSessions.last)
    }

    private var trainingRecommendation: TrainingRecommendationResult {
        TrainingRecommendation.recommend(progressStore: progressStore, playerId: playerId, last5: last5, hasCompletedInitialTest: hasCompletedInitialTest, lastAFPSessionResult: lastAFPSessionResult, decisionConsistency: decisionConsistencyForRecommendation)
    }

    /// All session results oldest-first for chart/baseline logic.
    private var chartSessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
    }

    /// Sessions to compare against: previous calendar month, or older half of last 10 (min 1 session).
    private var baselineSessions: [SessionResult] {
        let calendar = Calendar.current
        let now = Date()
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? now
        let previousMonth = chartSessions.filter { $0.date >= startOfLastMonth && $0.date < startOfThisMonth }
        if !previousMonth.isEmpty {
            return previousMonth
        }
        let last10 = Array(chartSessions.suffix(10))
        if last10.count <= 1 { return [] }
        let olderHalfCount = max(1, last10.count / 2)
        return Array(last10.prefix(olderHalfCount))
    }

    // MARK: - Metric values

    /// Decision speed: lower is better. Current = personal best or latest; progress 0–1 (0.3s = 1, 2.0s = 0). Includes band for display.
    private var decisionSpeedMetric: (current: String, improvement: String?, progress: Double, improved: Bool?, bandLabel: String?, bandColor: Color?, explanationText: String?) {
        let current: Double?
        if let best = profileManager.fastestDecisionSpeedSeconds() {
            current = best
        } else {
            current = chartSessions.last(where: { $0.avgDecisionTime != nil })?.avgDecisionTime
        }
        guard let cur = current else {
            return ("—", nil, 0, nil, nil, nil, nil)
        }
        let baselineValues = baselineSessions.compactMap { $0.avgDecisionTime }
        let previous = baselineValues.isEmpty ? nil : baselineValues.reduce(0, +) / Double(baselineValues.count)
        let improvement: String?
        let improved: Bool?
        if let prev = previous {
            let diff = prev - cur
            improved = diff != 0 ? (diff > 0) : nil
            improvement = String(format: "%.2fs → %.2fs", prev, cur) + (diff > 0 ? " (faster)" : (diff < 0 ? " (slower)" : ""))
        } else {
            improved = nil
            improvement = nil
        }
        let progress = (2.0 - cur) / 1.7
        let band = DecisionSpeedBand.band(forSeconds: cur)
        return (
            String(format: "%.2fs", cur),
            improvement,
            min(1, max(0, progress)),
            improved,
            band?.label,
            band?.color,
            band?.explanation
        )
    }

    /// Pressure escape: AFP correct %. Higher is better.
    private var pressureEscapeMetric: (current: String, improvement: String?, progress: Double, improved: Bool?) {
        let afpSessions = chartSessions.filter { $0.activityType == .awayFromPressure }
        let current: Double?
        if let best = profileManager.bestPressureEscapePercent() {
            current = best
        } else if let last = afpSessions.last, last.totalReps > 0 {
            current = Double(last.correctCount) / Double(last.totalReps) * 100
        } else {
            current = nil
        }
        guard let cur = current else {
            return ("—", nil, 0, nil)
        }
        let baselineAFP = baselineSessions.filter { $0.activityType == .awayFromPressure }
        let baselinePcts = baselineAFP.compactMap { s -> Double? in
            guard s.totalReps > 0 else { return nil }
            return Double(s.correctCount) / Double(s.totalReps) * 100
        }
        let previous = baselinePcts.isEmpty ? nil : baselinePcts.reduce(0, +) / Double(baselinePcts.count)
        var improvement: String?
        var improved: Bool?
        if let prev = previous {
            improved = cur != prev ? (cur > prev) : nil
            improvement = String(format: "%.0f%% → %.0f%%", prev, cur)
        }
        return (String(format: "%.0f%%", cur), improvement, min(1, cur / 100), improved)
    }

    /// First touch commitment: % where first touch matched correct direction (AFP). Higher is better.
    private var firstTouchCommitmentMetric: (current: String, improvement: String?, progress: Double, improved: Bool?) {
        let withFirstTouch = chartSessions.filter { $0.firstTouchMatchCount != nil && $0.totalReps > 0 }
        let current: Double?
        if let last = withFirstTouch.last, let m = last.firstTouchMatchCount {
            current = Double(m) / Double(last.totalReps) * 100
        } else if withFirstTouch.count >= 2 {
            let recent = Array(withFirstTouch.suffix(3))
            let sum = recent.reduce(0.0) { acc, s in
                guard let m = s.firstTouchMatchCount else { return acc }
                return acc + Double(m) / Double(s.totalReps) * 100
            }
            current = sum / Double(recent.count)
        } else {
            current = nil
        }
        guard let cur = current else {
            return ("—", nil, 0, nil)
        }
        let baselineWithFT = baselineSessions.filter { $0.firstTouchMatchCount != nil && $0.totalReps > 0 }
        let baselinePcts = baselineWithFT.map { Double($0.firstTouchMatchCount!) / Double($0.totalReps) * 100 }
        let previous = baselinePcts.isEmpty ? nil : baselinePcts.reduce(0, +) / Double(baselinePcts.count)
        var improvement: String?
        var improved: Bool?
        if let prev = previous {
            improved = cur != prev ? (cur > prev) : nil
            improvement = String(format: "%.0f%% → %.0f%%", prev, cur)
        }
        return (String(format: "%.0f%%", cur), improvement, min(1, cur / 100), improved)
    }

    /// Forward intent: DOP forward choice %. Higher is better.
    private var forwardIntentMetric: (current: String, improvement: String?, progress: Double, improved: Bool?) {
        let dopSessions = chartSessions.filter { $0.activityType == .dribbleOrPass }
        let current: Double?
        if let best = profileManager.bestForwardIntentPercent() {
            current = best
        } else if let last = dopSessions.last(where: { $0.forwardOpportunityCount != nil && ($0.forwardOpportunityCount ?? 0) > 0 }),
                  let opp = last.forwardOpportunityCount, let choice = last.forwardChoiceCount {
            current = Double(choice) / Double(opp) * 100
        } else {
            current = nil
        }
        guard let cur = current else {
            return ("—", nil, 0, nil)
        }
        let baselineDOP = baselineSessions.filter { $0.activityType == .dribbleOrPass }
        let baselinePcts = baselineDOP.compactMap { s -> Double? in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            return Double(choice) / Double(opp) * 100
        }
        let previous = baselinePcts.isEmpty ? nil : baselinePcts.reduce(0, +) / Double(baselinePcts.count)
        var improvement: String?
        var improved: Bool?
        if let prev = previous {
            improved = cur != prev ? (cur > prev) : nil
            improvement = String(format: "%.0f%% → %.0f%%", prev, cur)
        }
        return (String(format: "%.0f%%", cur), improvement, min(1, cur / 100), improved)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricsCard
                recommendedFocusCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activeProfile?.name ?? "Player")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Player Development Snapshot")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Core metrics")
                .font(.headline)
                .foregroundColor(.white)
            if chartSessions.isEmpty {
                Text("Complete training sessions to see your development metrics.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 12)
            } else {
                SnapshotMetricRow(
                    label: "Decision Speed",
                    currentDisplay: decisionSpeedMetric.current,
                    improvementText: decisionSpeedMetric.improvement,
                    progress: decisionSpeedMetric.progress,
                    improved: decisionSpeedMetric.improved,
                    bandLabel: decisionSpeedMetric.bandLabel,
                    bandColor: decisionSpeedMetric.bandColor,
                    explanationText: decisionSpeedMetric.explanationText
                )
                SnapshotMetricRow(
                    label: "Pressure Escape Rate",
                    currentDisplay: pressureEscapeMetric.current,
                    improvementText: pressureEscapeMetric.improvement,
                    progress: pressureEscapeMetric.progress,
                    improved: pressureEscapeMetric.improved
                )
                SnapshotMetricRow(
                    label: "First Touch Commitment",
                    currentDisplay: firstTouchCommitmentMetric.current,
                    improvementText: firstTouchCommitmentMetric.improvement,
                    progress: firstTouchCommitmentMetric.progress,
                    improved: firstTouchCommitmentMetric.improved
                )
                SnapshotMetricRow(
                    label: "Forward Intent",
                    currentDisplay: forwardIntentMetric.current,
                    improvementText: forwardIntentMetric.improvement,
                    progress: forwardIntentMetric.progress,
                    improved: forwardIntentMetric.improved
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var recommendedFocusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recommended Focus")
                .font(.headline)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 8) {
                Text(RecommendationEngine.activityTitle(trainingRecommendation.activity))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)
                if !trainingRecommendation.coachTip.isEmpty {
                    Text("Reason:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Text(trainingRecommendation.coachTip)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        PlayerDevelopmentSnapshotView(profileManager: UserProfileManager(), settingsViewModel: SettingsViewModel())
            .environmentObject(ProgressStore())
            .environmentObject(PlayerStore())
            .environmentObject(PopToRootTrigger())
            .environmentObject(AppRouter())
    }
}
