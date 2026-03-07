//
//  SessionSummaryView.swift
//  FootballScanningAI
//
//  PBA V2 — SCREEN 11 SESSION SUMMARY. Train Another → same activity. Back to Home → HomeDashboardView. Share Report → sheet.
//

import SwiftUI

private func activityDisplayName(_ kind: ActivityKind) -> String {
    switch kind {
    case .twoMinuteTest: return "2-Minute Test"
    case .awayFromPressure: return "Playing Away From Pressure"
    case .dribbleOrPass: return "Dribble or Pass"
    case .oneTouchPassing: return "One-Touch Passing"
    }
}

private func biasLabel(_ gate: Gate?) -> String {
    guard let g = gate else { return "none" }
    switch g {
    case .up: return "Up"
    case .down: return "Down"
    case .left: return "Left"
    case .right: return "Right"
    }
}

struct SessionSummaryView: View {
    let session: SessionResult
    let playerName: String
    /// When true, show "New Personal Best" badge (set when this session just beat the previous best).
    var isNewPersonalBest: Bool = false
    /// When set (e.g. from block summary), "Back to Home" calls this to pop to Progress instead of one level.
    var onBackToHome: (() -> Void)? = nil
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var shareReportItems: [Any] = []
    @State private var navigateToTrainAnother = false

    private var activityName: String { activityDisplayName(session.activityType) }
    private var coachInsightText: String { CoachInsightGenerator.coachInsight(for: session) }
    private var personalBest: ActivityBest? {
        profileManager.currentProfile?.personalBests[session.activityType]
            ?? profileManager.profiles.first(where: { $0.id == session.playerID })?.personalBests[session.activityType]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Session Summary")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("\(playerName) • \(activityName)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                correctCard
                if session.activityType == .awayFromPressure {
                    pressureEscapesCard
                }
                if isNewPersonalBest {
                    Text("New Personal Best")
                        .foregroundColor(.yellow)
                        .font(.headline)
                }
                personalBestCard
                decisionSpeedCard
                biasCard
                firstTouchCard
                coachInsightCard

                buttonsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareReportItems)
        }
        .navigationDestination(isPresented: $navigateToTrainAnother) {
            trainAnotherDestination
        }
    }

    private var correctCard: some View {
        card {
            VStack(spacing: 8) {
                Text("\(session.correctCount) / \(session.totalReps)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Correct Decisions")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Pressure Escapes: reps where the player successfully escaped (correct direction + exited that gate). AFP only.
    private var pressureEscapesCard: some View {
        card {
            VStack(spacing: 8) {
                Text("\(session.correctCount) / \(session.totalReps)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Pressure Escapes")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var personalBestCard: some View {
        card {
            VStack(spacing: 8) {
                Text("Personal Best")
                    .font(.headline)
                    .foregroundColor(.white)
                if let best = personalBest {
                    Text("\(best.bestCorrect) / \(best.bestTotal)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                } else {
                    Text("First session recorded")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var decisionSpeedCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Decision Speed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                HStack(spacing: 12) {
                    pill("Fast", value: session.speedCounts.fast)
                    pill("Medium", value: session.speedCounts.medium)
                    pill("Slow", value: session.speedCounts.slow)
                }
                Text("Goal: more Fast, fewer Slow")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func pill(_ label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12))
        .cornerRadius(20)
    }

    private var biasCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                if let bias = session.biasDirection {
                    Text("Bias: favors \(biasLabel(bias))")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text("Scan the whole field before receiving.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text("Good: using the whole field.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }

    private var firstTouchCard: some View {
        Group {
            if session.firstTouchCounts != nil || session.firstTouchMatchCount != nil || session.lateAdjustments != nil {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        if session.firstTouchMatchCount != nil || session.firstTouchCounts != nil {
                            Text("First Touch Accuracy: \(session.firstTouchMatchCount ?? 0) / \(session.totalReps)")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        if let late = session.lateAdjustments {
                            Text("Late Adjustments: \(late)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
            }
        }
    }

    private var coachInsightCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Coach Insight")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)
                Text(coachInsightText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttonsSection: some View {
        VStack(spacing: 12) {
            Button {
                navigateToTrainAnother = true
            } label: {
                Text("Train Another Block")
                    .font(.headline)
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
                Text("Back to Home")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                var items: [Any] = []
                if let image = SessionReportExporter.exportImage(session: session, playerName: playerName) {
                    items.append(image)
                }
                if let pdfURL = SessionReportExporter.exportPDF(session: session, playerName: playerName) {
                    items.append(pdfURL)
                }
                if items.isEmpty {
                    items.append(shareText)
                }
                shareReportItems = items
                showShare = !items.isEmpty
            } label: {
                Text("Share Report")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 8)
    }

    private var shareText: String {
        var lines: [String] = [
            "\(playerName) — Session Summary",
            activityName,
            "Correct: \(session.correctCount)/\(session.totalReps)",
            "Speed: Fast \(session.speedCounts.fast) / Med \(session.speedCounts.medium) / Slow \(session.speedCounts.slow)",
            "Bias: \(session.biasDirection != nil ? biasLabel(session.biasDirection) : "none")",
            "Coach Insight: \(coachInsightText)"
        ]
        if let avg = session.avgDecisionTime {
            lines.insert("Avg decision time: \(String(format: "%.2f", avg))s", at: 4)
        }
        if session.firstTouchMatchCount != nil || session.firstTouchCounts != nil {
            lines.insert("First Touch Accuracy: \(session.firstTouchMatchCount ?? 0)/\(session.totalReps)", at: lines.count - 1)
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var trainAnotherDestination: some View {
        switch session.activityType {
        case .twoMinuteTest:
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .awayFromPressure:
            AwayFromPressureGetReadyView(config: AwayFromPressureConfig.config(for: session.difficulty ?? .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .dribbleOrPass:
            DribbleOrPassGetReadyView(config: DribbleOrPassConfig.defaultConfig(for: session.difficulty ?? .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .oneTouchPassing:
            OneTouchPassingGetReadyView(config: OneTouchPassingConfig.defaultConfig(for: session.difficulty ?? .standard), mode: .partner, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        SessionSummaryView(
            session: SessionResult(
                playerID: UUID(),
                activityType: .awayFromPressure,
                correctCount: 9,
                totalReps: 12,
                speedCounts: SessionSpeedCounts(fast: 4, medium: 5, slow: 3),
                avgDecisionTime: 1.4,
                biasDirection: .left,
                directionCounts: [.left: 5, .right: 3, .up: 2, .down: 2],
                difficulty: .standard
            ),
            playerName: "Orlando",
            profileManager: UserProfileManager(),
            settingsViewModel: SettingsViewModel()
        )
        .environmentObject(ProgressStore())
        .environmentObject(PlayerStore())
        .environmentObject(PopToRootTrigger())
        .environmentObject(AppRouter())
    }
}
