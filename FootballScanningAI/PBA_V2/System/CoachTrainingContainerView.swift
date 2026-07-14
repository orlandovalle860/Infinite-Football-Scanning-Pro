//
//  CoachTrainingContainerView.swift
//  FootballScanningAI
//
//  In-place coach activity rendering for timed partner sessions.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CoachTrainingContainerView: View {
    let fallbackActivity: ActivityKind
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var partnerCoordinator = TrainingPartnerConnectionCoordinator.shared
    @ObservedObject private var timedSession = TimedSessionController.shared

    @State private var showActivityPicker = false
    @State private var switchBanner: CoachActivitySwitchBannerView.Style?

    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    private var shouldUseTimedSharedSwitching: Bool {
        partnerCoordinator.isPartnerTrainingSessionActive
        && resolvedActivityId != nil
    }

    private var showsCoachEndSessionControl: Bool {
        partnerCoordinator.isPartnerTrainingSessionActive
    }

    private var showsCoachChangeActivityControl: Bool {
        partnerCoordinator.isPartnerTrainingSessionActive
            && partnerCoordinator.displayTimedSessionAnnounced
    }

    private var resolvedActivityId: String? {
        partnerCoordinator.currentTimedSessionActivityId
            ?? partnerCoordinator.lastNonNilActivityId
    }

    private var resolvedActivity: ActivityKind {
        let rawActivityId = partnerCoordinator.currentTimedSessionActivityId
        let lastActivityId = partnerCoordinator.lastNonNilActivityId
        let effectiveActivityId = resolvedActivityId
        let mappedActivity = effectiveActivityId.flatMap(ActivityKind.fromSessionActivityId)
        debugLog("[COACH SESSION] usesSharedSession=\(TimedSessionDisplayIntegration.usesSharedSession)")
        debugLog("[COACH SESSION] partnerActive=\(partnerCoordinator.isPartnerTrainingSessionActive) coachTimedSessionActive=\(timedSession.isSessionActive)")
        debugLog("[COACH RESOLVE] raw=\(rawActivityId ?? "nil") last=\(lastActivityId ?? "nil") resolved=\(mappedActivity?.rawValue ?? "nil")")
        if effectiveActivityId == nil {
            debugLog("[COACH WARNING] activityId is nil — fallback may trigger")
        }

        let shouldUseTimedSharedSwitching =
            self.shouldUseTimedSharedSwitching
        if shouldUseTimedSharedSwitching,
           let activity = mappedActivity {
            return activity
        }
        debugLog("[COACH VIEW] rendering WAITING (fallback=\(fallbackActivity.rawValue))")
        return fallbackActivity
    }

    var body: some View {
        Group {
            switch resolvedActivity {
            case .twoMinuteTest:
                let _ = debugLog("[COACH VIEW] rendering MTB")
                TwoMinuteCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
            case .dribbleOrPass:
                let _ = debugLog("[COACH VIEW] rendering DOP")
                DribbleOrPassCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
            case .awayFromPressure:
                let _ = debugLog("[COACH VIEW] rendering AFP")
                AwayFromPressureCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
            case .oneTouchPassing:
                let _ = debugLog("[COACH VIEW] rendering OTP")
                OneTouchPassingCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                VisionPlayBrandingView(style: .sessionChrome)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                if showsCoachEndSessionControl {
                    coachEndSessionBar
                }
            }
        }
        .overlay(alignment: .top) {
            if let switchBanner {
                CoachActivitySwitchBannerView(style: switchBanner)
                    .padding(.top, showsCoachEndSessionControl ? 52 : 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: switchBanner)
        .onReceive(NotificationCenter.default.publisher(for: .partnerTimedSessionEndedFromDisplay)) { _ in
            handleDisplayEndedTimedSession()
        }
        .onAppear {
            debugLog("[COACH VIEW] container appeared shouldUseTimedSharedSwitching=\(shouldUseTimedSharedSwitching)")
        }
        .sheet(isPresented: $showActivityPicker) {
            CoachActivityChangePickerView(
                currentActivity: resolvedActivity,
                onSelect: { activity in
                    handleActivitySelection(activity)
                }
            )
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    private var coachEndSessionBar: some View {
        HStack(spacing: 12) {
            if showsCoachChangeActivityControl {
                coachChangeActivityButton
            }
            Spacer()
            Button("End Session") {
                partnerCoordinator.coachEndTimedSession(router: router)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.orange)
            .accessibilityLabel("End Session")
            .accessibilityHint("Ends training on the display and returns both devices to home")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
    }

    private var coachChangeActivityButton: some View {
        Button {
            showActivityPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Change")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
        }
        .accessibilityLabel("Change Activity")
        .accessibilityHint("Choose the next training activity")
    }

    private func handleActivitySelection(_ activity: ActivityKind) {
        showActivityPicker = false
        guard activity != resolvedActivity else { return }

        Task {
            switchBanner = nil
            let delivered = await partnerCoordinator.sendActivityChanged(to: activity) {
                withAnimation {
                    switchBanner = .connectionRetrying
                }
            }

            if delivered {
                triggerSwitchBannerHaptic()
                withAnimation {
                    switchBanner = .switched(activityName: activity.displayName)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation {
                    switchBanner = nil
                }
            } else {
                withAnimation {
                    switchBanner = .connectionRetrying
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation {
                    switchBanner = nil
                }
            }
        }
    }

    private func handleDisplayEndedTimedSession() {
        guard partnerCoordinator.isPartnerTrainingSessionActive else { return }
        partnerCoordinator.softResetAfterTimedPartnerSessionEnd()
        router.returnToCoachRemoteHubAfterSessionEnd()
    }

    private func triggerSwitchBannerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
