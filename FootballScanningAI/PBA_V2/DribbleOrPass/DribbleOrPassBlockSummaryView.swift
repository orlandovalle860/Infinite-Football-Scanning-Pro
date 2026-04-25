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
    var summaryCalibratedTravelSeconds: Double? = nil
    var showTimingAdaptationFeedback: Bool = false
    /// Live in-session streak from ``DribbleOrPassEngine.earlyStreak`` when available; otherwise derived from `results`.
    var liveEarlyRepStreak: Int? = nil
    /// Live all-time best from ``DribbleOrPassEngine.bestEarlyStreak`` when available (persisted during the block).
    var liveBestEarlyRepStreak: Int? = nil
    let onRunItBack: () -> Void

    private let timingCalibrationActivityId = ActivityKind.dribbleOrPass.sessionActivityActivityId
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
    @State private var earlySessionStreakForSummary: Int?

    private var endingEarlyRepStreak: Int {
        if let live = liveEarlyRepStreak { return live }
        return EarlyDecisionStreak.endingEarlyRepCount(from: results.map { $0.decisionSpeed == .fast })
    }

    private var blockResult: DribbleOrPassBlockResult {
        DribbleOrPassBlockResult.from(repResults: results)
    }

    private var decisionSpeedScoreValue: Int? {
        guard !results.isEmpty else { return nil }
        let accuracy = Double(blockResult.correctCount) / Double(results.count)
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: decisionWindowSeconds, activity: .dribbleOrPass)
    }

    private var travelTimeSeconds: Double {
        if let snap = summaryCalibratedTravelSeconds { return snap }
        let base = CurrentSessionStore.shared.expectedBallTravelTimeOverrideSeconds
            ?? config.difficulty.passTempo.expectedBallTravelTime(distanceMeters: 11.0)
        return CurrentSessionStore.shared.calibratedBallTravelSeconds(
            baseNominal: base,
            activityId: timingCalibrationActivityId
        )
    }

    private var decisionWindowSeconds: [Double] {
        results.map { travelTimeSeconds - $0.decisionTime }
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

    /// Forward Intent: reps where forward lane was actually open (environment), not a single expected gate.
    private var forwardOpportunities: Int {
        results.filter(\.forwardLaneOpen).count
    }
    private var forwardChoices: Int {
        results.filter { $0.forwardLaneOpen && $0.chosenGate == .up }.count
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
            return "Safe decision — look forward sooner"
        }
        return "Good mix. Keep building forward habits."
    }

    private var headlineSpeedResolution: UniversalBlockSummaryHeadline.Resolution {
        UniversalBlockSummaryHeadline.resolve(
            fast: blockResult.fastCount,
            medium: blockResult.mediumCount,
            slow: blockResult.slowCount
        )
    }

    private var biasString: String {
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for r in results { c[r.chosenGate, default: 0] += 1 }
        let l = c[.left] ?? 0, r = c[.right] ?? 0
        if l > r + 1 { return "Left" }
        if r > l + 1 { return "Right" }
        return "Balanced"
    }

    /// Block headline: dominant per-rep bucket (tie → worse bucket).
    private var speedBucket: SpeedBucket {
        headlineSpeedResolution.bucket
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
        let speedCounts = decisionWindowSpeedCounts
        let avgWindow = decisionWindowSeconds.isEmpty ? 0 : decisionWindowSeconds.reduce(0, +) / Double(decisionWindowSeconds.count)
        let optimal = results.filter { $0.decisionQuality == .correct }.count
        let acceptableOnly = results.filter { $0.decisionQuality == .acceptable }.count
        return SessionResult(
            playerID: playerId,
            activityType: .dribbleOrPass,
            correctCount: blockResult.correctCount,
            totalReps: 12,
            speedCounts: speedCounts,
            avgDecisionTime: avgWindow,
            biasDirection: biasString == "Left" ? .left : (biasString == "Right" ? .right : nil),
            directionCounts: [.up: 0, .down: downChoices, .left: 0, .right: 0],
            firstTouchCounts: firstTouchCountsFromResults,
            firstTouchMatchCount: firstTouchMatchCountFromResults,
            difficulty: config.difficulty,
            decisionTotalScore: Double(decisionSpeedScoreValue ?? 0),
            forwardChoiceCount: forwardOpportunities > 0 ? forwardChoices : nil,
            forwardOpportunityCount: forwardOpportunities > 0 ? forwardOpportunities : nil,
            preReceiveDecisionCount: preReceiveDecisionCountFromResults,
            decisionTimeStdDev: blockResult.decisionTimeStdDev,
            decisionOptimalCount: optimal,
            decisionAcceptableOnlyCount: acceptableOnly
        )
    }

    private var decisionWindowSpeedCounts: SessionSpeedCounts {
        var fast = 0, medium = 0, slow = 0
        let adaptiveScore = decisionSpeedScoreValue ?? 70
        for window in decisionWindowSeconds {
            switch DecisionTimingModel.speedBucket(forDecisionWindow: window, activity: .dribbleOrPass, score: adaptiveScore) {
            case .fast: fast += 1
            case .medium: medium += 1
            case .slow: slow += 1
            }
        }
        return SessionSpeedCounts(fast: fast, medium: medium, slow: slow)
    }

    private var previousBlockSpeedBucket: SpeedBucket? {
        progressStore.lastN(.dribbleOrPass, n: 2, playerId: playerStore.selectedPlayerId).dropFirst().first?.speedBucket
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
                    onRunItBack: onRunItBack,
                    earlyRepEndingStreak: endingEarlyRepStreak,
                    earlyRepBestStreak: liveBestEarlyRepStreak,
                    earlySessionStreakDisplay: earlySessionStreakForSummary,
                    profileManager: profileManager,
                    settingsViewModel: settingsViewModel
                )
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
            }
            else { blockSummaryContent }
        }
        .onAppear {
            PBASessionFlowPolicy.handleResultsPresented()
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            AnalyticsManager.shared.track(.trainingSessionCompleted, playerId: playerStore.selectedPlayerId)
            guard !didSave else { return }
            #if DEBUG
            print("[PBA-Debug] Block completed (DOP). results.count=\(results.count), correct=\(blockResult.correctCount), decisionSpeedScoreValue=\(decisionSpeedScoreValue ?? -1), playerId=\(playerStore.selectedPlayerId?.uuidString ?? "nil")")
            let repLabels = results.map { $0.decisionSpeed.rawValue }
            UniversalSummaryBucketDebugLog.log(
                activity: .dribbleOrPass,
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
                #if DEBUG
                print("[PBA-Debug] SessionRecord created (DOP, no sessionId). decisionSpeedScore=\(record.decisionSpeedScore ?? -1), playerId=\(record.playerId?.uuidString ?? "nil")")
                let savedScore = record.decisionSpeedScore.map(String.init) ?? "nil"
                print("[PBA-Debug] Saved session score: \(savedScore)")
                print("[PBA-Debug] Player ID match: \(record.playerId == playerStore.selectedPlayerId)")
                #endif
                previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
                let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
                progressStore.add(record)
                #if DEBUG
                print("[PBA-Debug] progressStore.add(record) DOP. sessions count=\(progressStore.sessions.count)")
                #endif
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
            #if DEBUG
            print("[PBA-Debug] SessionRecord created (DOP, with sessionId). decisionSpeedScore=\(record.decisionSpeedScore ?? -1), playerId=\(record.playerId?.uuidString ?? "nil")")
            let savedScore = record.decisionSpeedScore.map(String.init) ?? "nil"
            print("[PBA-Debug] Saved session score: \(savedScore)")
            print("[PBA-Debug] Player ID match: \(record.playerId == playerStore.selectedPlayerId)")
            #endif
            previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
            let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            progressStore.add(record)
            #if DEBUG
            print("[PBA-Debug] progressStore.add(record) DOP (with sessionId). sessions count=\(progressStore.sessions.count)")
            #endif
            personalBestScore = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            isNewPersonalBestForDecisionSpeed = (decisionSpeedScoreValue ?? 0) > (previousBest ?? -1)
            let decisions = results.map { TrainingDecisionRecord.from($0) }
            SupabaseSessionService.shared.saveSession(record: record, decisions: decisions) {
                progressStore.markSynced(id: record.id)
            }
            let playerId = record.playerId ?? playerStore.selectedPlayerId
            let activityName = record.activity.rawValue
            for r in results {
                let reactionTimeMs = Int((travelTimeSeconds - r.decisionTime) * 1000)
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
                let rewards = profileManager.addSessionResult(result)
                newPersonalBestsFromBlock = rewards.newPersonalBests
                xpEarnedFromBlock = rewards.xpEarned
                newlyUnlockedBadgesFromBlock = rewards.newlyUnlockedBadges
                earlySessionStreakForSummary = EarlySessionStreakStore.current(for: result.playerID)
                sessionResultForSummary = result
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
                    Text("Correct first decisions: \(blockResult.correctCount)/12")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    VStack(spacing: 4) {
                        Text("Decision Window: \(speedBucket.rawValue.capitalized)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        BlockSummarySpeedCountsSubline(
                            fast: blockResult.fastCount,
                            medium: blockResult.mediumCount,
                            slow: blockResult.slowCount,
                            debugActivity: .dribbleOrPass
                        )
                    }
                    .multilineTextAlignment(.center)
                    if showTimingAdaptationFeedback {
                        Text("Adapted to your pace")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)

                if CoachRemoteSessionStartGate.isPadPlayerRole() {
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
                    Text("Use the coach remote to start the next block.")
                        .font(.body.weight(.medium))
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                } else {
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
                }
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
