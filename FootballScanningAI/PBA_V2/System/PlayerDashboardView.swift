//
//  PlayerDashboardView.swift
//  FootballScanningAI
//
//  PBA V2 — Player development summary: snapshot, progress graphs, training recommendation.
//

import SwiftUI

/// Trend status for dashboard: derived from recent vs older session metrics.
enum DevelopmentStatus: String {
    case improving = "Improving"
    case stable = "Stable"
    case declining = "Declining"
}

struct PlayerDashboardView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var navigateToFullProgress = false
    @State private var navigateToTrain = false
    @State private var navigateToReportCard = false
    @State private var navigateToDevelopmentSnapshot = false
    @State private var metricInfoToShow: (title: String, message: String)?

    private var activeProfile: UserProfile? { profileManager.currentProfile }
    private var playerId: UUID? { activeProfile?.id }
    private var last5: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: playerId) }
    private var recentSessions: [SessionResult] { profileManager.recentTrainSessions(limit: 5) }
    private var speedCounts: (fast: Int, medium: Int, slow: Int) { UserProfileManager.speedCounts(from: recentSessions) }
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    private var lastAFPSessionResult: SessionResult? {
        profileManager.recentTrainSessions(limit: 20).first { $0.activityType == .awayFromPressure }
    }
    private var trainingRecommendation: TrainingRecommendationResult {
        TrainingRecommendation.recommend(progressStore: progressStore, playerId: playerId, last5: last5, hasCompletedInitialTest: hasCompletedInitialTest, lastAFPSessionResult: lastAFPSessionResult, decisionConsistency: decisionConsistencyCurrent)
    }

    private var chartSessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
    }

    // Snapshot metrics (current)
    private var scanEfficiencyCurrent: Int? {
        guard let s = chartSessions.last else { return nil }
        return Int(round(ScanEfficiency.score(from: s)))
    }

    /// Decision speed in seconds for headline display (latest session or personal best).
    private var decisionSpeedSeconds: Double? {
        chartSessions.last(where: { $0.avgDecisionTime != nil })?.avgDecisionTime
            ?? profileManager.fastestDecisionSpeedSeconds()
    }

    private var decisionSpeedLabel: String {
        let (f, m, s) = speedCounts
        let total = f + m + s
        guard total > 0 else { return "—" }
        if f >= m && f >= s { return "Fast" }
        if s >= f && s >= m { return "Slow" }
        return "Medium"
    }

    private var firstTouchCommitmentCurrent: Int? {
        guard let s = chartSessions.last, let match = s.firstTouchMatchCount, s.totalReps > 0 else { return nil }
        return Int(round(Double(match) / Double(s.totalReps) * 100.0))
    }

    /// Correction Rate: % of reps where first touch direction differed from final exit direction. Lower = stronger commitment.
    private var correctionRateCurrent: Int? {
        guard let s = chartSessions.last, let match = s.firstTouchMatchCount, s.totalReps > 0 else { return nil }
        let correctionCount = s.totalReps - match
        return Int(round(Double(correctionCount) / Double(s.totalReps) * 100.0))
    }

    private var forwardIntentCurrent: Int? {
        guard let s = chartSessions.last, let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
        return Int(round(Double(choice) / Double(opp) * 100.0))
    }

    /// Decision Before Contact: % of reps where decisionTime < threshold and firstTouch == correct (from most recent session with data).
    private var decisionBeforeContactCurrent: Int? {
        guard let s = chartSessions.last, let count = s.preReceiveDecisionCount, s.totalReps > 0 else { return nil }
        return Int(round(Double(count) / Double(s.totalReps) * 100.0))
    }

    /// Improving / Stable / Declining from Scan Efficiency trend (recent vs older sessions).
    private var developmentStatus: DevelopmentStatus {
        let sessions = chartSessions
        guard sessions.count >= 2 else { return .stable }
        let scores = sessions.map { ScanEfficiency.score(from: $0) }
        let half = scores.count / 2
        let recent = Array(scores.suffix(half))
        let older = Array(scores.prefix(scores.count - half))
        guard !recent.isEmpty, !older.isEmpty else { return .stable }
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        let diff = recentAvg - olderAvg
        if diff >= 3 { return .improving }
        if diff <= -3 { return .declining }
        return .stable
    }

    // Chart data
    private var decisionScorePoints: [ChartDataPoint] {
        chartSessions.enumerated().map { index, s in
            let value: Double
            if let score = s.decisionTotalScore, s.totalReps > 0 {
                value = (score / 60.0) * 100.0
            } else if s.totalReps > 0 {
                value = Double(s.correctCount) / Double(s.totalReps) * 100.0
            } else {
                value = 0
            }
            return ChartDataPoint(sessionIndex: index + 1, value: value)
        }
    }

    private var decisionSpeedPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let t = s.avgDecisionTime else { return nil }
            return ChartDataPoint(sessionIndex: index + 1, value: t)
        }
    }

    private var firstTouchCommitmentPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let match = s.firstTouchMatchCount, s.totalReps > 0 else { return nil }
            let pct = Double(match) / Double(s.totalReps) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }

    private var forwardIntentPoints: [ChartDataPoint] {
        chartSessions.enumerated().compactMap { index, s in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            let pct = Double(choice) / Double(opp) * 100.0
            return ChartDataPoint(sessionIndex: index + 1, value: pct)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                decisionMapCard
                playerSnapshotCard
                progressGraphsSection
                trainingRecommendationCard
                actionsSection
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
        .alert(metricInfoToShow?.title ?? "", isPresented: Binding(
            get: { metricInfoToShow != nil },
            set: { if !$0 { metricInfoToShow = nil } }
        )) {
            Button("OK", role: .cancel) { metricInfoToShow = nil }
        } message: {
            if let msg = metricInfoToShow?.message {
                Text(msg)
            }
        }
        .navigationDestination(isPresented: $navigateToFullProgress) {
            PlayerProgressView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToTrain) {
            trainDestination
        }
        .navigationDestination(isPresented: $navigateToReportCard) {
            PlayerReportCardView(data: ReportCardGenerator.reportCard(
                chartSessions: chartSessions,
                last5: last5,
                trainingRecommendation: trainingRecommendation
            ))
        }
        .navigationDestination(isPresented: $navigateToDevelopmentSnapshot) {
            PlayerDevelopmentSnapshotView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activeProfile?.name ?? "Player")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Player Dashboard")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private var decisionMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Decision Map")
                .font(.headline)
                .foregroundColor(.white)
            if let speed = decisionSpeedSeconds, let commitment = firstTouchCommitmentCurrent {
                DecisionMapView(
                    decisionSpeedSeconds: speed,
                    firstTouchCommitmentPercent: Double(commitment)
                )
                .frame(height: 220)
            } else {
                Text("Complete sessions with decision speed and first touch data to see your position.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
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

    private var playerSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Player Snapshot")
                .font(.headline)
                .foregroundColor(.white)
            if chartSessions.isEmpty {
                Text("Complete training sessions to see your snapshot.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                decisionSpeedHeadline
                firstTouchCommitmentHeadline
                snapshotRow("Scan Efficiency", value: scanEfficiencyCurrent.map { "\($0)" } ?? "—", suffix: nil)
                snapshotRow("Decision Before Contact", value: decisionBeforeContactCurrent.map { "\($0)%" } ?? "—", suffix: nil)
                snapshotRow("Forward Intent", value: forwardIntentCurrent.map { "\($0)%" } ?? "—", suffix: nil)
                correctionRateRow
                snapshotRowWithInfo("Status", value: developmentStatus.rawValue, valueColor: statusColor(developmentStatus))
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

    private var decisionSpeedHeadline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Decision Speed")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            if let sec = decisionSpeedSeconds {
                Text(String(format: "%.2fs", sec))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let band = DecisionSpeedBand.band(forSeconds: sec) {
                    Text(band.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(band.color)
                }
            } else {
                Text(decisionSpeedLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            if let consistency = decisionConsistencyCurrent {
                Text("Consistency")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.75))
                Text(consistency.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .padding(.vertical, 4)
    }

    /// Decision Consistency: within-session stability of decision speed (from latest session with data).
    private var decisionConsistencyCurrent: DecisionConsistencyLabel? {
        DecisionConsistencyLabel.from(session: chartSessions.last(where: { $0.avgDecisionTime != nil || $0.decisionTimeStdDev != nil }))
    }

    private var firstTouchCommitmentHeadline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("First Touch Commitment")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            if let pct = firstTouchCommitmentCurrent {
                Text("\(pct)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let band = FirstTouchCommitmentBand.band(forPercent: Double(pct)) {
                    Text(band.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(band.color)
                }
                Text("How often your first touch commits to the correct action.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 4)
    }

    private var correctionRateRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Correction Rate")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                if MetricExplanations.message(for: "Correction Rate") != nil {
                    Button {
                        metricInfoToShow = (title: "Correction Rate", message: MetricExplanations.message(for: "Correction Rate") ?? "")
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                Spacer()
                Text(correctionRateCurrent.map { "\($0)%" } ?? "—")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
            }
            Text("How often you adjust after your first touch.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 4)
    }

    private func snapshotRow(_ label: String, value: String, suffix: String?) -> some View {
        snapshotRowWithInfo(label, value: value, valueColor: .white, suffix: suffix)
    }

    private func snapshotRowWithInfo(_ label: String, value: String, valueColor: Color = .white, suffix: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            if let msg = MetricExplanations.message(for: label) {
                Button {
                    metricInfoToShow = (title: label, message: msg)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(valueColor)
            if let s = suffix {
                Text(s)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func statusColor(_ status: DevelopmentStatus) -> Color {
        switch status {
        case .improving: return .green
        case .stable: return .white.opacity(0.9)
        case .declining: return .orange
        }
    }

    private var progressGraphsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress Over Time")
                .font(.headline)
                .foregroundColor(.white)
            if chartSessions.count < 2 {
                Text("Complete at least 2 training sessions to see progress graphs.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 12)
            } else {
                ProgressLineChartView(title: "Decision Score", points: decisionScorePoints, valueLabel: "%", yAxisRange: (0, 100))
                ProgressLineChartView(title: "Decision Speed", points: decisionSpeedPoints, valueLabel: "s", yAxisRange: nil, emptyStateMessage: "Complete at least 2 Dribble or Pass sessions to see your trend.")
                ProgressLineChartView(title: "First Touch Commitment", points: firstTouchCommitmentPoints, valueLabel: "%", yAxisRange: (0, 100), emptyStateMessage: "Complete at least 2 Playing Away From Pressure sessions to see your trend.")
                ProgressLineChartView(title: "Forward Intent", points: forwardIntentPoints, valueLabel: "%", yAxisRange: (0, 100), emptyStateMessage: "Complete at least 2 Dribble or Pass sessions to see your trend.")
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

    private var trainingRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Training Recommendation")
                .font(.headline)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Train:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(RecommendationEngine.activityTitle(trainingRecommendation.activity))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.yellow)
                }
                if !trainingRecommendation.coachTip.isEmpty {
                    Text("Reason:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Text(trainingRecommendation.coachTip)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Focus:")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text(trainingRecommendation.focusLine)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
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

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                navigateToTrain = true
            } label: {
                Text("Train Now")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToFullProgress = true
            } label: {
                Text("See Full Progress")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToReportCard = true
            } label: {
                Text("Report Card")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToDevelopmentSnapshot = true
            } label: {
                Text("Development Snapshot")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder
    private var trainDestination: some View {
        switch trainingRecommendation.activity {
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
}

// MARK: - Decision Map (two-axis: Decision Speed × First Touch Commitment)

private struct DecisionMapView: View {
    let decisionSpeedSeconds: Double
    let firstTouchCommitmentPercent: Double

    /// Speed axis: 0.3s = fast (right), 1.5s = slow (left). x = 0 left, 1 right.
    private static let speedMin = 0.3
    private static let speedMax = 1.5

    private var xNormalized: CGFloat {
        let clamped = min(Self.speedMax, max(Self.speedMin, decisionSpeedSeconds))
        return CGFloat((Self.speedMax - clamped) / (Self.speedMax - Self.speedMin))
    }

    private var yNormalized: CGFloat {
        CGFloat(min(1, max(0, firstTouchCommitmentPercent / 100.0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text("Slow")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("Decision Speed")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("Fast")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let pad: CGFloat = 28
                let plotW = w - pad * 2
                let plotH = h - pad * 2
                ZStack(alignment: .topLeading) {
                    // Plot area background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: plotW, height: plotH)
                        .offset(x: pad, y: pad)
                    // Vertical midline (fast/slow divide)
                    Path { p in
                        p.move(to: CGPoint(x: pad + plotW / 2, y: pad))
                        p.addLine(to: CGPoint(x: pad + plotW / 2, y: pad + plotH))
                    }
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    // Horizontal midline (commitment high/low divide)
                    Path { p in
                        p.move(to: CGPoint(x: pad, y: pad + plotH / 2))
                        p.addLine(to: CGPoint(x: pad + plotW, y: pad + plotH / 2))
                    }
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    // Quadrant labels
                    quadrantLabel("Developing", at: CGPoint(x: pad + plotW * 0.25, y: pad + plotH * 0.25))
                    quadrantLabel("Decisive but Slow", at: CGPoint(x: pad + plotW * 0.25, y: pad + plotH * 0.75))
                    quadrantLabel("Fast but Uncertain", at: CGPoint(x: pad + plotW * 0.75, y: pad + plotH * 0.25))
                    quadrantLabel("Elite Receiver", at: CGPoint(x: pad + plotW * 0.75, y: pad + plotH * 0.75))
                    // Player dot (x: 0 = left, 1 = right; y: 0 = bottom, 1 = top in data, but view y is top-down so 1-y)
                    let dotX = pad + xNormalized * plotW
                    let dotY = pad + (1 - yNormalized) * plotH
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(x: dotX, y: dotY)
                }
            }
            HStack(spacing: 0) {
                Text("Low")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("First Touch Commitment")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("High")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func quadrantLabel(_ text: String, at point: CGPoint) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .frame(width: 52)
            .position(point)
    }
}

#Preview {
    NavigationStack {
        PlayerDashboardView(profileManager: UserProfileManager(), settingsViewModel: SettingsViewModel())
            .environmentObject(ProgressStore())
            .environmentObject(PlayerStore())
            .environmentObject(PopToRootTrigger())
            .environmentObject(AppRouter())
    }
}
