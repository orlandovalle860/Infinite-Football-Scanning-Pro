//
//  AwayFromPressureBlockSummaryView.swift
//  FootballScanningAI
//
//  PBA V2 — After 12 reps: correct X/12, latency, bias; save record; Continue / Retest / Progress.
//

import SwiftUI

struct AwayFromPressureBlockSummaryView: View {
    let logs: [AwayFromPressureRepLog]
    let config: AwayFromPressureConfig
    let trainingMode: TrainingMode
    /// Effective pass travel (seconds) used for decision-window math on this block; nil = derive from store/config.
    var summaryCalibratedTravelSeconds: Double? = nil
    /// Set from display at block complete when timing calibration ≠ 1.0 for this activity.
    var showTimingAdaptationFeedback: Bool = false

    private let timingCalibrationActivityId = ActivityKind.awayFromPressure.sessionActivityActivityId
    /// Pops summary and resets the display session (same activity; no role selection).
    let onRunItBack: () -> Void
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
    @State private var navigateToTwoMinute = false
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
    @State private var earlyRepBestStreakForSummary: Int?

    private var earlyRepFlagsForBestStreak: [Bool] {
        logs.map { log -> Bool in
            guard let t = log.decisionTimeSeconds else { return false }
            return travelTimeSeconds - t > 0.25
        }
    }

    /// Consecutive early reps at end of block (same threshold as `speedCounts`: window > 0.25s).
    private var endingEarlyRepStreak: Int {
        EarlyDecisionStreak.endingEarlyRepCount(from: earlyRepFlagsForBestStreak)
    }

    private var maxConsecutiveEarlyRepStreak: Int {
        EarlyDecisionStreak.maxConsecutiveEarlyDuringBlock(from: earlyRepFlagsForBestStreak)
    }

    private var correctCount: Int { logs.filter(\.correct).count }

    private var decisionSpeedScoreValue: Int? {
        guard !logs.isEmpty else { return nil }
        let accuracy = Double(correctCount) / Double(logs.count)
        return DecisionTimingModel.decisionScore(accuracy: accuracy, windows: decisionWindowSeconds, activity: .awayFromPressure)
    }

    private var integratedDecisionScore: Double {
        guard !logs.isEmpty else { return 0 }
        let accuracy = Double(correctCount) / Double(logs.count)
        let speedValues = decisionWindowSeconds.map { window -> Double in
            if window > 0.25 { return 1.0 }
            if window > 0 { return 0.85 }
            return 0.4
        }
        let avgSpeed = speedValues.isEmpty ? 0 : (speedValues.reduce(0, +) / Double(speedValues.count))
        return ((accuracy * 0.70) + (avgSpeed * 0.30)) * 100.0
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
        logs.compactMap(\.decisionTimeSeconds).map { travelTimeSeconds - $0 }
    }

    private var performanceLabel: String {
        if correctCount >= 10 { return "Strong block" }
        if correctCount >= 8 { return "Solid block" }
        return "Needs work"
    }

    private var coachMessage: String {
        if correctCount >= 10 {
            return "Good. You decided away from pressure consistently. Keep the standard."
        } else if correctCount >= 8 {
            return "You're reading pressure. Now make the first decision earlier."
        } else {
            return "You're reacting late. Commit to your first decision earlier."
        }
    }

    private var avgLatencyString: String {
        avgLatency.map { String(format: "%.2fs", $0) } ?? "—"
    }
    private var repsWithFirstTouchLogged: Int { logs.filter { $0.firstTouchGate != nil }.count }
    private var lateCorrectionsCount: Int { logs.filter(\.lateCorrection).count }
    /// Average decision time (trigger → coach direction). Nil when no reps have timing.
    private var avgLatency: Double? {
        let times = logs.compactMap(\.decisionTimeSeconds)
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }
    private var headlineSpeedResolution: UniversalBlockSummaryHeadline.Resolution {
        let c = speedCounts
        return UniversalBlockSummaryHeadline.resolve(fast: c.fast, medium: c.medium, slow: c.slow)
    }

