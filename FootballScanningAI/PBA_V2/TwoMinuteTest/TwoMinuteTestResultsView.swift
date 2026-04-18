//
//  TwoMinuteTestResultsView.swift
//  FootballScanningAI
//
//  PBA V2 — Coaching-style 2-Minute Test results: identity, clarity, next action.
//

import SwiftUI

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
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController
    @Environment(\.dismiss) private var dismiss

    @State private var didSave = false
    @State private var trainingTarget: ActivityKind? = nil
    @State private var navigateToTestAgain = false
    @State private var navigateToAccountPrompt = false
    @State private var navigateToEmailAuth = false
    @State private var navigateToCreateProfile = false
    @State private var navigateToPlayerReport = false
    @State private var showQuickCalibration = false
    private let plannedTestReps: Int = 10
    private var loggedReps: Int { result.totalReps }

    /// Onboarding: no profiles yet or first-time test not completed.
    private var isOnboarding: Bool {
        profileManager.profiles.isEmpty || !UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey)
    }

    /// Behavior timing from per-rep logs (nil when preview / no logs).
    private var behaviorBadgeEvaluation: TwoMinuteBehaviorBadgeEvaluation? {
        guard let logs = repLogs, !logs.isEmpty else { return nil }
        return TwoMinuteBehaviorBadgeEvaluator.evaluate(logs: logs, difficulty: result.difficulty)
    }

    private var earlyCount: Int { behaviorBadgeEvaluation?.earlyCount ?? 0 }
    private var idealCount: Int { behaviorBadgeEvaluation?.idealCount ?? 0 }
    private var lateCount: Int { behaviorBadgeEvaluation?.lateCount ?? 0 }
    private var totalCount: Int { behaviorBadgeEvaluation?.total ?? 0 }
    private var shouldShowCalibrationSuggestion: Bool { !PartnerPassTempoCalibrationStore.hasSavedCalibration }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isOnboarding {
                    onboardingResultSummary
                    onboardingAccountCTA
                }

                // 1. Header
                headerSection

                // 2. Visual chart
                DecisionTimingDonutChart(
                    earlyCount: earlyCount,
                    idealCount: idealCount,
                    lateCount: lateCount,
                    totalCount: totalCount
                )
                .frame(maxWidth: .infinity)

                // 3. Breakdown
                breakdownSection

                // 4. Action buttons + existing nav
                actionButtonsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
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
            PBASessionFlowPolicy.handleResultsPresented()
            logResultsUIDebug()
            AuthFlowOnboardingSync.markLocalBaselineCompleted()
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
                    status: "Decision Timing Summary",
                    consistency: "First test"
                ),
                twoMinuteTestResult: profileManager.profiles.isEmpty ? result : nil,
                onComplete: onDismissCover
            )
        }
        .navigationDestination(isPresented: $navigateToPlayerReport) {
            PlayerReportView(content: PlayerReportGenerator.report(from: result))
        }
        .fullScreenCover(isPresented: $showQuickCalibration) {
            PassTempoCalibrationScreen { calibrated in
                CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(calibrated)
                if let calibrated {
                    PartnerPassTempoCalibrationStore.save(averageTravelTimeSeconds: calibrated)
                }
                showQuickCalibration = false
            }
            .interactiveDismissDisabled()
        }
    }

    private func logResultsUIDebug() {
        print("[ResultsUI-Debug] earlyCount=\(earlyCount) idealCount=\(idealCount) lateCount=\(lateCount) totalCount=\(totalCount)")
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Decision Timing Summary")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.95))
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Decisions")
                .font(.headline)
                .foregroundColor(.white.opacity(0.95))
            HStack {
                Text("Early")
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(totalCount > 0 ? "\(earlyCount)" : "—")
                    .foregroundColor(.white.opacity(0.9))
            }
            HStack {
                Text("On Time")
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(totalCount > 0 ? "\(idealCount)" : "—")
                    .foregroundColor(.white.opacity(0.9))
            }
            HStack {
                Text("Late")
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(totalCount > 0 ? "\(lateCount)" : "—")
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if shouldShowCalibrationSuggestion {
                VStack(spacing: 8) {
                    Text("For more accurate timing, try quick calibration")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                    Button {
                        showQuickCalibration = true
                    } label: {
                        Text("Calibrate Timing (10 seconds)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)
            }

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
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                } else if !UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey) {
                    Button {
                        if Config.isSupabaseConfigured {
                            navigateToAccountPrompt = true
                        } else {
                            navigateToCreateProfile = true
                        }
                    } label: {
                        Text("Continue to Home")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                }
            }

            if CoachRemoteSessionStartGate.isPadPlayerRole() {
                Text("Your coach starts the next session from Coach Remote on a phone.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                Button {
                    let route = PBASessionFlowPolicy.routeForActivityLaunch(.twoMinuteTest)
                    if CoachRemoteSessionStartGate.shouldBlock(route) {
                        if !CoachRemoteSessionStartGate.coachDeviceIsPresent() {
                            coachRemoteRequiredPrompt.present()
                        }
                    } else {
                        navigateToTestAgain = true
                    }
                } label: {
                    Text("Run It Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)

                Button {
                    let r = PBASessionFlowPolicy.routeForActivityLaunch(.awayFromPressure)
                    if CoachRemoteSessionStartGate.shouldBlock(r) {
                        if !CoachRemoteSessionStartGate.coachDeviceIsPresent() {
                            coachRemoteRequiredPrompt.present()
                        }
                        return
                    }
                    if let onStartTraining = onStartTraining {
                        onStartTraining(.awayFromPressure)
                    } else {
                        trainingTarget = .awayFromPressure
                    }
                } label: {
                    Text("Start Training")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            Button {
                navigateToPlayerReport = true
            } label: {
                Text("View Player Report")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(.plain)

            Button {
                popToRootTrigger.request = true
                onDismissCover?()
                router.popToRoot()
            } label: {
                Text("Back to Home")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    /// Top-of-screen result for onboarding: decisions count, average speed, elite benchmark.
    private var onboardingResultSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completed reps: \(loggedReps) / \(plannedTestReps)")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text("Average decision window: \(result.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")")
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
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

    @ViewBuilder
    private func roleSelectionView(for activity: ActivityKind) -> some View {
        let route = PBASessionFlowPolicy.routeForActivityLaunch(activity)
        switch route {
        case .twoMinuteRoleSelection:
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .awayFromPressureRoleSelection:
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .dribbleOrPassRoleSelection:
            DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .oneTouchPassingRoleSelection:
            OneTouchPassingRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .coachRemote:
            CoachRemoteHubView(settingsViewModel: settingsViewModel, profileManager: profileManager)
        case .trainingModeSelection(let title):
            TrainingModeSelectionView(activityTitle: title) { mode in
                TwoMinuteTestSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            }
        case .awayFromPressureTrainingModeSelection:
            TrainingModeSelectionView(activityTitle: "Playing Away From Pressure") { mode in
                AwayFromPressureSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            }
        case .dribbleOrPassTrainingModeSelection:
            TrainingModeSelectionView(activityTitle: "Dribble or Pass") { mode in
                DribbleOrPassSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            }
        case .oneTouchPassingTrainingModeSelection:
            TrainingModeSelectionView(activityTitle: "One-Touch Passing") { mode in
                OneTouchPassingSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
            }
        default:
            // For non-training routes that are not expected here, keep a safe empty fallback.
            EmptyView()
        }
    }

    private func saveProgressIfNeeded() {
        guard !didSave else { return }
        didSave = true
        if profileManager.profiles.isEmpty {
            return
        }
        let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId
        let isNewPlayerForCurriculum: Bool = {
            guard let pid = playerId else { return false }
            let existing = profileManager.profiles.first(where: { $0.id == pid })?.sessionResults ?? []
            return !existing.contains { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        }()
        let speedBucket = UniversalBlockSummaryHeadline.resolve(
            fast: result.fastCount,
            medium: result.mediumCount,
            slow: result.slowCount
        ).bucket
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
                guard let window = log.decisionWindowSeconds(activity: .twoMinuteTest, difficulty: result.difficulty) else { continue }
                let reactionTimeMs = Int(window * 1000)
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
            if isNewPlayerForCurriculum {
                _ = GuidedCurriculumEngine.assignBaselineStage(playerId: pid, baseline: sessionResult)
            }
        }
    }
}

// MARK: - Donut chart

private struct DecisionTimingDonutChart: View {
    let earlyCount: Int
    let idealCount: Int
    let lateCount: Int
    let totalCount: Int

    private var earlyFrac: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(earlyCount) / CGFloat(totalCount)
    }
    private var idealFrac: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(idealCount) / CGFloat(totalCount)
    }
    private var lateFrac: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(lateCount) / CGFloat(totalCount)
    }

    var body: some View {
        ZStack {
            if totalCount == 0 {
                Circle()
                    .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                    .frame(width: 160, height: 160)
                Text("No timing data")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            } else {
                let e = earlyFrac
                let i = idealFrac
                let l = lateFrac
                Circle()
                    .trim(from: 0, to: e)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 160, height: 160)
                Circle()
                    .trim(from: e, to: e + i)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 160, height: 160)
                Circle()
                    .trim(from: e + i, to: e + i + l)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 160, height: 160)
            }
        }
        .frame(width: 160, height: 160)
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
        .environmentObject(AppRouter())
        .environmentObject(CoachRemoteRequiredPromptController())
    }
}
