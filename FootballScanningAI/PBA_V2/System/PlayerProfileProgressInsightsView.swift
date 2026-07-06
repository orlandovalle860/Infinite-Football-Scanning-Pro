//
//  PlayerProfileProgressInsightsView.swift
//  FootballScanningAI
//
//  Profile, progress, curriculum, and insights — moved off the training-first home screen.
//

import SwiftUI

struct PlayerProfileProgressInsightsView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var router: AppRouter

    @State private var guidedProgress = GuidedCurriculumProgress(
        stage: 1,
        loop: 1,
        nextActivity: .awayFromPressure,
        focus: "Decide away from pressure quickly — your first decision is what we score."
    )

    private var playerId: UUID? { playerStore.selectedPlayerId }

    private var playerIdentity: PlayerIdentity? {
        guard let id = playerId else { return nil }
        return PlayerIdentityEngine.loadLastIdentity(playerId: id)
    }

    private var coachInsightBody: String {
        let sessions = profileManager.profile(id: playerId)?.sessionResults ?? []
        let trainingSessions = sessions.filter {
            [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType)
        }
        guard let latest = trainingSessions.first else {
            return "Complete your next block to unlock a personalized coaching insight."
        }
        let previousRecord: SessionRecord? = {
            guard trainingSessions.count >= 2 else { return nil }
            return sessionRecord(from: trainingSessions[1])
        }()
        return CoachInsightGenerator.coachInsight(for: latest, previous: previousRecord)
    }

    private func sessionRecord(from session: SessionResult) -> SessionRecord {
        let speedBucket = UniversalBlockSummaryHeadline.resolve(
            fast: session.speedCounts.fast,
            medium: session.speedCounts.medium,
            slow: session.speedCounts.slow
        ).bucket
        return SessionRecord(
            id: session.id,
            date: session.date,
            activity: session.activityType,
            gridSize: .fiveByFive,
            difficulty: session.difficulty ?? .standard,
            reps: session.totalReps,
            decisionsCompleted: session.totalReps,
            correct: session.correctCount,
            forwardCorrect: session.forwardChoiceCount,
            speedBucket: speedBucket,
            bias: session.biasDirection?.userFacingName,
            avgLatency: session.avgDecisionTime,
            profile: nil,
            playerId: session.playerID,
            decisionSpeedScore: session.estimatedDecisionSpeedScore
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                if let identity = playerIdentity {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(identity.emojiTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(identity.shortDescription)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.78))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(StartPageCardStyle())
                }

                insightPreviewCard(
                    title: "Current Focus",
                    body: "\(RecommendationEngine.activityTitle(guidedProgress.nextActivity)) — \(guidedProgress.focus)",
                    actionTitle: "View full path",
                    route: .curriculum
                )

                insightPreviewCard(
                    title: "Correct First-Decision Trend",
                    body: "Decision window trends and session history.",
                    actionTitle: "Open progress",
                    route: .progress
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Coach Insight")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(coachInsightBody)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("View full report") {
                        router.push(.progress)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.yellow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(StartPageCardStyle())

                insightPreviewCard(
                    title: "Your Path",
                    body: "Stage \(guidedProgress.stage) · Loop \(guidedProgress.loop)",
                    actionTitle: "View curriculum",
                    route: .curriculum
                )

                hubRow(title: "Achievements", subtitle: "Earned and locked badges") {
                    router.push(.achievements)
                }
                .modifier(StartPageCardStyle())

#if DEBUG
                hubRow(title: "Reset curriculum", subtitle: "Debug: clear guided stage for selected player") {
                    resetCurriculumForSelectedPlayer()
                }
                .modifier(StartPageCardStyle())
#endif

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Profile & Insights")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshGuidedProgress() }
        .onChange(of: playerStore.selectedPlayerId) { _, _ in refreshGuidedProgress() }
    }

    private func insightPreviewCard(title: String, body: String, actionTitle: String, route: AppRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text(body)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle) {
                router.push(route)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.yellow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(StartPageCardStyle())
    }

    private func hubRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func refreshGuidedProgress() {
        let sessions = profileManager.profile(id: playerId)?.sessionResults ?? []
        guidedProgress = GuidedCurriculumEngine.evaluateAndAdvance(
            playerId: playerId,
            sessions: sessions
        )
    }

#if DEBUG
    private func resetCurriculumForSelectedPlayer() {
        guidedProgress = GuidedCurriculumEngine.resetCurriculumForPlayer(
            playerId: playerId,
            baselineCompleted: false
        )
        refreshGuidedProgress()
    }
#endif
}
