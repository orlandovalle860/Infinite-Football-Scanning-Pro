//
//  TwoMinuteResultsView.swift
//  FootballScanningAI
//
//  PBA V2 — Results: coaching tone, Your Receiving Profile, stat lines, one-sentence interpretation, Train / Retake.
//

import SwiftUI

struct TwoMinuteResultsView: View {
    let logs: [RepLog]
    let difficulty: TestDifficulty
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var didSave = false
    @State private var showRenameSheet = false
    @State private var navigateToCurriculum = false
    @State private var navigateToAwayFromPressure = false
    @State private var navigateToProgress = false
    @State private var navigateToCreateProfile = false
    @State private var sessionResultForSummary: SessionResult?
    @State private var isNewPersonalBestForSummary = false
    @State private var newPersonalBestsFromBlock: [NewPersonalBest] = []
    @State private var xpEarnedFromBlock: Int = 0
    @State private var newlyUnlockedBadgesFromBlock: [PlayerBadge] = []
    @State private var baselineRecommendation: GuidedCurriculumProgress?
    @State private var showBaselineRecommendation = false

    private var earlyDecisions: Int { logs.filter(\.correct).count }
    private var forwardCorrect: Int { logs.filter { $0.ballGate == .up && $0.correct }.count }
    private let forwardTotal = 4
    private var exitCounts: [Gate: Int] {
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for log in logs { c[log.exitedGate, default: 0] += 1 }
        return c
    }
    private var strongSideTendency: String {
        let l = exitCounts[.left] ?? 0
        let r = exitCounts[.right] ?? 0
        if l > r + 1 { return "Left" }
        if r > l + 1 { return "Right" }
        return "Balanced"
    }
    /// Bias for SessionRecord: Left, Right, Up, Down, or Balanced (5x5 baseline).
    private var biasString: String {
        let u = exitCounts[.up] ?? 0, d = exitCounts[.down] ?? 0
        let l = exitCounts[.left] ?? 0, r = exitCounts[.right] ?? 0
        let maxCount = max(u, d, l, r)
        let sum = u + d + l + r
        if sum == 0 { return "Balanced" }
        if u == maxCount && u > d && u > l && u > r { return "Up" }
        if d == maxCount && d > u && d > l && d > r { return "Down" }
        if l == maxCount && l > r + 1 { return "Left" }
        if r == maxCount && r > l + 1 { return "Right" }
        return "Balanced"
    }
    /// Average latency (passTriggered -> exitLogged) in seconds; nil if none. Shown in UI / analytics; not used for headline bucket.
    private var avgLatency: Double? {
        let withPass = logs.compactMap { log -> Double? in
            guard let pt = log.passTriggeredAt else { return nil }
            return log.exitLoggedAt.timeIntervalSince(pt)
        }
        guard !withPass.isEmpty else { return nil }
        return withPass.reduce(0, +) / Double(withPass.count)
    }

    private var twoMinuteSpeedCounts: SessionSpeedCounts {
        var fast = 0, medium = 0, slow = 0
        for log in logs {
            let t = log.exitLoggedAt.timeIntervalSince(log.passTriggeredAt ?? log.infoShownAt)
            switch TimingThresholds.speedBucket(for: t, activity: .twoMinuteTest) {
            case .fast: fast += 1
            case .medium: medium += 1
            case .slow: slow += 1
            }
        }
        return SessionSpeedCounts(fast: fast, medium: medium, slow: slow)
    }

    private var headlineSpeedResolution: UniversalBlockSummaryHeadline.Resolution {
        let c = twoMinuteSpeedCounts
        return UniversalBlockSummaryHeadline.resolve(fast: c.fast, medium: c.medium, slow: c.slow)
    }

    /// Session headline: dominant per-rep bucket (tie → worse bucket). Same thresholds as per-rep classification.
    private var speedBucket: SpeedBucket {
        headlineSpeedResolution.bucket
    }
    private var totalExits: Int { logs.count }
    private var leftExits: Int { exitCounts[.left] ?? 0 }
    private var rightExits: Int { exitCounts[.right] ?? 0 }
    /// Profile for this test (stored with record).
    private var evaluatedProfile: PlayerProfile {
        ProfileEvaluator.profile(
            speedBucket: speedBucket,
            bias: biasString,
            forwardCorrect: forwardCorrect,
            leftExits: leftExits,
            rightExits: rightExits,
            totalExits: totalExits
        )
    }
    private var twoMinutePerRepBucketLabels: [String] {
        logs.map { log in
            let t = log.exitLoggedAt.timeIntervalSince(log.passTriggeredAt ?? log.infoShownAt)
            return TimingThresholds.speedBucket(for: t, activity: .twoMinuteTest).rawValue
        }
    }