    /// Block headline: dominant per-rep bucket (tie → worse bucket). Average latency is shown separately, not used for this label.
    private var speedBucket: SpeedBucket {
        headlineSpeedResolution.bucket
    }
    private var biasString: String {
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for log in logs { if let g = log.exitedGate { c[g, default: 0] += 1 } }
        let u = c[.up] ?? 0, d = c[.down] ?? 0, l = c[.left] ?? 0, r = c[.right] ?? 0
        let maxC = max(u, d, l, r)
        if u == maxC && u > d && u > l && u > r { return "Up" }
        if d == maxC && d > u && d > l && d > r { return "Down" }
        if l == maxC && l > r + 1 { return "Left" }
        if r == maxC && r > l + 1 { return "Right" }
        return "Balanced"
    }

    private var speedCounts: SessionSpeedCounts {
        var f = 0, m = 0, s = 0
        for window in decisionWindowSeconds {
            if window > 0.25 {
                f += 1
            } else if window > 0 {
                m += 1
            } else {
                s += 1
            }
        }
        return SessionSpeedCounts(fast: f, medium: m, slow: s)
    }

    private var directionCounts: [Gate: Int] {
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for log in logs { if let g = log.exitedGate { c[g, default: 0] += 1 } }
        return c
    }

    private var biasGate: Gate? {
        let u = directionCounts[.up] ?? 0, d = directionCounts[.down] ?? 0, l = directionCounts[.left] ?? 0, r = directionCounts[.right] ?? 0
        let maxC = max(u, d, l, r)
        if u == maxC && u > d && u > l && u > r { return .up }
        if d == maxC && d > u && d > l && d > r { return .down }
        if l == maxC && l > r + 1 { return .left }
        if r == maxC && r > l + 1 { return .right }
        return nil
    }

    private var firstTouchCountsFromLogs: [Gate: Int]? {
        let withFirst = logs.compactMap { $0.firstTouchGate }
        guard withFirst.count >= 3 else { return nil }
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for g in withFirst { c[g, default: 0] += 1 }
        return c
    }

    /// Reps (with first touch logged) where first touch matched the correct escape direction.
    private var firstTouchMatchCountFromLogs: Int? {
        let withFirst = logs.filter { $0.firstTouchGate != nil }
        guard withFirst.count >= 3 else { return nil }
        return withFirst.filter { log in
            guard let ft = log.firstTouchGate else { return false }
            return ft == log.pressureGate.opposite
        }.count
    }

    /// Pre-Receive Decision: reps where decisionTime < threshold AND firstTouch == correct direction.
    private var preReceiveDecisionCountFromLogs: Int? {
        let threshold = TimingThresholds.earlyDecisionThresholdForPreReceive
        let withFirst = logs.filter { $0.firstTouchGate != nil }
        guard withFirst.count >= 3 else { return nil }
        return withFirst.filter { log in
            guard let t = log.decisionTimeSeconds, t < threshold,
                  let ft = log.firstTouchGate, ft == log.pressureGate.opposite else { return false }
            return true
        }.count
    }

    /// Reps where first touch was toward pressure (wrong direction).
    private var firstTouchTowardPressureCountFromLogs: Int? {
        let withFirst = logs.filter { $0.firstTouchGate != nil }
        guard withFirst.count >= 3 else { return nil }
        return withFirst.filter { $0.firstTouchGate == $0.pressureGate }.count
    }

    /// Reps where first touch was sideways/neutral (hesitating between options).
    private var firstTouchHesitantCountFromLogs: Int? {
        let withFirst = logs.filter { $0.firstTouchGate != nil }
        guard withFirst.count >= 3 else { return nil }
        return withFirst.filter { log in
            guard let ft = log.firstTouchGate else { return false }
            let correct = log.pressureGate.opposite
            return isSideways(correct: correct, firstTouch: ft)
        }.count
    }

    private func isSideways(correct: Gate, firstTouch: Gate) -> Bool {
        let vertical: Set<Gate> = [.up, .down]
        let horizontal: Set<Gate> = [.left, .right]
        if vertical.contains(correct) { return horizontal.contains(firstTouch) }
        if horizontal.contains(correct) { return vertical.contains(firstTouch) }
        return false
    }

    private var decisionTimeStdDev: Double? {
        let times = logs.compactMap(\.decisionTimeSeconds)
        return SessionResult.standardDeviation(of: times)
    }

