//
//  DribbleOrPassBlockSummaryView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Coach-style block summary, Show Details, Continue Training.
//

import SwiftUI

struct DribbleOrPassBlockSummaryView: View {
    let results: [DribbleOrPassRepResult]
    let config: DribbleOrPassConfig
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var didSave = false
    @State private var showSessionFeedback = true
    @State private var showDetails = false
    @State private var navigateToNewBlock = false
    @State private var navigateToCurriculum = false
    @State private var navigateToProgress = false
    @State private var sessionResultForSummary: SessionResult?
    @State private var isNewPersonalBestForSummary = false
    @State private var newPersonalBestsFromBlock: [NewPersonalBest] = []
    @State private var decisionSpeedPercentile: Int?
    @State private var previousSessionForComparison: SessionRecord?
    @State private var personalBestScore: Int?
    @State private var isNewPersonalBestForDecisionSpeed = false

    private var blockResult: DribbleOrPassBlockResult {
        DribbleOrPassBlockResult.from(repResults: results)
    }

    /// Decision Speed Score (0–100) from correctness and reaction times; nil when no reps.
    private var decisionSpeedScoreValue: Int? {
        let ms = results.map { Int($0.decisionTime * 1000) }
        let correct = results.map(\.correct)
        return DecisionSpeedScore.sessionScore(reactionTimesMs: ms, correct: correct)
    }

    /// Decision-hierarchy tiers (score 0–60): Elite → Playmaker → Forward Thinker → Positive Player → Safe Player.
    private var performanceLabel: String {
        let score = blockResult.totalScore
        if score >= 52 { return "Elite" }
        if score >= 44 { return "Playmaker" }
        if score >= 36 { return "Forward Thinker" }
        if score >= 24 { return "Positive Player" }
        return "Safe Player"
    }

    private var downChoices: Int {
        results.filter { $0.chosenGate == .down }.count
    }

    private var forwardChoices: Int {
        results.filter { $0.chosenGate == .up }.count
    }

    private var lateralChoices: Int {
        results.filter { [.left, .right].contains($0.chosenGate) }.count
    }

    /// Feedback from decision hierarchy: reward forward play, flag backward, note safe-but-lateral.
    private var coachMessage: String {
        if downChoices >= 1 {
            return "You're going backwards when better options exist."
        }
        if forwardChoices >= 6 && blockResult.fastCount >= 4 {
            return "You're recognizing forward options early."
        }
        if lateralChoices >= 6 && forwardChoices <= 3 {
            return "You're finding safe options, but not progressing enough."
        }
        return "Good mix. Keep building forward habits."
    }

    private var dominantDecisionSpeed: DecisionSpeed {
        let f = blockResult.fastCount
        let m = blockResult.mediumCount
        let s = blockResult.slowCount
        if f >= m && f >= s { return .fast }
        if s >= f && s >= m { return .slow }
        return .medium
    }

    private var biasString: String {
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for r in results { c[r.chosenGate, default: 0] += 1 }
        let l = c[.left] ?? 0, r = c[.right] ?? 0
        if l > r + 1 { return "Left" }
        if r > l + 1 { return "Right" }
        return "Balanced"
    }

    private var speedBucket: SpeedBucket {
        switch dominantDecisionSpeed {
        case .fast: return .fast
        case .medium: return .medium
        case .slow: return .slow
        }
    }

    private var firstTouchCountsFromResults: [Gate: Int]? {
        let withFirst = results.compactMap { $0.firstTouchGate }
        guard !withFirst.isEmpty else { return nil }
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for g in withFirst { c[g, default: 0] += 1 }
        return c
    }

    private var firstTouchMatchCountFromResults: Int? {
        let withFirst = results.filter { $0.firstTouchGate != nil }
        guard !withFirst.isEmpty else { return nil }
        return withFirst.filter { $0.firstTouchAccurate == true }.count
    }

    /// Pre-Receive Decision: reps where decisionTime < threshold AND firstTouch == correct direction.
    private var preReceiveDecisionCountFromResults: Int? {
        let threshold = TimingThresholds.earlyDecisionThresholdForPreReceive
        return results.filter { r in
            r.decisionTime < threshold && r.firstTouchAccurate == true
        }.count
    }