    private var biasGateFromBiasString: Gate? {
        switch biasString {
        case "Up": return .up
        case "Down": return .down
        case "Left": return .left
        case "Right": return .right
        default: return nil
        }
    }

    private var sessionResult: SessionResult? {
        guard let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId else { return nil }
        return SessionResult(
            playerID: playerId,
            activityType: .twoMinuteTest,
            correctCount: earlyDecisions,
            totalReps: 10,
            speedCounts: twoMinuteSpeedCounts,
            avgDecisionTime: avgLatency,
            biasDirection: biasGateFromBiasString,
            directionCounts: exitCounts,
            difficulty: difficulty,
            forwardChoiceCount: forwardCorrect,
            forwardOpportunityCount: forwardTotal
        )
    }
    /// Aggregated metrics for narrative + coach copy (same model as `TwoMinuteTestResultsView`).
    private var aggregatedTwoMinuteResult: TwoMinuteTestResult {
        TwoMinuteTestResult.from(logs: logs, difficulty: difficulty)
    }

    private var narrativePlayerType: PlayerType {
        TwoMinutePlayerType.determinePlayerType(
            correct: aggregatedTwoMinuteResult.correctCount,
            total: aggregatedTwoMinuteResult.totalReps,
            fast: aggregatedTwoMinuteResult.fastCount,
            medium: aggregatedTwoMinuteResult.mediumCount,
            slow: aggregatedTwoMinuteResult.slowCount
        )
    }

    private var postSessionNarrative: PBAPostSessionNarrative {
        PBAPostSessionNarrativeBuilder.fromTwoMinuteTestResult(
            aggregatedTwoMinuteResult,
            playerType: narrativePlayerType,
            previousTwoMinute: progressStore.previous(.twoMinuteTest, playerId: profileManager.currentProfile?.id ?? playerStore.selectedPlayerId),
            progressStore: progressStore,
            playerId: profileManager.currentProfile?.id ?? playerStore.selectedPlayerId
        )
    }

    private func activityTitle(_ activity: ActivityKind) -> String {
        switch activity {
        case .twoMinuteTest: return "2-Minute Test"
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        }
    }

