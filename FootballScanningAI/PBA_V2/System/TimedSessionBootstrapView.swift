//
//  TimedSessionBootstrapView.swift
//  FootballScanningAI
//
//  Single entry for solo + partner timed training: duration picker, then timed session container.
//

import SwiftUI

struct TimedSessionBootstrapView: View {
    let activity: ActivityKind
    let trainingMode: TrainingMode

    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject private var timedSession = TimedSessionController.shared

    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if timedSession.durationChoice == nil {
                SoloSessionDurationSelectionView(activity: activity, trainingMode: trainingMode)
            } else {
                TimedSessionContainerView(
                    initialActivity: activity,
                    trainingMode: trainingMode,
                    settingsViewModel: settingsViewModel,
                    profileManager: profileManager
                )
            }
        }
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
        .safeAreaInset(edge: .top, spacing: 0) {
            VisionPlayBrandingView(style: .sessionChrome)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .background(Color.black.opacity(0.001))
        }
    }
}