    private var sessionResult: SessionResult? {
        guard let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId else { return nil }
        return SessionResult(
            playerID: playerId,
            activityType: .dribbleOrPass,
            correctCount: blockResult.correctCount,
            totalReps: 12,
            speedCounts: SessionSpeedCounts(fast: blockResult.fastCount, medium: blockResult.mediumCount, slow: blockResult.slowCount),
            avgDecisionTime: blockResult.averageDecisionTime,
            biasDirection: biasString == "Left" ? .left : (biasString == "Right" ? .right : nil),
            directionCounts: [.up: 0, .down: downChoices, .left: 0, .right: 0],
            firstTouchCounts: firstTouchCountsFromResults,
            firstTouchMatchCount: firstTouchMatchCountFromResults,
            difficulty: config.difficulty,
            decisionTotalScore: blockResult.totalScore,
            forwardChoiceCount: forwardChoices,
            forwardOpportunityCount: 12,
            preReceiveDecisionCount: preReceiveDecisionCountFromResults,
            decisionTimeStdDev: blockResult.decisionTimeStdDev
        )
    }

    private var previousBlockSpeedBucket: SpeedBucket? {
        progressStore.lastN(.dribbleOrPass, n: 2, playerId: playerStore.selectedPlayerId).dropFirst().first?.speedBucket
    }

    private var sessionFeedbackCoachSentence: String {
        if let s = sessionResult {
            return CoachInsightGenerator.coachInsight(for: s)
        }
        return coachMessage
    }

