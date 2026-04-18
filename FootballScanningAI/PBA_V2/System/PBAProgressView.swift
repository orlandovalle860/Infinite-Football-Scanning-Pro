//
//  PBAProgressView.swift
//  FootballScanningAI
//
//  PBA V2 — Progress screen (named PBAProgressView to avoid conflict with SwiftUI.ProgressView).
//

import SwiftUI

struct PBAProgressView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showPlayerSwitcher = false
    @State private var navigateToAwayFromPressure = false
    @State private var navigateToTwoMinuteTest = false
    @State private var navigateToDribbleOrPass = false
    @State private var navigateToDevelopmentSnapshot = false
    @State private var selectedSessionResult: SessionResult?

    private var selectedPlayerId: UUID? { playerStore.selectedPlayerId }
    private var sessionHistory: [SessionResult] {
        profileManager.currentProfile?.sessionResults ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Progress")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            navigateToDevelopmentSnapshot = true
                        } label: {
                            Text("Development Snapshot")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Text(playerStore.selectedPlayer?.name ?? "Player 1")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Button("Switch") {
                            showPlayerSwitcher = true
                        }
                        .font(.footnote)
                        .foregroundColor(.yellow)
                    }
                }

                section2MinuteTest
                sectionAwayFromPressure
                sectionDribbleOrPass
                sectionSessionHistory
                recommendedNextCard
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .navigationDestination(isPresented: $navigateToAwayFromPressure) {
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToTwoMinuteTest) {
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToDribbleOrPass) {
            DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .navigationDestination(isPresented: $navigateToDevelopmentSnapshot) {
            PlayerDevelopmentSnapshotView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .sheet(isPresented: $showPlayerSwitcher) {
            playerSwitcherSheet
        }
        .navigationDestination(item: $selectedSessionResult) { session in
            SessionSummaryScreenView(session: session, playerName: profileManager.currentProfile?.name ?? "Player", profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private var playerSwitcherSheet: some View {
        NavigationStack {
            List {
                ForEach(playerStore.players) { p in
                    Button {
                        playerStore.selectPlayer(id: p.id)
                        showPlayerSwitcher = false
                    } label: {
                        HStack {
                            Text(p.name)
                                .foregroundColor(.white)
                            if p.id == playerStore.selectedPlayerId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                }
                Button {
                    playerStore.addPlayer(name: "")
                    showPlayerSwitcher = false
                } label: {
                    Label("Add Player", systemImage: "plus.circle")
                        .foregroundColor(.yellow)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12))
            .navigationTitle("Switch Player")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var last2AwayFromPressure: [SessionRecord] {
        progressStore.lastN(.awayFromPressure, n: 2, playerId: selectedPlayerId)
    }
    private var last2AwayFromPressureStrong: Bool {
        last2AwayFromPressure.count == 2 &&
        last2AwayFromPressure.allSatisfy { $0.correct >= 9 && $0.speedBucket == .fast }
    }
    private var retestReadinessMessage: String {
        last2AwayFromPressureStrong ? "You're ready to re-test." : "Recommended after 2 strong blocks."
    }

    private var section2MinuteTest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2-Minute Test")
                .font(.headline)
                .foregroundColor(.white)
            if let last = progressStore.last(.twoMinuteTest, playerId: selectedPlayerId) {
                let profileStr = last.profile?.rawValue ?? "—"
                Text("Last: \(last.date.formatted(date: .abbreviated, time: .shortened)) — \(last.correct)/10 — \(last.speedBucket?.rawValue ?? "—") — \(profileStr)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
            if let best = progressStore.bestTwoMinuteTest(playerId: selectedPlayerId) {
                Text("Best: \(best.correct)/10 — \(best.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
            let last3 = progressStore.lastN(.twoMinuteTest, n: 3, playerId: selectedPlayerId)
            if !last3.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last 3")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    ForEach(last3) { s in
                        let profileStr = s.profile?.rawValue ?? "—"
                        Text("\(s.date.formatted(date: .abbreviated, time: .omitted)) — \(s.correct)/10 — \(profileStr)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                profileTrendLine(last3: last3)
            }
            if progressStore.last(.twoMinuteTest, playerId: selectedPlayerId) == nil {
                Text("No sessions yet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            Text(retestReadinessMessage)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)

            Button {
                navigateToTwoMinuteTest = true
            } label: {
                Text("Re-Test 2-Minute Challenge")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func profileTrendLine(last3: [SessionRecord]) -> some View {
        let profiles = last3.compactMap(\.profile)
        if profiles.isEmpty {
            EmptyView()
        } else {
            let allSame = profiles.count >= 2 && profiles.dropFirst().allSatisfy { $0 == profiles[0] }
            let label = profiles.first?.rawValue ?? "—"
            if allSame {
                Text("Profile: Stable — \(label)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Text("Profile: Changing — \(label)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var sectionAwayFromPressure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playing Away From Pressure")
                .font(.headline)
                .foregroundColor(.white)
            let last3 = progressStore.lastN(.awayFromPressure, n: 3, playerId: selectedPlayerId)
            if !last3.isEmpty {
                ForEach(last3) { s in
                    Text("\(s.date.formatted(date: .abbreviated, time: .omitted)) — \(s.correct)/12 — \(s.speedBucket?.rawValue ?? "—")")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
            } else {
                Text("No blocks yet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            if progressStore.last(.twoMinuteTest, playerId: selectedPlayerId) != nil {
                Button {
                    navigateToAwayFromPressure = true
                } label: {
                    Text("Start training")
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    private var sectionDribbleOrPass: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dribble or Pass")
                .font(.headline)
                .foregroundColor(.white)
            let last3 = progressStore.lastN(.dribbleOrPass, n: 3, playerId: selectedPlayerId)
            if !last3.isEmpty {
                ForEach(last3) { s in
                    Text("\(s.date.formatted(date: .abbreviated, time: .omitted)) — \(s.correct)/12 — \(s.speedBucket?.rawValue ?? "—")")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
            } else {
                Text("No blocks yet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            Button {
                navigateToDribbleOrPass = true
            } label: {
                Text("Start Dribble or Pass")
                    .font(.subheadline)
                    .foregroundColor(.yellow)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    private var sectionSessionHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session History")
                .font(.headline)
                .foregroundColor(.white)
            if sessionHistory.isEmpty {
                Text("No session summaries yet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                VStack(spacing: 0) {
                    ForEach(sessionHistory.prefix(20)) { session in
                        Button {
                            selectedSessionResult = session
                        } label: {
                            HStack {
                                Text(activityDisplayName(session.activityType))
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Text("•")
                                    .foregroundColor(.white.opacity(0.5))
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                Text("•")
                                    .foregroundColor(.white.opacity(0.5))
                                Text("\(session.correctCount)/\(session.totalReps)")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("•")
                                    .foregroundColor(.white.opacity(0.5))
                                Text(sessionSpeedLabel(session))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func activityDisplayName(_ kind: ActivityKind) -> String {
        switch kind {
        case .twoMinuteTest: return "2-Minute Test"
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        }
    }

    private func sessionSpeedLabel(_ session: SessionResult) -> String {
        let c = session.speedCounts
        return UniversalBlockSummaryHeadline.headlineLabel(fast: c.fast, medium: c.medium, slow: c.slow)
    }

    private var last5Training: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: selectedPlayerId) }
    private var lastAFPSessionResult: SessionResult? {
        profileManager.recentTrainSessions(limit: 20).first { $0.activityType == .awayFromPressure }
    }
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    private var decisionConsistencyForRecommendation: DecisionConsistencyLabel? {
        guard let profile = profileManager.currentProfile else { return nil }
        let sessions = profile.sessionResults.sorted { $0.date > $1.date }
        return DecisionConsistencyLabel.from(session: sessions.first)
    }

    private var trainingRecommendation: TrainingRecommendationResult {
        TrainingRecommendation.recommend(progressStore: progressStore, playerId: selectedPlayerId, last5: last5Training, hasCompletedInitialTest: hasCompletedInitialTest, lastAFPSessionResult: lastAFPSessionResult, decisionConsistency: decisionConsistencyForRecommendation)
    }

    @ViewBuilder
    private var recommendedNextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended next")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Text(RecommendationEngine.activityTitle(trainingRecommendation.activity))
                .font(.subheadline.bold())
                .foregroundColor(.white)
            Text("Focus: \(trainingRecommendation.focusLine)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Text("Coach Tip: \(trainingRecommendation.coachTip)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}
