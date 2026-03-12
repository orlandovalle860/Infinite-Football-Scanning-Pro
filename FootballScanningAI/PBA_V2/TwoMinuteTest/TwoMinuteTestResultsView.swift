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
    /// Rep logs for saving individual decisions to Supabase; nil when shown without logs (e.g. preview).
    var repLogs: [RepLog]? = nil
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    /// When set (e.g. from fullScreenCover), "Back to Home" calls this then dismisses so the session can pop to root.
    var onDismissCover: (() -> Void)? = nil
    /// When set (e.g. from fullScreenCover), "Start Training" pushes the recommended activity's role selection onto the cover's path instead of using trainingTarget.
    var onStartTraining: ((ActivityKind) -> Void)? = nil
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var didSave = false
    @State private var trainingTarget: ActivityKind? = nil
    @State private var navigateToTestAgain = false
    @State private var navigateToAccountPrompt = false
    @State private var navigateToEmailAuth = false
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

    private static func formatDecisionTime(_ seconds: Double?) -> String {
        guard let s = seconds else { return "—" }
        return String(format: "%.2f seconds", s)
    }

    /// Onboarding: no profiles yet or first-time test not completed.
    private var isOnboarding: Bool {
        profileManager.profiles.isEmpty || !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isOnboarding {
                    onboardingResultSummary
                    onboardingAccountCTA
                }
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
        .navigationDestination(isPresented: $navigateToAccountPrompt) {
            AccountPromptView(
                profileManager: profileManager,
                playerStore: playerStore,
                twoMinuteTestResult: result,
                onContinueWithoutAccount: {
                    navigateToAccountPrompt = false
                    if !Config.isSupabaseConfigured {
                        navigateToCreateProfile = true
                    }
                },
                onAccountComplete: {
                    navigateToAccountPrompt = false
                    onDismissCover?()
                    router.popToRoot()
                }
            )
            .environmentObject(progressStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToEmailAuth) {
            EmailAuthView(
                profileManager: profileManager,
                playerStore: playerStore,
                twoMinuteTestResult: result,
                onComplete: {
                    navigateToEmailAuth = false
                    onDismissCover?()
                    router.popToRoot()
                }
            )
            .environmentObject(progressStore)
        }
        .navigationDestination(isPresented: Binding(
            get: { navigateToCreateProfile && !Config.isSupabaseConfigured },
            set: { navigateToCreateProfile = $0 }
        )) {
            CreatePlayerProfileAfterTestView(
                profileManager: profileManager,
                testResult: TestResultSummary(
                    decisionScore: min(100, result.correctCount * 10),
                    status: type.title,
                    consistency: "First test"
                ),
                twoMinuteTestResult: profileManager.profiles.isEmpty ? result : nil,
                onComplete: onDismissCover
            )
        }
        .navigationDestination(isPresented: $navigateToPlayerReport) {
            PlayerReportView(content: PlayerReportGenerator.report(from: result))
        }
    }

    /// Top-of-screen result for onboarding: decisions count, average speed, elite benchmark.
    private var onboardingResultSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You made \(result.totalReps) decisions in 2 minutes.")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text("Average decision speed: \(Self.formatDecisionTime(result.avgDecisionTime))")
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
            Text("Elite academy players average about 0.60 seconds.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
    }

    /// Onboarding CTA: Sign in with Apple or Continue with Email to save score and track improvement.
    private var onboardingAccountCTA: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save your score and track your improvement.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                Button {
                    if Config.isSupabaseConfigured {
                        navigateToAccountPrompt = true
                    } else {
                        navigateToCreateProfile = true
                    }
                } label: {
                    Text("Sign in with Apple")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    if Config.isSupabaseConfigured {
                        navigateToEmailAuth = true
                    } else {
                        navigateToCreateProfile = true
                    }
                } label: {
                    Text("Continue with Email")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
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
            // Primary account CTA is in onboardingAccountCTA when isOnboarding
            if !isOnboarding {
                if profileManager.profiles.isEmpty {
                    Button {
                        if Config.isSupabaseConfigured {
                            navigateToAccountPrompt = true
                        } else {
                            navigateToCreateProfile = true
                        }
                    } label: {
                        Text("Save your results and track your improvement.")
                            .font(.headline)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(14)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest") {
                    Button {
                        if Config.isSupabaseConfigured {
                            navigateToAccountPrompt = true
                        } else {
                            navigateToCreateProfile = true
                        }
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
            }

            Button {
                if let onStartTraining = onStartTraining {
                    onStartTraining(recommendation.activity)
                } else {
                    trainingTarget = recommendation.activity
                }
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
        if profileManager.profiles.isEmpty {
            return
        }
        let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId
        let speedBucket: SpeedBucket = {
            let (f, m, s) = (result.fastCount, result.mediumCount, result.slowCount)
            if f >= m && f >= s { return .fast }
            if s >= f && s >= m { return .slow }
            return .medium
        }()
        let biasString = result.biasDirection?.userFacingName ?? "Balanced"
        guard let sessionId = CurrentSessionStore.shared.sessionId else {
            let record = SessionRecord(
                id: UUID(),
                date: Date(),
                activity: .twoMinuteTest,
                gridSize: .fiveByFive,
                difficulty: result.difficulty,
                reps: result.totalReps,
                decisionsCompleted: result.totalReps,
                correct: result.correctCount,
                forwardCorrect: nil,
                speedBucket: speedBucket,
                bias: biasString,
                avgLatency: result.avgDecisionTime,
                profile: nil,
                playerId: playerId
            )
            progressStore.add(record)
            return
        }
        let record = SessionRecord(
            id: sessionId,
            date: Date(),
            activity: .twoMinuteTest,
            gridSize: .fiveByFive,
            difficulty: result.difficulty,
            reps: result.totalReps,
            decisionsCompleted: result.totalReps,
            correct: result.correctCount,
            forwardCorrect: nil,
            speedBucket: speedBucket,
            bias: biasString,
            avgLatency: result.avgDecisionTime,
            profile: nil,
            playerId: playerId
        )
        progressStore.add(record)
        SupabaseSessionService.shared.saveSession(record: record, decisions: []) {
            progressStore.markSynced(id: record.id)
        }
        if let logs = repLogs {
            let pid = record.playerId ?? playerId
            let activityName = record.activity.rawValue
            for log in logs {
                guard let sec = log.passTriggeredAt.map({ log.exitLoggedAt.timeIntervalSince($0) }) else { continue }
                let reactionTimeMs = Int(sec * 1000)
                if reactionTimeMs > SupabaseDecisionService.maxReactionTimeMs { continue }
                let decision = Decision(
                    sessionId: sessionId,
                    playerId: pid,
                    activityName: activityName,
                    stimulusType: "ball",
                    decisionDirection: log.exitedGate.rawValue,
                    reactionTimeMs: reactionTimeMs,
                    correct: log.correct,
                    createdAt: log.exitLoggedAt
                )
                SupabaseDecisionService.shared.saveDecision(decision)
            }
        }
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