    var body: some View {
        Group {
            if showSessionFeedback {
                TrainingCompleteFeedbackView(
                    activityName: "Dribble or Pass",
                    correct: blockResult.correctCount,
                    total: 12,
                    firstTouchAccuracy: firstTouchMatchCountFromResults != nil ? "\(firstTouchMatchCountFromResults!)/12" : nil,
                    decisionSpeedLabel: decisionSpeedComparisonLabel(current: speedBucket, previous: previousBlockSpeedBucket),
                    avgDecisionTimeSeconds: blockResult.averageDecisionTime,
                    decisionSpeedScore: decisionSpeedScoreValue,
                    decisionSpeedPercentile: decisionSpeedPercentile,
                    previousDecisionSpeedScore: previousSessionForComparison?.decisionSpeedScore,
                    previousAvgReactionTimeSeconds: previousSessionForComparison?.avgLatency,
                    previousCorrect: previousSessionForComparison?.correct,
                    previousTotal: previousSessionForComparison?.decisionsCompleted,
                    personalBest: personalBestScore,
                    isNewPersonalBest: isNewPersonalBestForDecisionSpeed,
                    coachFeedback: sessionFeedbackCoachSentence,
                    onContinue: { showSessionFeedback = false }
                )
            } else if let s = sessionResultForSummary {
                SessionSummaryView(
                    session: s,
                    playerName: profileManager.currentProfile?.name ?? "Player",
                    isNewPersonalBest: isNewPersonalBestForSummary,
                    newPersonalBests: newPersonalBestsFromBlock,
                    profileManager: profileManager,
                    settingsViewModel: settingsViewModel
                )
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
            } else {
                blockSummaryContent
            }
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            AnalyticsManager.shared.track(.trainingSessionCompleted, playerId: playerStore.selectedPlayerId)
            guard !didSave else { return }
            guard let sessionId = CurrentSessionStore.shared.sessionId else {
                let record = SessionRecord(
                    id: UUID(),
                    date: Date(),
                    activity: .dribbleOrPass,
                    gridSize: .fiveByFive,
                    difficulty: config.difficulty,
                    reps: 12,
                    decisionsCompleted: results.count,
                    correct: blockResult.correctCount,
                    forwardCorrect: nil,
                    speedBucket: speedBucket,
                    bias: biasString,
                    avgLatency: blockResult.averageDecisionTime,
                    profile: nil,
                    playerId: playerStore.selectedPlayerId,
                    decisionSpeedScore: decisionSpeedScoreValue
                )
                previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
                let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
                progressStore.add(record)
                personalBestScore = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
                isNewPersonalBestForDecisionSpeed = (decisionSpeedScoreValue ?? 0) > (previousBest ?? -1)
                didSave = true
                return
            }
            let record = SessionRecord(
                id: sessionId,
                date: Date(),
                activity: .dribbleOrPass,
                gridSize: .fiveByFive,
                difficulty: config.difficulty,
                reps: 12,
                decisionsCompleted: results.count,
                correct: blockResult.correctCount,
                forwardCorrect: nil,
                speedBucket: speedBucket,
                bias: biasString,
                avgLatency: blockResult.averageDecisionTime,
                profile: nil,
                playerId: playerStore.selectedPlayerId,
                decisionSpeedScore: decisionSpeedScoreValue
            )
            previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
            let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            progressStore.add(record)
            personalBestScore = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            isNewPersonalBestForDecisionSpeed = (decisionSpeedScoreValue ?? 0) > (previousBest ?? -1)
            let decisions = results.map { TrainingDecisionRecord.from($0) }
            SupabaseSessionService.shared.saveSession(record: record, decisions: decisions) {
                progressStore.markSynced(id: record.id)
            }
            let playerId = record.playerId ?? playerStore.selectedPlayerId
            let activityName = record.activity.rawValue
            for r in results {
                let reactionTimeMs = Int(r.decisionTime * 1000)
                if reactionTimeMs > SupabaseDecisionService.maxReactionTimeMs { continue }
                let decision = Decision(
                    sessionId: sessionId,
                    playerId: playerId,
                    activityName: activityName,
                    stimulusType: "space",
                    decisionDirection: r.chosenGate.rawValue,
                    reactionTimeMs: reactionTimeMs,
                    correct: r.correct,
                    createdAt: Date()
                )
                SupabaseDecisionService.shared.saveDecision(decision)
            }
            if let result = sessionResult {
                isNewPersonalBestForSummary = profileManager.wouldBeNewPersonalBest(session: result)
                newPersonalBestsFromBlock = profileManager.addSessionResult(result)
                sessionResultForSummary = result
            }
            if let score = decisionSpeedScoreValue {
                Task {
                    let p = await SupabaseSessionService.shared.decisionSpeedPercentile(activityName: ActivityKind.dribbleOrPass.rawValue, currentScore: score)
                    await MainActor.run { decisionSpeedPercentile = p }
                }
            }
            didSave = true
        }
        .navigationDestination(isPresented: $navigateToNewBlock) {
            DribbleOrPassDisplaySessionView(config: config, mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToCurriculum) {
            PBACurriculumView(settingsViewModel: settingsViewModel, profileManager: profileManager, progressStore: progressStore, playerStore: playerStore, popToRootTrigger: popToRootTrigger)
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
    }

    private var blockSummaryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    Text("Block complete")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(performanceLabel)
                        .font(.headline)
                        .foregroundColor(.yellow)
                    Text(coachMessage)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.85))
                    Text("Score: \(Int(blockResult.totalScore))/60")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Text("(Forward pass 4, forward dribble 3, lateral pass 2, lateral dribble 1, backward 0; + fast timing)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Correct gate: \(blockResult.correctCount)/12")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Decision Window: \(dominantDecisionSpeed.rawValue.capitalized)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)

                Button(showDetails ? "Hide details" : "Show details") {
                    showDetails.toggle()
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))

                if showDetails {
                    VStack(spacing: 10) {
                        detailRow("Average decision window", String(format: "%.2fs", blockResult.averageDecisionTime))
                        detailRow("Fast", "\(blockResult.fastCount)")
                        detailRow("Medium", "\(blockResult.mediumCount)")
                        detailRow("Slow", "\(blockResult.slowCount)")
                        detailRow("Backward choices", "\(downChoices)/12")
                        detailRow("Directional bias", biasString)
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                }

                VStack(spacing: 12) {
                    Button { navigateToNewBlock = true } label: {
                        Text("Continue Training")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button { navigateToCurriculum = true } label: {
                        Text("Back to Curriculum")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button { navigateToProgress = true } label: {
                        Text("View Progress")
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
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
    }

    /// Pops back to Home/Progress when user taps "Back to Home" (5 levels: Role → Setup → GetReady → Session → BlockSummary).
    private func popToRootFromBlockSummary() {
        let levels = 5
        for i in 0..<levels {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 * Double(i)) {
                dismiss()
            }
        }
    }
}
