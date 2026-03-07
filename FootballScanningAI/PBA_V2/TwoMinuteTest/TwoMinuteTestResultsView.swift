//
//  TwoMinuteTestResultsView.swift
//  FootballScanningAI
//
//  PBA V2 — Unique result screen: Player Type, metrics, coach insight, recommended next, Start Training CTA.
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

struct TwoMinuteTestResultsView: View {
    let result: TwoMinuteTestResult
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    /// When set (e.g. from fullScreenCover), "Back to Home" calls this then dismisses so the session can pop to root.
    var onDismissCover: (() -> Void)? = nil
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var didSave = false
    @State private var trainingTarget: ActivityKind? = nil
    @State private var navigateToTestAgain = false
    @State private var navigateToCreateProfile = false
    @State private var navigateToPlayerReport = false

    private var type: PlayerType {
        TwoMinutePlayerType.determinePlayerType(
            correct: result.correctCount,
            total: result.totalReps,
            fast: result.fastCount,
            medium: result.mediumCount,
            slow: result.slowCount
        )
    }
    private var bias: Gate? { result.biasDirection }
    private var insight: String {
        TwoMinuteCoachInsight.coachInsight(
            type: type,
            correct: result.correctCount,
            total: result.totalReps,
            fast: result.fastCount,
            medium: result.mediumCount,
            slow: result.slowCount,
            bias: bias
        )
    }
    private var recommendation: (activity: ActivityKind, focus: String) {
        TwoMinuteRecommendedNext.recommendedNext(
            for: type,
            slow: result.slowCount,
            correct: result.correctCount,
            total: result.totalReps,
            bias: bias
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleSection
                metricsCard
                coachInsightCard
                recommendedNextCard
                buttonsSection
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onDismissCover?()
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear {
            saveProgressIfNeeded()
        }
        .navigationDestination(item: $trainingTarget) { activity in
            roleSelectionView(for: activity)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToTestAgain) {
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToCreateProfile) {
            CreatePlayerProfileAfterTestView(
                profileManager: profileManager,
                testResult: TestResultSummary(
                    decisionScore: min(100, result.correctCount * 10),
                    status: type.title,
                    consistency: "First test"
                ),
                onComplete: onDismissCover
            )
        }
        .navigationDestination(isPresented: $navigateToPlayerReport) {
            PlayerReportView(content: PlayerReportGenerator.report(from: result))
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Result")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Text(type.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(type.tagline)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private var metricsCard: some View {
        sectionCard(title: "Metrics") {
            VStack(alignment: .leading, spacing: 12) {
                row("Correct", "\(result.correctCount) / \(result.totalReps)")
                row("Decision Speed", "Fast \(result.fastCount) • Med \(result.mediumCount) • Slow \(result.slowCount)")
                row("Bias", bias?.userFacingName ?? "None")
            }
        }
    }

    private var coachInsightCard: some View {
        sectionCard(title: "Coach Insight") {
            Text(insight)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recommendedNextCard: some View {
        sectionCard(title: "Recommended Next") {
            VStack(alignment: .leading, spacing: 6) {
                Text(activityDisplayName(recommendation.activity))
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Focus: \(recommendation.focus)")
                    .font(.subheadline)
                    .foregroundColor(.yellow.opacity(0.95))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttonsSection: some View {
        VStack(spacing: 12) {
            if !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest") {
                Button {
                    navigateToCreateProfile = true
                } label: {
                    Text("Continue to Home")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button {
                if !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest") {
                    navigateToCreateProfile = true
                    return
                }
                trainingTarget = recommendation.activity
            } label: {
                Text("Start Training")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToTestAgain = true
            } label: {
                Text("Run Test Again")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                navigateToPlayerReport = true
            } label: {
                Text("View Player Report")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                popToRootTrigger.request = true
                onDismissCover?()
                router.popToRoot()
            } label: {
                Text("Back to Home")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            content()
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

    @ViewBuilder
    private func roleSelectionView(for activity: ActivityKind) -> some View {
        switch activity {
        case .twoMinuteTest:
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .awayFromPressure:
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .dribbleOrPass:
            DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .oneTouchPassing:
            OneTouchPassingRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        }
    }

    private func saveProgressIfNeeded() {
        guard !didSave else { return }
        didSave = true
        let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId
        let speedBucket: SpeedBucket = {
            let (f, m, s) = (result.fastCount, result.mediumCount, result.slowCount)
            if f >= m && f >= s { return .fast }
            if s >= f && s >= m { return .slow }
            return .medium
        }()
        let biasString = result.biasDirection?.userFacingName ?? "Balanced"
        let record = SessionRecord(
            id: UUID(),
            date: Date(),
            activity: .twoMinuteTest,
            gridSize: .fiveByFive,
            difficulty: result.difficulty,
            reps: result.totalReps,
            correct: result.correctCount,
            forwardCorrect: nil,
            speedBucket: speedBucket,
            bias: biasString,
            avgLatency: result.avgDecisionTime,
            profile: nil,
            playerId: playerId
        )
        progressStore.add(record)
        if let pid = playerId {
            let sessionResult = SessionResult(
                playerID: pid,
                activityType: .twoMinuteTest,
                correctCount: result.correctCount,
                totalReps: result.totalReps,
                speedCounts: SessionSpeedCounts(fast: result.fastCount, medium: result.mediumCount, slow: result.slowCount),
                avgDecisionTime: result.avgDecisionTime,
                biasDirection: result.biasDirection,
                directionCounts: result.directionCounts,
                difficulty: result.difficulty,
                forwardChoiceCount: result.forwardChoiceCount,
                forwardOpportunityCount: result.forwardOpportunityCount
            )
            profileManager.addSessionResult(sessionResult)
        }
    }
}

#Preview {
    NavigationStack {
        TwoMinuteTestResultsView(
            result: TwoMinuteTestResult(
                correctCount: 8,
                totalReps: 10,
                fastCount: 3,
                mediumCount: 5,
                slowCount: 2,
                directionCounts: [.up: 2, .down: 2, .left: 2, .right: 4],
                biasDirection: .right,
                avgDecisionTime: 1.8,
                difficulty: .standard
            ),
            profileManager: UserProfileManager(),
            settingsViewModel: SettingsViewModel()
        )
        .environmentObject(ProgressStore())
        .environmentObject(PlayerStore())
        .environmentObject(PopToRootTrigger())
    }
}
