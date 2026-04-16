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
    @State private var showSessionFeedback = false
    @State private var showDetails = false
    @State private var navigateToNewBlock = false
    @State private var navigateToCurriculum = false
    @State private var navigateToProgress = false
    @State private var sessionResultForSummary: SessionResult?
    @State private var isNewPersonalBestForSummary = false
    @State private var newPersonalBestsFromBlock: [NewPersonalBest] = []
    @State private var xpEarnedFromBlock: Int = 0
    @State private var newlyUnlockedBadgesFromBlock: [PlayerBadge] = []
    @State private var previousSessionForComparison: SessionRecord?
    @State private var personalBestScore: Int?
    @State private var isNewPersonalBestForDecisionSpeed = false

    private var blockResult: OneTouchBlockResult {
        OneTouchBlockResult.from(repResults: results)
    }

    private var decisionSpeedScoreValue: Int? {
        guard !results.isEmpty else { return nil }
        let accuracy = Double(blockResult.correctCount) / Double(results.count)
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: decisionWindowSeconds, activity: .oneTouchPassing)
    }

    private var integratedDecisionScore: Double {
        guard !results.isEmpty else { return 0 }
        let accuracy = Double(blockResult.correctCount) / Double(results.count)
        let speedValues = decisionWindowSeconds.map { window -> Double in
            if window > 0.25 { return 1.0 }
            if window > 0 { return 0.85 }
            return 0.4
        }
        let avgSpeed = speedValues.reduce(0, +) / Double(speedValues.count)
        return ((accuracy * 0.70) + (avgSpeed * 0.30)) * 100.0
    }

    private var travelTimeSeconds: Double {
        CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
    }

    private var decisionWindowSeconds: [Double] {
        results.map { travelTimeSeconds - $0.decisionTime }
    }

    private var decisionWindowSpeedCounts: SessionSpeedCounts {
        var fast = 0
        var medium = 0
        var slow = 0
        for window in decisionWindowSeconds {
            if window > 0.25 {
                fast += 1
            } else if window > 0 {
                medium += 1
            } else {
                slow += 1
            }
        }
        return SessionSpeedCounts(fast: fast, medium: medium, slow: slow)
    }

    private var avgDecisionWindow: Double {
        guard !decisionWindowSeconds.isEmpty else { return 0 }
        return decisionWindowSeconds.reduce(0, +) / Double(decisionWindowSeconds.count)
    }

    private var performanceLabel: String {
        let c = blockResult.correctCount
        if c >= 10 { return "Strong block" }
        if c >= 8 { return "Solid block" }
        return "Needs work"
    }

    private var headlineSpeedResolution: UniversalBlockSummaryHeadline.Resolution {
        UniversalBlockSummaryHeadline.resolve(
            fast: blockResult.fastCount,
            medium: blockResult.mediumCount,
            slow: blockResult.slowCount
        )
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
        // 2) Else if block headline speed is slow (dominant bucket; tie → worse)
        if speedBucket == .slow {
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
            return "Good. You're playing before expected arrival."
        }
        if c >= 8 {
            return "You're finding options. Stay consistent."
        }
        return "Find the green option earlier."
    }

    /// Block headline: dominant per-rep bucket (tie → worse bucket).
    private var speedBucket: SpeedBucket {
        headlineSpeedResolution.bucket
    }

    /// Forward Intent: only when up was a valid (green) option. forwardOpportunities = reps where up was available; forwardChoices = those reps where player chose up. Nil when no forward opportunities so metric is not displayed.
    private var forwardOpportunityCount: Int? {
        let n = results.filter { $0.greenDirections.contains(.up) }.count
        return n > 0 ? n : nil
    }
    private var forwardChoiceCount: Int? {
        guard forwardOpportunityCount != nil else { return nil }
        return results.filter { $0.greenDirections.contains(.up) && $0.chosenGate == .up }.count
    }

    private var sessionResult: SessionResult? {
        guard let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId else { return nil }
        return SessionResult(
            playerID: playerId,
            activityType: .oneTouchPassing,
            correctCount: blockResult.correctCount,
            totalReps: 12,
            speedCounts: decisionWindowSpeedCounts,
            avgDecisionTime: avgDecisionWindow,
            biasDirection: biasDirection,
            directionCounts: blockResult.directionCounts,
            difficulty: config.difficulty,
            decisionTotalScore: integratedDecisionScore,
            forwardChoiceCount: forwardChoiceCount,
            forwardOpportunityCount: forwardOpportunityCount,
            decisionTimeStdDev: blockResult.decisionTimeStdDev
        )
    }

    private var previousBlockSpeedBucket: SpeedBucket? {
        progressStore.lastN(.oneTouchPassing, n: 2, playerId: playerStore.selectedPlayerId).dropFirst().first?.speedBucket
    }

    private var sessionFeedbackCoachSentence: String {
        if let s = sessionResult {
            return CoachInsightGenerator.coachInsight(for: s, previous: previousSessionForComparison)
        }
        return coachMessage
    }

    var body: some View {
        Group {
            if let s = sessionResultForSummary {
                SessionSummaryScreenView(
                    session: s,
                    playerName: profileManager.currentProfile?.name ?? "Player",
                    isNewPersonalBest: isNewPersonalBestForSummary,
                    newPersonalBests: newPersonalBestsFromBlock,
                    xpEarned: xpEarnedFromBlock,
                    newlyUnlockedBadges: newlyUnlockedBadgesFromBlock,
                    profileManager: profileManager,
                    settingsViewModel: settingsViewModel
                )
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
            }
            else { blockSummaryContent }
        }
        .onAppear {
            PBASessionFlowPolicy.handleResultsPresented()
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            AnalyticsManager.shared.track(.trainingSessionCompleted, playerId: playerStore.selectedPlayerId)
            guard !didSave else { return }
            #if DEBUG
            print("[PBA-Debug] Block completed (OTP). results.count=\(results.count), correct=\(blockResult.correctCount), decisionSpeedScoreValue=\(decisionSpeedScoreValue ?? -1), playerId=\(playerStore.selectedPlayerId?.uuidString ?? "nil")")
            let repLabels = results.map { $0.decisionSpeed.rawValue }
            UniversalSummaryBucketDebugLog.log(
                activity: .oneTouchPassing,
                perRepBucketLabels: repLabels,
                fast: blockResult.fastCount,
                medium: blockResult.mediumCount,
                slow: blockResult.slowCount,
                avgRawDeltaSeconds: blockResult.averageDecisionTime,
                headline: speedBucket,
                tieBreakApplied: headlineSpeedResolution.tieBreakApplied
            )
            #endif
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
                #if DEBUG
                print("[PBA-Debug] SessionRecord created (OTP, no sessionId). decisionSpeedScore=\(record.decisionSpeedScore ?? -1), playerId=\(record.playerId?.uuidString ?? "nil")")
                #endif
                previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
                let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
                progressStore.add(record)
                #if DEBUG
                print("[PBA-Debug] progressStore.add(record) OTP. sessions count=\(progressStore.sessions.count)")
                #endif
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
            #if DEBUG
            print("[PBA-Debug] SessionRecord created (OTP, with sessionId). decisionSpeedScore=\(record.decisionSpeedScore ?? -1), playerId=\(record.playerId?.uuidString ?? "nil")")
            #endif
            previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
            let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            progressStore.add(record)
            #if DEBUG
            print("[PBA-Debug] progressStore.add(record) OTP (with sessionId). sessions count=\(progressStore.sessions.count)")
            #endif
            personalBestScore = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            isNewPersonalBestForDecisionSpeed = (decisionSpeedScoreValue ?? 0) > (previousBest ?? -1)
            let decisions = results.map { TrainingDecisionRecord.from($0) }
            SupabaseSessionService.shared.saveSession(record: record, decisions: decisions) {
                progressStore.markSynced(id: record.id)
            }
            let playerId = record.playerId ?? playerStore.selectedPlayerId
            let activityName = record.activity.rawValue
            let travelTimeSeconds = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
                ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
            for r in results {
                let reactionTimeMs = Int((travelTimeSeconds - r.decisionTime) * 1000)
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
                let rewards = profileManager.addSessionResult(result)
                newPersonalBestsFromBlock = rewards.newPersonalBests
                xpEarnedFromBlock = rewards.xpEarned
                newlyUnlockedBadgesFromBlock = rewards.newlyUnlockedBadges
                sessionResultForSummary = result
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
                    Text("Correct first decisions: \(blockResult.correctCount)/12")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    VStack(spacing: 4) {
                        Text("Decision Speed: \(speedBucket.rawValue.capitalized)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        BlockSummarySpeedCountsSubline(
                            fast: blockResult.fastCount,
                            medium: blockResult.mediumCount,
                            slow: blockResult.slowCount,
                            debugActivity: .oneTouchPassing
                        )
                    }
                    .multilineTextAlignment(.center)
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
