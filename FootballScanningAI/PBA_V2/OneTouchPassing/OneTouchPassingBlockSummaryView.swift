//
//  OneTouchPassingBlockSummaryView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Coach-style block summary, bias/speed/message, Show Details, Continue / Back to Curriculum.
//

import SwiftUI
import Combine

struct OneTouchPassingBlockSummaryView: View {
    let results: [OneTouchRepResult]
    let config: OneTouchPassingConfig
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

    private var blockResult: OneTouchBlockResult {
        OneTouchBlockResult.from(repResults: results)
    }

    /// Decision Speed Score (0–100) from correctness and reaction times; nil when no reps.
    private var decisionSpeedScoreValue: Int? {
        let ms = results.map { Int($0.decisionTime * 1000) }
        let correct = results.map(\.correct)
        return DecisionSpeedScore.sessionScore(reactionTimesMs: ms, correct: correct)
    }

    private var performanceLabel: String {
        let c = blockResult.correctCount
        if c >= 10 { return "Strong block" }
        if c >= 8 { return "Solid block" }
        return "Needs work"
    }

    private var dominantDecisionSpeed: DecisionSpeed {
        let f = blockResult.fastCount
        let m = blockResult.mediumCount
        let s = blockResult.slowCount
        if f >= m && f >= s { return .fast }
        if s >= f && s >= m { return .slow }
        return .medium
    }

    /// Bias: any direction >= 50% of passes (12 reps => 6+).
    private var biasDirection: Gate? {
        let total = results.count
        guard total > 0 else { return nil }
        for gate in Gate.allCases {
            let count = blockResult.directionCounts[gate] ?? 0
            if count >= (total + 1) / 2 { return gate }
        }
        return nil
    }

    private var biasString: String {
        guard let gate = biasDirection else { return "None" }
        switch gate {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    private var coachMessage: String {
        // 1) If bias detected (>=50%): show bias message first
        if let gate = biasDirection {
            switch gate {
            case .right: return "You favor the right side. Scan the whole field."
            case .left: return "You favor the left side. Scan the whole field."
            case .up: return "You force forward often. Sometimes the best play is sideways."
            case .down: return "You're playing safe too often. Look forward earlier."
            }
        }
        // 2) Else if Decision Speed is Slow
        if dominantDecisionSpeed == .slow {
            let c = blockResult.correctCount
            if c >= 8 {
                return "Good decisions. Now make them earlier."
            } else {
                return "You're reacting late. Scan sooner."
            }
        }
        // 3) Else by performance
        let c = blockResult.correctCount
        if c >= 10 {
            if biasDirection == nil {
                return "Good. You're using the whole field."
            }
            return "Good. You're playing before the ball arrives."
        }
        if c >= 8 {
            return "You're finding options. Stay consistent."
        }
        return "Find the green option earlier."
    }

    private var speedBucket: SpeedBucket {
        switch dominantDecisionSpeed {
        case .fast: return .fast
        case .medium: return .medium
        case .slow: return .slow
        }
    }

    private var sessionResult: SessionResult? {
        guard let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId else { return nil }
        return SessionResult(
            playerID: playerId,
            activityType: .oneTouchPassing,
            correctCount: blockResult.correctCount,
            totalReps: 12,
            speedCounts: SessionSpeedCounts(fast: blockResult.fastCount, medium: blockResult.mediumCount, slow: blockResult.slowCount),
            avgDecisionTime: blockResult.averageDecisionTime,
            biasDirection: biasDirection,
            directionCounts: blockResult.directionCounts,
            difficulty: config.difficulty,
            decisionTimeStdDev: blockResult.decisionTimeStdDev
        )
    }

    private var previousBlockSpeedBucket: SpeedBucket? {
        progressStore.lastN(.oneTouchPassing, n: 2, playerId: playerStore.selectedPlayerId).dropFirst().first?.speedBucket
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
                    activityName: "One-Touch Passing",
                    correct: blockResult.correctCount,
                    total: 12,
                    firstTouchAccuracy: nil,
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
                    activity: .oneTouchPassing,
                    gridSize: .fiveByFive,
                    difficulty: config.difficulty,
                    reps: 12,
                    decisionsCompleted: results.count,
                    correct: blockResult.correctCount,
                    forwardCorrect: nil,
                    speedBucket: speedBucket,
                    bias: biasString == "None" ? nil : biasString,
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
                activity: .oneTouchPassing,
                gridSize: .fiveByFive,
                difficulty: config.difficulty,
                reps: 12,
                decisionsCompleted: results.count,
                correct: blockResult.correctCount,
                forwardCorrect: nil,
                speedBucket: speedBucket,
                bias: biasString == "None" ? nil : biasString,
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
                    stimulusType: "teammate",
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
                    let p = await SupabaseSessionService.shared.decisionSpeedPercentile(activityName: ActivityKind.oneTouchPassing.rawValue, currentScore: score)
                    await MainActor.run { decisionSpeedPercentile = p }
                }
            }
            didSave = true
        }
        .navigationDestination(isPresented: $navigateToNewBlock) {
            OneTouchPassingDisplaySessionView(config: config, mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
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
                    Text("Correct Passes: \(blockResult.correctCount)/12")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Decision Speed: \(dominantDecisionSpeed.rawValue.capitalized)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Bias: \(biasString)")
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
                        detailRow("Up", "\(blockResult.directionCounts[.up] ?? 0)")
                        detailRow("Down", "\(blockResult.directionCounts[.down] ?? 0)")
                        detailRow("Left", "\(blockResult.directionCounts[.left] ?? 0)")
                        detailRow("Right", "\(blockResult.directionCounts[.right] ?? 0)")
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

    /// Pops back to Home/Progress when user taps "Back to Home" (5 levels).
    private func popToRootFromBlockSummary() {
        let levels = 5
        for i in 0..<levels {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 * Double(i)) {
                dismiss()
            }
        }
    }
}
