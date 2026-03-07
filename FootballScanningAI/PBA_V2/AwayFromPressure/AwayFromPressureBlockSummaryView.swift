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
    @State private var navigateToTwoMinute = false
    @State private var navigateToProgress = false
    @State private var sessionResultForSummary: SessionResult?
    @State private var isNewPersonalBestForSummary = false

    private var correctCount: Int { logs.filter(\.correct).count }

    private var performanceLabel: String {
        if correctCount >= 10 { return "Strong block" }
        if correctCount >= 8 { return "Solid block" }
        return "Needs work"
    }

    private var coachMessage: String {
        if correctCount >= 10 {
            return "Good. You escaped pressure consistently. Keep the standard."
        } else if correctCount >= 8 {
            return "You're getting out. Now make the decision earlier."
        } else {
            return "You're reacting to pressure. Commit to the escape earlier."
        }
    }

    private var avgLatencyString: String {
        avgLatency.map { String(format: "%.2fs", $0) } ?? "—"
    }
    private var repsWithFirstTouchLogged: Int { logs.filter { $0.firstTouchGate != nil }.count }
    private var lateCorrectionsCount: Int { logs.filter(\.lateCorrection).count }
    /// Per-rep decision time: first-touch timing when logged, else exit timing (fallback).
    private var avgLatency: Double? {
        let times = logs.compactMap(\.decisionTimeSeconds)
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }
    private var speedBucket: SpeedBucket {
        guard let avg = avgLatency else { return .medium }
        return TimingThresholds.pressureSpeedBucket(for: avg)
    }
    private var biasString: String {
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for log in logs { c[log.exitedGate, default: 0] += 1 }
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
        for log in logs {
            guard let t = log.decisionTimeSeconds else { continue }
            let bucket = TimingThresholds.pressureSpeedBucket(for: t)
            switch bucket {
            case .fast: f += 1
            case .medium: m += 1
            case .slow: s += 1
            }
        }
        return SessionSpeedCounts(fast: f, medium: m, slow: s)
    }

    private var directionCounts: [Gate: Int] {
        var c: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for log in logs { c[log.exitedGate, default: 0] += 1 }
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

    private var sessionResult: SessionResult? {
        guard let playerId = profileManager.currentProfile?.id ?? playerStore.selectedPlayerId else { return nil }
        return SessionResult(
            playerID: playerId,
            activityType: .awayFromPressure,
            correctCount: correctCount,
            totalReps: 12,
            speedCounts: speedCounts,
            avgDecisionTime: avgLatency,
            biasDirection: biasGate,
            directionCounts: directionCounts,
            firstTouchCounts: firstTouchCountsFromLogs,
            firstTouchMatchCount: firstTouchMatchCountFromLogs,
            firstTouchTowardPressureCount: firstTouchTowardPressureCountFromLogs,
            firstTouchHesitantCount: firstTouchHesitantCountFromLogs,
            lateAdjustments: repsWithFirstTouchLogged >= 3 ? lateCorrectionsCount : nil,
            difficulty: config.difficulty,
            preReceiveDecisionCount: preReceiveDecisionCountFromLogs
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
            return CoachInsightGenerator.coachInsight(for: s)
        }
        return coachMessage
    }

    var body: some View {
        Group {
            if showSessionFeedback {
                TrainingCompleteFeedbackView(
                    activityName: "Playing Away From Pressure",
                    correct: correctCount,
                    total: 12,
                    firstTouchAccuracy: repsWithFirstTouchLogged >= 3 ? "\(firstTouchMatchCountFromLogs ?? 0)/12" : nil,
                    decisionSpeedLabel: decisionSpeedComparisonLabel(current: speedBucket, previous: previousBlockSpeedBucket),
                    avgDecisionTimeSeconds: avgLatency,
                    coachFeedback: sessionFeedbackCoachSentence,
                    onContinue: { showSessionFeedback = false }
                )
            } else if let s = sessionResultForSummary {
                SessionSummaryView(
                    session: s,
                    playerName: profileManager.currentProfile?.name ?? "Player",
                    isNewPersonalBest: isNewPersonalBestForSummary,
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
            guard !didSave else { return }
            let record = SessionRecord(
                id: UUID(),
                date: Date(),
                activity: .awayFromPressure,
                gridSize: .fiveByFive,
                difficulty: config.difficulty,
                reps: 12,
                correct: correctCount,
                forwardCorrect: nil,
                speedBucket: speedBucket,
                bias: biasString,
                avgLatency: avgLatency,
                profile: nil,
                playerId: playerStore.selectedPlayerId
            )
            progressStore.add(record)
            if let result = sessionResult {
                isNewPersonalBestForSummary = profileManager.wouldBeNewPersonalBest(session: result)
                profileManager.addSessionResult(result)
                sessionResultForSummary = result
            }
            didSave = true
        }
        .navigationDestination(isPresented: $navigateToNewBlock) {
            AwayFromPressureGetReadyView(config: config, mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToCurriculum) {
            PBACurriculumView(settingsViewModel: settingsViewModel, profileManager: profileManager)
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

                    Text("Escapes: \(correctCount)/12")
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
                        HStack {
                            Text("Escapes")
                            Spacer()
                            Text("\(correctCount)/12")
                        }
                        HStack {
                            Text("Avg latency")
                            Spacer()
                            Text(avgLatencyString)
                        }
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(speedBucket.rawValue.capitalized)
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
