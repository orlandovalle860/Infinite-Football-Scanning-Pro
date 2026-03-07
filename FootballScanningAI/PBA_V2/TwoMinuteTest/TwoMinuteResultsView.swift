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

    private var earlyDecisions: Int { logs.filter(\.correct).count }
    private var forwardCorrect: Int { logs.filter { $0.starGate == .up && $0.correct }.count }
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
    /// Average latency (passTriggered -> exitLogged) in seconds; nil if none.
    private var avgLatency: Double? {
        let withPass = logs.compactMap { log -> Double? in
            guard let pt = log.passTriggeredAt else { return nil }
            return log.exitLoggedAt.timeIntervalSince(pt)
        }
        guard !withPass.isEmpty else { return nil }
        return withPass.reduce(0, +) / Double(withPass.count)
    }
    /// Speed bucket for SessionRecord: fast < 1.2, medium 1.2–1.8, slow > 1.8.
    private var speedBucket: SpeedBucket {
        guard let avg = avgLatency else { return .medium }
        if avg < 1.2 { return .fast }
        if avg <= 1.8 { return .medium }
        return .slow
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
    private var decisionSpeed: String {
        let counts = twoMinuteSpeedCounts
        if counts.fast >= counts.medium && counts.fast >= counts.slow { return "Fast" }
        if counts.slow >= counts.fast && counts.slow >= counts.medium { return "Slow" }
        return "Medium"
    }

    private var twoMinuteSpeedCounts: SessionSpeedCounts {
        var fast = 0, medium = 0, slow = 0
        for log in logs {
            let t = log.exitLoggedAt.timeIntervalSince(log.passTriggeredAt ?? log.infoShownAt)
            if t < 1.5 { fast += 1 }
            else if t < 3.0 { medium += 1 }
            else { slow += 1 }
        }
        return SessionSpeedCounts(fast: fast, medium: medium, slow: slow)
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
    private var profileHeadline: String {
        switch evaluatedProfile {
        case .latePlanner: return "You're a step behind the game."
        case .predictable: return "You're becoming readable."
        case .safePlayer: return "You choose safe over sharp."
        case .gameReady: return "Good. Now raise the standard."
        }
    }
    private var profileSubline: String {
        switch evaluatedProfile {
        case .latePlanner: return "The window closes before your first touch."
        case .predictable: return "Pressure sees your body shape early."
        case .safePlayer: return "The forward option is there — take it."
        case .gameReady: return "Do it under pressure — not just in space."
        }
    }
    private var profileCTALine: String {
        switch evaluatedProfile {
        case .latePlanner: return "Train turning away from pressure at match speed."
        case .predictable: return "Train escaping pressure from both sides."
        case .safePlayer: return "Train turning forward under pressure."
        case .gameReady: return "Train at higher speed."
        }
    }

    var body: some View {
        Group {
            if let s = sessionResultForSummary {
                SessionSummaryView(session: s, playerName: profileManager.currentProfile?.name ?? playerStore.selectedPlayer?.name ?? "Player", isNewPersonalBest: isNewPersonalBestForSummary, profileManager: profileManager, settingsViewModel: settingsViewModel)
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
            let record = SessionRecord(
                id: UUID(),
                date: Date(),
                activity: .twoMinuteTest,
                gridSize: .fiveByFive,
                difficulty: difficulty,
                reps: 10,
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
                profileManager.addSessionResult(result)
                sessionResultForSummary = result
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

    private var resultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your current profile:")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text(evaluatedProfile.rawValue)
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text(profileHeadline)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Text(profileSubline)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Text(profileCTALine)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 2)

                Text("Your Receiving Profile")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(.top, 16)

                resultRow("Early decisions", "\(earlyDecisions) / 10")
                resultRow("Forward decisions", "\(forwardCorrect) / \(forwardTotal)")
                resultRow("Strong side tendency", strongSideTendency)
                resultRow("Decision speed", decisionSpeed)

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
                    if !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest") {
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
                        if !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest") {
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
                        if !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest") {
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
                        if !UserDefaults.standard.bool(forKey: "hasCompletedInitialTest") {
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
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
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
