//
//  TimedSessionSummaryProgressView.swift
//  FootballScanningAI
//
//  Unified summary + progress surface with top segmented control.
//

import SwiftUI

struct TimedSessionSummaryProgressView: View {
    enum Tab: Hashable {
        case session
        case progress
    }

    let totalRepCount: Int
    let durationText: String
    let completionType: SessionCompletionType
    let isFreeMode: Bool
    let mode: TrainingMode
    let activityRepCounts: [String: Int]
    let onTrainAgain: () -> Void
    let onDone: () -> Void

    @State private var selectedTab: Tab = .session
    @ObservedObject private var activityStats = ActivityStatsStore.shared

    private var shouldHighlightProgress: Bool {
        activityStats.sessionsToday >= 2
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .session:
                    TimedSessionSummaryView(
                        totalRepCount: totalRepCount,
                        durationText: durationText,
                        completionType: completionType,
                        isFreeMode: isFreeMode,
                        mode: mode,
                        activityRepCounts: activityRepCounts,
                        onTrainAgain: onTrainAgain,
                        onDone: onDone
                    )
                case .progress:
                    ActivityProgressPanelView(showTitle: false)
                }
            }
            .padding(.top, 52)
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                Picker("", selection: $selectedTab) {
                    Text("Session").tag(Tab.session)
                    Text("Progress").tag(Tab.progress)
                }
                .pickerStyle(.segmented)

                if shouldHighlightProgress && selectedTab == .session {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(Color.black.opacity(0.16))
        }
    }
}