    var body: some View {
        Group {
            if showBaselineRecommendation, let rec = baselineRecommendation, let baseline = sessionResult {
                baselineRecommendationContent(recommendation: rec, baseline: baseline)
            } else if let s = sessionResultForSummary {
                SessionSummaryView(session: s, playerName: profileManager.currentProfile?.name ?? playerStore.selectedPlayer?.name ?? "Player", isNewPersonalBest: isNewPersonalBestForSummary, newPersonalBests: newPersonalBestsFromBlock, xpEarned: xpEarnedFromBlock, newlyUnlockedBadges: newlyUnlockedBadgesFromBlock, profileManager: profileManager, settingsViewModel: settingsViewModel)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            } else {
                resultsContent
            }
        }
        .onAppear {
            guard !didSave else { return }
            #if DEBUG
            let c = twoMinuteSpeedCounts
            UniversalSummaryBucketDebugLog.log(
                activity: .twoMinuteTest,
                perRepBucketLabels: twoMinutePerRepBucketLabels,
                fast: c.fast,
                medium: c.medium,
                slow: c.slow,
                avgRawDeltaSeconds: avgLatency,
                headline: speedBucket,
                tieBreakApplied: headlineSpeedResolution.tieBreakApplied
            )
            #endif
            let wasNewPlayer = !(profileManager.currentProfile?.sessionResults.contains { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) } ?? false)
            guard let sessionId = CurrentSessionStore.shared.sessionId else {
                let record = SessionRecord(
                    id: UUID(),
                    date: Date(),
                    activity: .twoMinuteTest,
                    gridSize: .fiveByFive,
                    difficulty: difficulty,
                    reps: 10,
                    decisionsCompleted: logs.count,
                    correct: earlyDecisions,
                    forwardCorrect: forwardCorrect,
                    speedBucket: speedBucket,
                    bias: biasString,
                    avgLatency: avgLatency,
                    profile: evaluatedProfile,
                    playerId: playerStore.selectedPlayerId
                )
                progressStore.add(record)
                if let result = sessionResult {
                    isNewPersonalBestForSummary = profileManager.wouldBeNewPersonalBest(session: result)
                    let rewards = profileManager.addSessionResult(result)
                    newPersonalBestsFromBlock = rewards.newPersonalBests
                    xpEarnedFromBlock = rewards.xpEarned
                    newlyUnlockedBadgesFromBlock = rewards.newlyUnlockedBadges
                    if wasNewPlayer {
                        let rec = GuidedCurriculumEngine.assignBaselineStage(playerId: result.playerID, baseline: result)
                        baselineRecommendation = rec
                        showBaselineRecommendation = true
                    } else {
                        sessionResultForSummary = result
                    }
                }
                didSave = true
                return
            }
            let record = SessionRecord(
                id: sessionId,
                date: Date(),
                activity: .twoMinuteTest,
                gridSize: .fiveByFive,
                difficulty: difficulty,
                reps: 10,
                decisionsCompleted: logs.count,
                correct: earlyDecisions,
                forwardCorrect: forwardCorrect,
                speedBucket: speedBucket,
                bias: biasString,
                avgLatency: avgLatency,
                profile: evaluatedProfile,
                playerId: playerStore.selectedPlayerId
            )
            progressStore.add(record)
            let decisions = logs.map { TrainingDecisionRecord.from($0) }
            SupabaseSessionService.shared.saveSession(record: record, decisions: decisions) {
                progressStore.markSynced(id: record.id)
            }
            let playerId = record.playerId ?? playerStore.selectedPlayerId
            let activityName = record.activity.rawValue
            for log in logs {
                guard let sec = log.passTriggeredAt.map({ log.exitLoggedAt.timeIntervalSince($0) }) else { continue }
                let reactionTimeMs = Int(sec * 1000)
                if reactionTimeMs > SupabaseDecisionService.maxReactionTimeMs { continue }
                let decision = Decision(
                    sessionId: sessionId,
                    playerId: playerId,
                    activityName: activityName,
                    stimulusType: "ball",
                    decisionDirection: log.exitedGate.rawValue,
                    reactionTimeMs: reactionTimeMs,
                    correct: log.correct,
                    createdAt: log.exitLoggedAt
                )
                SupabaseDecisionService.shared.saveDecision(decision)
            }
            if let result = sessionResult {
                isNewPersonalBestForSummary = profileManager.wouldBeNewPersonalBest(session: result)
                let rewards = profileManager.addSessionResult(result)
                newPersonalBestsFromBlock = rewards.newPersonalBests
                xpEarnedFromBlock = rewards.xpEarned
                newlyUnlockedBadgesFromBlock = rewards.newlyUnlockedBadges
                if wasNewPlayer {
                    let rec = GuidedCurriculumEngine.assignBaselineStage(playerId: result.playerID, baseline: result)
                    baselineRecommendation = rec
                    showBaselineRecommendation = true
                } else {
                    sessionResultForSummary = result
                }
            }
            didSave = true
        }
        .navigationDestination(isPresented: $navigateToCurriculum) {
            PBACurriculumView(settingsViewModel: settingsViewModel, profileManager: profileManager, progressStore: progressStore, playerStore: playerStore, popToRootTrigger: popToRootTrigger)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToAwayFromPressure) {
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToProgress) {
            PBAProgressView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToCreateProfile) {
            CreatePlayerProfileAfterTestView(
                profileManager: profileManager,
                testResult: TestResultSummary(
                    decisionScore: min(100, earlyDecisions * 10),
                    status: evaluatedProfile.rawValue,
                    consistency: "First test"
                )
            )
        }
        .sheet(isPresented: $showRenameSheet) {
            renamePlayerSheet
        }
    }

    @ViewBuilder
    private func baselineRecommendationContent(recommendation: GuidedCurriculumProgress, baseline: SessionResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your Starting Point")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Baseline Summary")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)
                Text("Decision window: \(baseline.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                let accuracyPct = baseline.totalReps > 0 ? Int(round(Double(baseline.correctCount) / Double(baseline.totalReps) * 100.0)) : 0
                Text("Accuracy: \(accuracyPct)%")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Based on your baseline, we recommend starting with:")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Text("Stage \(recommendation.stage) of 3")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.yellow)
                Text(activityTitle(recommendation.nextActivity))
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Focus: \(recommendation.focus)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }

            Button {
                switch recommendation.nextActivity {
                case .awayFromPressure:
                    router.push(.awayFromPressureRoleSelection)
                case .dribbleOrPass:
                    router.push(.dribbleOrPassRoleSelection)
                case .oneTouchPassing:
                    router.push(.oneTouchPassingRoleSelection)
                case .twoMinuteTest:
                    router.push(.twoMinuteRoleSelection)
                }
            } label: {
                Text("Start Training")
                    .font(.headline.weight(.semibold))
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
                Text("Go to Home")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
    }

    private var resultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PBAPostSessionNarrativeStack(narrative: postSessionNarrative)

                Text("Your numbers")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white.opacity(0.95))
                Text("Reference only — your coach debrief is above.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))

                resultRow("Receiving profile", narrativePlayerType.title)
                resultRow("Early decisions", "\(earlyDecisions) / 10")
                resultRow("Forward decisions", "\(forwardCorrect) / \(forwardTotal)")
                resultRow("Decision window", sessionResult?.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")
                resultRow("Strong side tendency", strongSideTendency)
                twoMinuteDecisionSpeedHeadlineRow

                HStack {
                    Text("Saving progress for: \(playerStore.selectedPlayer?.name ?? "Player 1")")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.6))
                    Button("Rename") {
                        showRenameSheet = true
                    }
                    .font(.footnote)
                    .foregroundColor(.yellow)
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    if !UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey) {
                        Button {
                            navigateToCreateProfile = true
                        } label: {
                            Text("Continue to Home")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.yellow)
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Button {
                        if !UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey) {
                            navigateToCreateProfile = true
                            return
                        }
                        navigateToCurriculum = true
                    } label: {
                        Text("Go to Curriculum")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button {
                        if !UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey) {
                            navigateToCreateProfile = true
                            return
                        }
                        navigateToAwayFromPressure = true
                    } label: {
                        Text("Train Away From Pressure Now")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(PlainButtonStyle())
                    Text("Coach: on the other device, choose Playing Away From Pressure → Coach remote.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button {
                        if !UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey) {
                            navigateToCreateProfile = true
                            return
                        }
                        navigateToProgress = true
                    } label: {
                        Text("View Progress")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        dismiss()
                    } label: {
                        Text("Retake Test")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 24)

                Spacer(minLength: 40)
            }
            .padding(24)
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
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var renamePlayerSheet: some View {
        let name = playerStore.selectedPlayer?.name ?? ""
        return NavigationStack {
            RenamePlayerSheet(
                initialName: name,
                onSave: { newName in
                    playerStore.renameSelected(to: newName)
                    showRenameSheet = false
                },
                onCancel: { showRenameSheet = false }
            )
        }
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
    }

    /// Dominant bucket headline with rep counts (same `twoMinuteSpeedCounts` as universal headline).
    private var twoMinuteDecisionSpeedHeadlineRow: some View {
        let c = twoMinuteSpeedCounts
        return HStack(alignment: .top) {
            Text("Decision speed")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(speedBucket.rawValue.capitalized)
                    .font(.headline)
                    .foregroundColor(.white)
                BlockSummarySpeedCountsSubline(
                    fast: c.fast,
                    medium: c.medium,
                    slow: c.slow,
                    textAlignment: .trailing,
                    debugActivity: .twoMinuteTest
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rename player sheet
private struct RenamePlayerSheet: View {
    let initialName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            TextField("Player name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)
                .focused($focused)
            HStack(spacing: 16) {
                Button("Cancel") { onCancel() }
                    .foregroundColor(.white.opacity(0.8))
                Button("Save") {
                    onSave(name)
                }
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.yellow)
                .cornerRadius(10)
            }
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .onAppear {
            name = initialName
            focused = true
        }
    }
}