    private var sessionResult: SessionResult? {
        guard let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId else { return nil }
        return SessionResult(
            playerID: playerId,
            activityType: .awayFromPressure,
            correctCount: correctCount,
            totalReps: 12,
            speedCounts: speedCounts,
            avgDecisionTime: decisionWindowSeconds.isEmpty ? nil : (decisionWindowSeconds.reduce(0, +) / Double(decisionWindowSeconds.count)),
            biasDirection: biasGate,
            directionCounts: directionCounts,
            firstTouchCounts: firstTouchCountsFromLogs,
            firstTouchMatchCount: firstTouchMatchCountFromLogs,
            firstTouchTowardPressureCount: firstTouchTowardPressureCountFromLogs,
            firstTouchHesitantCount: firstTouchHesitantCountFromLogs,
            lateAdjustments: repsWithFirstTouchLogged >= 3 ? lateCorrectionsCount : nil,
            difficulty: config.difficulty,
            decisionTotalScore: integratedDecisionScore,
            preReceiveDecisionCount: preReceiveDecisionCountFromLogs,
            decisionTimeStdDev: decisionTimeStdDev
        )
    }

    /// Last 2 Away From Pressure blocks (includes the one just saved); strong = >=9/12 and fast.
    private var last2AwayFromPressure: [SessionRecord] {
        progressStore.lastN(.awayFromPressure, n: 2, playerId: playerStore.selectedPlayerId)
    }
    private var last2AreStrong: Bool {
        last2AwayFromPressure.count == 2 &&
        last2AwayFromPressure.allSatisfy { $0.correct >= 9 && $0.speedBucket == .fast }
    }
    private var retestMessage: String {
        last2AreStrong ? "You're ready to re-test." : "Recommended after 2 strong blocks."
    }

    private var previousBlockSpeedBucket: SpeedBucket? {
        let lastTwo = progressStore.lastN(.awayFromPressure, n: 2, playerId: playerStore.selectedPlayerId)
        return lastTwo.dropFirst().first?.speedBucket
    }

    private var sessionFeedbackCoachSentence: String {
        if let s = sessionResult {
            return CoachInsightGenerator.coachInsight(for: s, previous: previousSessionForComparison)
        }
        return coachMessage
    }

