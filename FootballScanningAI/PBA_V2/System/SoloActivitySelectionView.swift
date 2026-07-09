//
//  SoloActivitySelectionView.swift
//  FootballScanningAI
//
//  Solo mode: pick an activity before starting a session.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct SoloActivitySelectionView: View {
    @EnvironmentObject private var router: AppRouter

    @State private var selectedActivity: ActivityKind = .twoMinuteTest

    private struct ActivityOption: Identifiable {
        let activity: ActivityKind
        let title: String
        var id: ActivityKind { activity }
    }

    private let options: [ActivityOption] = [
        ActivityOption(activity: .twoMinuteTest, title: ActivityKind.twoMinuteTest.displayName),
        ActivityOption(activity: .awayFromPressure, title: ActivityKind.awayFromPressure.displayName),
        ActivityOption(activity: .dribbleOrPass, title: ActivityKind.dribbleOrPass.displayName),
        ActivityOption(activity: .oneTouchPassing, title: ActivityKind.oneTouchPassing.displayName)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ResponsiveScrollScreen {
                VStack(spacing: 32) {
                    Text("Choose Activity")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    VStack(spacing: 24) {
                        ForEach(options) { option in
                            Button {
                                selectedActivity = option.activity
                            } label: {
                                Text(option.title)
                                    .font(.system(size: 20, weight: selectedActivity == option.activity ? .bold : .regular))
                                    .foregroundColor(.white.opacity(selectedActivity == option.activity ? 1 : 0.65))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(selectedActivity == option.activity ? .isSelected : [])
                        }
                    }

                    Text("Start Session")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(Color.yellow)
                        .cornerRadius(16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            start(selectedActivity)
                        }
                        .onLongPressGesture(minimumDuration: 0.9, maximumDistance: 50) {
                            forceRecalibrateAndNavigate(selectedActivity)
                        }
                        .accessibilityLabel("Start session")
                        .accessibilityHint("Long press to recalibrate wall timing")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func start(_ activity: ActivityKind) {
        PBASessionFlowPolicy.persistTrainingMode(.solo)
        router.push(.soloSessionDuration(activity: activity))
    }

    private func forceRecalibrateAndNavigate(_ activity: ActivityKind) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.soloReturnTime)
        SoloWallCalibrationLaunchIntent.setForceInlineCalibration()
        SoloTimeBasedSession.clear()
        PBASessionFlowPolicy.persistTrainingMode(.solo)
        let route = PBASessionFlowPolicy.routeForActivityLaunch(activity)
        router.push(route)
    }
}