    var body: some View {
        Group {
            if trainingMode == .solo {
                SoloSessionSummaryView(
                    passTempo: config.difficulty.passTempo,
                    recalibrationRoute: .awayFromPressureSetup(mode: .solo),
                    onRunItBack: onRunItBack,
                    onDone: { popToRootFromBlockSummary() }
                )
                .environmentObject(router)
            } else if let s = sessionResultForSummary {
                SessionSummaryScreenView(
                    session: s,
                    playerName: profileManager.currentProfile?.name ?? "Player",
                    isNewPersonalBest: isNewPersonalBestForSummary,
                    newPersonalBests: newPersonalBestsFromBlock,
                    xpEarned: xpEarnedFromBlock,
                    newlyUnlockedBadges: newlyUnlockedBadgesFromBlock,
                    onRunItBack: onRunItBack,
                    earlyRepEndingStreak: endingEarlyRepStreak,
                    earlyRepBestStreak: earlyRepBestStreakForSummary,
                    earlySessionStreakDisplay: earlySessionStreakForSummary,
                    profileManager: profileManager,
                    settingsViewModel: settingsViewModel,
                    trainingMode: trainingMode
                )
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
            } else {
                blockSummaryContent
            }
        }
        .onAppear {
            PBASessionFlowPolicy.handleResultsPresented()
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            #if DEBUG
            if !didSave {
                DecisionSpeedDebugLog.logAwayFromPressureAggregate(logs: logs, difficulty: config.difficulty)
                let adaptiveScore = decisionSpeedScoreValue ?? 70
                let repLabels = logs.map { log -> String in
                    guard let t = log.decisionTimeSeconds else { return "none" }
                    let window = DecisionTimingModel.decisionWindow(rawRepInterval: t, activity: .awayFromPressure, difficulty: config.difficulty)
                    return DecisionTimingModel.speedBucket(forDecisionWindow: window, activity: .awayFromPressure, score: adaptiveScore).rawValue
                }
                let c = speedCounts
                UniversalSummaryBucketDebugLog.log(
                    activity: .awayFromPressure,
                    perRepBucketLabels: repLabels,
                    fast: c.fast,
                    medium: c.medium,
                    slow: c.slow,
                    avgRawDeltaSeconds: avgLatency,
                    headline: speedBucket,
                    tieBreakApplied: headlineSpeedResolution.tieBreakApplied
                )
            }
            #endif
            AnalyticsManager.shared.track(.trainingSessionCompleted, playerId: playerStore.selectedPlayerId)
            guard !didSave else {
                #if DEBUG
                print("[PBA-Debug] Block summary onAppear: skipped (didSave already true)")
                #endif
                return
            }
            let playerId = playerStore.selectedPlayerId
            #if DEBUG
            print("[PBA-Debug] Block completed (AFP). decisionSpeedScoreValue=\(decisionSpeedScoreValue ?? -1), activity=awayFromPressure, playerId=\(playerId?.uuidString ?? "nil"), correct=\(correctCount), decisionsCompleted=\(logs.count)")
            #endif
            guard let sessionId = CurrentSessionStore.shared.sessionId else {
                let record = SessionRecord(
                    id: UUID(),
                    date: Date(),
                    activity: .awayFromPressure,
                    gridSize: .fiveByFive,
                    difficulty: config.difficulty,
                    reps: 12,
                    decisionsCompleted: logs.count,
                    correct: correctCount,
                    forwardCorrect: nil,
                    speedBucket: speedBucket,
                    bias: biasString,
                    avgLatency: avgLatency,
                    profile: nil,
                    playerId: playerId,
                    decisionSpeedScore: decisionSpeedScoreValue
                )
                #if DEBUG
                print("[PBA-Debug] SessionRecord created (no sessionId). activity=\(record.activity.rawValue), decisionSpeedScore=\(record.decisionSpeedScore ?? -1), playerId=\(record.playerId?.uuidString ?? "nil"), correct=\(record.correct)/\(record.decisionsCompleted)")
                let savedScore = record.decisionSpeedScore.map(String.init) ?? "nil"
                print("[PBA-Debug] Saved session score: \(savedScore)")
                print("[PBA-Debug] Player ID match: \(record.playerId == playerId)")
                #endif
                previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
                let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
                progressStore.add(record)
                #if DEBUG
                print("[PBA-Debug] progressStore.add(record) called. sessions count after add=\(progressStore.sessions.count)")
                #endif
                personalBestScore = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
                isNewPersonalBestForDecisionSpeed = (decisionSpeedScoreValue ?? 0) > (previousBest ?? -1)
                didSave = true
                return
            }
            let record = SessionRecord(
                id: sessionId,
                date: Date(),
                activity: .awayFromPressure,
                gridSize: .fiveByFive,
                difficulty: config.difficulty,
                reps: 12,
                decisionsCompleted: logs.count,
                correct: correctCount,
                forwardCorrect: nil,
                speedBucket: speedBucket,
                bias: biasString,
                avgLatency: avgLatency,
                profile: nil,
                playerId: playerId,
                decisionSpeedScore: decisionSpeedScoreValue
            )
            #if DEBUG
            print("[PBA-Debug] SessionRecord created (with sessionId). activity=\(record.activity.rawValue), decisionSpeedScore=\(record.decisionSpeedScore ?? -1), playerId=\(record.playerId?.uuidString ?? "nil"), correct=\(record.correct)/\(record.decisionsCompleted)")
            let savedScore = record.decisionSpeedScore.map(String.init) ?? "nil"
            print("[PBA-Debug] Saved session score: \(savedScore)")
            print("[PBA-Debug] Player ID match: \(record.playerId == playerId)")
            #endif
            previousSessionForComparison = progressStore.last(record.activity, playerId: record.playerId)
            let previousBest = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            progressStore.add(record)
            #if DEBUG
            print("[PBA-Debug] progressStore.add(record) called (with sessionId). save success. sessions count after add=\(progressStore.sessions.count)")
            #endif
            personalBestScore = progressStore.bestDecisionSpeedScore(activity: record.activity, playerId: record.playerId)
            isNewPersonalBestForDecisionSpeed = (decisionSpeedScoreValue ?? 0) > (previousBest ?? -1)
            let decisions = logs.map { TrainingDecisionRecord.from($0) }
            SupabaseSessionService.shared.saveSession(record: record, decisions: decisions) {
                progressStore.markSynced(id: record.id)
            }
            let activityName = record.activity.rawValue
            for log in logs {
                guard let sec = log.decisionTimeSeconds else { continue }
                let reactionTimeMs = Int(sec * 1000)
                if reactionTimeMs > SupabaseDecisionService.maxReactionTimeMs { continue }
                let decision = Decision(
                    sessionId: sessionId,
                    playerId: record.playerId ?? playerId,
                    activityName: activityName,
                    stimulusType: "defender",
                    decisionDirection: log.exitedGate?.rawValue ?? "incorrect",
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
                earlySessionStreakForSummary = EarlySessionStreakStore.current(for: result.playerID)
                let bestEarly = BestEarlyStreakStore.recordIfNewBest(maxConsecutiveEarlyRepStreak, playerId: result.playerID)
                earlyRepBestStreakForSummary = bestEarly > 0 ? bestEarly : nil
                if trainingMode != .solo {
                    sessionResultForSummary = result
                }
            }
            didSave = true
        }
        .navigationDestination(isPresented: $navigateToNewBlock) {
            AwayFromPressureDisplaySessionView(config: config, mode: trainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
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
        .navigationDestination(isPresented: $navigateToTwoMinute) {
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
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

    private var blockSummaryContent: some View { partnerBlockSummaryFullContent }

    private var partnerBlockSummaryFullContent: some View {
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

                    Text("Correct first decisions: \(correctCount)/12")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    VStack(spacing: 4) {
                        Text("Decision speed: \(speedBucket.rawValue.capitalized)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        BlockSummarySpeedCountsSubline(
                            fast: speedCounts.fast,
                            medium: speedCounts.medium,
                            slow: speedCounts.slow,
                            debugActivity: .awayFromPressure
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
                        HStack {
                            Text("Correct decisions")
                            Spacer()
                            Text("\(correctCount)/12")
                        }
                        HStack {
                            Text("Avg latency")
                            Spacer()
                            Text(avgLatencyString)
                        }
                        HStack(alignment: .top) {
                            Text("Speed")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(speedBucket.rawValue.capitalized)
                                BlockSummarySpeedCountsSubline(
                                    fast: speedCounts.fast,
                                    medium: speedCounts.medium,
                                    slow: speedCounts.slow,
                                    foregroundColor: .white.opacity(0.5)
                                )
                            }
                        }
                        HStack {
                            Text("Bias")
                            Spacer()
                            Text(biasString)
                        }
                        if repsWithFirstTouchLogged >= 3 {
                            HStack {
                                Text("Late corrections")
                                Spacer()
                                Text("\(lateCorrectionsCount)")
                            }
                        }
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
                            HStack {
                                Text("Correct decisions")
                                Spacer()
                                Text("\(correctCount)/12")
                            }
                            HStack {
                                Text("Avg latency")
                                Spacer()
                                Text(avgLatencyString)
                            }
                            HStack(alignment: .top) {
                                Text("Speed")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(speedBucket.rawValue.capitalized)
                                    BlockSummarySpeedCountsSubline(
                                        fast: speedCounts.fast,
                                        medium: speedCounts.medium,
                                        slow: speedCounts.slow,
                                        foregroundColor: .white.opacity(0.5)
                                    )
                                }
                            }
                            HStack {
                                Text("Bias")
                                Spacer()
                                Text(biasString)
                            }
                            if repsWithFirstTouchLogged >= 3 {
                                HStack {
                                    Text("Late corrections")
                                    Spacer()
                                    Text("\(lateCorrectionsCount)")
                                }
                            }
                        }
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.75))
                    }

                    VStack(spacing: 12) {
                        Button {
                            navigateToNewBlock = true
                        } label: {
                            Text("Continue Training")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.yellow)
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text(retestMessage)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Button { navigateToCurriculum = true } label: {
                            Text("Back to Curriculum")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button {
                            navigateToTwoMinute = true
                        } label: {
                            Text("Re-Test 2-Minute Challenge")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button {
                            navigateToProgress = true
                        } label: {
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

    /// Pops back to Home/Progress when user taps "Back to Home" (RoleSelection → Setup → GetReady → Session → BlockSummary = 5 levels).
    private func popToRootFromBlockSummary() {
        let levels = 5
        for i in 0..<levels {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 * Double(i)) {
                dismiss()
            }
        }
    }
}
