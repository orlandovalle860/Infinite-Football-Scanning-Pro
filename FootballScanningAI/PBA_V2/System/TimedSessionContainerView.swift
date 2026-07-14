//
//  TimedSessionContainerView.swift
//  FootballScanningAI
//
//  Time-based session shell: shared timer, rep count, activity switching, single save on end.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct TimedSessionContainerView: View {
    let initialActivity: ActivityKind
    let trainingMode: TrainingMode

    @ObservedObject private var timedSession = TimedSessionController.shared
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger

    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager

    @State private var showActivityPicker = false
    @State private var showEndSessionConfirmation = false
    @State private var displayedActivity: ActivityKind
    @State private var repPulseScale: CGFloat = 1

    init(
        initialActivity: ActivityKind,
        trainingMode: TrainingMode,
        settingsViewModel: SettingsViewModel,
        profileManager: UserProfileManager
    ) {
        self.initialActivity = initialActivity
        self.trainingMode = trainingMode
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _displayedActivity = State(initialValue: initialActivity)
    }


    private var targetLabel: String? {
        guard let target = timedSession.repTarget ?? SoloTimeBasedSession.config?.repTarget else { return nil }
        return "Target: \(target)+ reps"
    }

    private var sessionChromeOpacity: Double {
        timedSession.isSessionActive && !timedSession.isSessionEnding ? 1 : 0.5
    }

    var body: some View {
        Group {
            if timedSession.durationChoice == nil {
                EmptyView()
            } else {
                timedSessionShell
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var timedSessionShell: some View {
        ZStack {
            activityContent
                .id("\(displayedActivity)-\(timedSession.activitySurfaceGeneration)")
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.98).combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(.easeInOut(duration: 0.18), value: displayedActivity)

            if timedSession.isManagingSession, timedSession.isSessionActive {
                VStack(spacing: 0) {
                    sessionTopBar
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(true)
                .zIndex(200)
            }
        }
        .onChange(of: timedSession.totalRepCount) { _, _ in
            pulseRepCount()
        }
        .fullScreenCover(isPresented: $timedSession.showSummary) {
            TimedSessionSummaryProgressView(
                totalRepCount: timedSession.completionRepCount,
                durationText: timedSession.summaryDurationText,
                completionType: timedSession.lastCompletionType ?? .completed,
                isFreeMode: timedSession.isFreeMode,
                mode: timedSession.mode,
                activityRepCounts: timedSession.summaryActivityRepCounts,
                onTrainAgain: trainAgainFromSummary,
                onDone: doneFromSummary
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showActivityPicker) {
            TimedSessionActivityPickerView(
                currentActivity: displayedActivity,
                sessionLocked: timedSession.sessionLocked,
                onSelect: { activity in
                    showActivityPicker = false
                    guard activity != displayedActivity else { return }
                    Task {
                        await timedSession.switchActivity(to: activity)
                        displayedActivity = activity
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .onReceive(NotificationCenter.default.publisher(for: .timedSessionSwitchActivity)) { notification in
            guard let activity = notification.object as? ActivityKind else { return }
            guard activity != displayedActivity else { return }
            Task {
                await timedSession.switchActivity(to: activity)
                displayedActivity = activity
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .coachEndTimedSessionRequested)) { _ in
            endSessionFromCoachAuthority()
        }
        .onChange(of: timedSession.activitySurfaceGeneration) { _, _ in
            if trainingMode == .partner, let activity = timedSession.currentActivity {
                displayedActivity = activity
            }
        }
        .task {
            guard timedSession.durationChoice != nil else { return }
            await timedSession.beginIfNeeded(
                initialActivity: initialActivity,
                mode: trainingMode,
                playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
            )
            if let current = timedSession.currentActivity {
                displayedActivity = current
            }
        }
        .onAppear {
            SessionStartCueRepGate.beginSessionContainer()
        }
        .confirmationDialog(
            "End Session?",
            isPresented: $showEndSessionConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                timedSession.finishSession(
                    completionType: timedSession.userInitiatedEndCompletionType,
                    showsSummary: false,
                    onPersisted: {
                        goHome()
                    }
                )
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your progress will be saved automatically.")
        }
        // Session teardown is explicit only (`finishSession`, `clear`, summary done) — not on transient disappear (background / reconnect).
    }

    private func doneFromSummary() {
        timedSession.completeSummaryDone {
            router.popToRoot()
        }
    }

    private func trainAgainFromSummary() {
        let mode = trainingMode
        let activity = initialActivity
        if mode == .partner {
            displayedActivity = activity
            timedSession.preparePartnerTrainAgain(
                initialActivity: activity,
                playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id
            )
            return
        }
        timedSession.completeSummaryTrainAgain {
            router.popToRoot()
            router.push(.soloActivitySelection)
        }
    }

    private func endSessionFromTopBar() {
        NotificationCenter.default.post(name: .timedSessionEndRequested, object: nil)
    }

    private func endSessionFromCoachAuthority() {
        guard trainingMode == .partner else { return }
        guard timedSession.isManagingSession, timedSession.isSessionActive else { return }

        let completionType = timedSession.userInitiatedEndCompletionType
        // Match display End Session: leave pairing live and return to Connected standby
        // without leaving a locked timed shell that blocks the next coach Start Session.
        timedSession.finishSession(
            completionType: completionType,
            showsSummary: false,
            onPersisted: {
                goHome()
            },
            peerInitiated: true
        )
    }

    private var isSoloTimedSessionLive: Bool {
        trainingMode == .solo
            && timedSession.isManagingSession
            && timedSession.isSessionActive
            && SoloTimeBasedSession.isActive
    }

    private func goHome() {
        HomeNavigationAction.goHome(router: router, popToRootTrigger: popToRootTrigger)
    }

    private func handleHomeFromTopBarTapped() {
        if timedSession.isManagingSession, timedSession.isSessionActive, SoloTimeBasedSession.isActive {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                showEndSessionConfirmation = true
            }
        } else {
            goHome()
        }
    }

    private func pulseRepCount() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
            repPulseScale = 1.1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.2)) {
                repPulseScale = 1
            }
        }
    }

    @ViewBuilder
    private var activityContent: some View {
        switch displayedActivity {
        case .twoMinuteTest:
            TwoMinuteCriticalScanSessionView(
                config: TwoMinuteTestConfig.baseline,
                mode: trainingMode,
                settingsViewModel: settingsViewModel,
                profileManager: profileManager
            )
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .awayFromPressure:
            AwayFromPressureDisplaySessionView(
                config: AwayFromPressureConfig.config(for: .standard),
                mode: trainingMode,
                settingsViewModel: settingsViewModel,
                profileManager: profileManager
            )
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .dribbleOrPass:
            DribbleOrPassDisplaySessionView(
                config: DribbleOrPassConfig.defaultConfig(for: .standard),
                mode: trainingMode,
                settingsViewModel: settingsViewModel,
                profileManager: profileManager
            )
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .oneTouchPassing:
            OneTouchPassingDisplaySessionView(
                config: OneTouchPassingConfig.defaultConfig(for: .standard),
                mode: trainingMode,
                settingsViewModel: settingsViewModel,
                profileManager: profileManager
            )
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        }
    }

    private var sessionTopBar: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayedActivity.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.yellow.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Activity")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
            }
            .frame(maxWidth: 120, alignment: .leading)
            .padding(.leading, 4)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(timedSession.timerDisplayText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("Time")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
            }
            .fixedSize()
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.85) {
                endSessionFromTopBar()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Session time \(timedSession.timerDisplayText)")
            .accessibilityHint("Long press to end session")

            Spacer()

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(timedSession.totalRepCount)")
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .scaleEffect(repPulseScale)
                    Text("Reps")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                    if let targetLabel {
                        Text(targetLabel)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.32))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .fixedSize()

                if trainingMode != .partner {
                    Button(action: { showActivityPicker = true }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.yellow.opacity(timedSession.sessionLocked ? 0.35 : 0.95))
                    .disabled(timedSession.sessionLocked)
                    .accessibilityLabel("Change activity")
                }

                if trainingMode == .partner {
                    Button(action: endSessionFromTopBar) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.orange.opacity(0.92))
                    .accessibilityLabel("End Session")
                    .accessibilityAddTraits(.isButton)
                } else {
                    if isSoloTimedSessionLive {
                        Button {
                            if timedSession.isManagingSession,
                               timedSession.isSessionActive,
                               SoloTimeBasedSession.isActive {
                                timedSession.finishSession(
                                    completionType: timedSession.userInitiatedEndCompletionType,
                                    showsSummary: true,
                                    onPersisted: nil
                                )
                            }
                        } label: {
                            Text("End Session")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.red)
                                        .shadow(color: Color.black.opacity(0.15), radius: 3, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: handleHomeFromTopBarTapped) {
                        Image(systemName: "house")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.85))
                    .accessibilityLabel("Home")
                }
            }
            .fixedSize()
        }
        .opacity(sessionChromeOpacity)
        .animation(.easeOut(duration: 0.2), value: sessionChromeOpacity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .safeAreaPadding(.top, 8)
    }
}

struct TimedSessionActivityPickerView: View {
    let currentActivity: ActivityKind
    let sessionLocked: Bool
    let onSelect: (ActivityKind) -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private let options: [ActivityKind] = [
        .twoMinuteTest,
        .awayFromPressure,
        .dribbleOrPass,
        .oneTouchPassing
    ]

    @State private var tappedActivity: ActivityKind?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Switch Activity")
                        .font(.headline)
                    Text("Session continues — choose next focus")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.top, 12)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(options, id: \.self) { activity in
                        activityCard(for: activity)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .opacity(sessionLocked ? 0.45 : 1)
    }

    private func activityCard(for activity: ActivityKind) -> some View {
        let isSelected = activity == currentActivity
        let isTapped = tappedActivity == activity

        return Button {
            guard !sessionLocked else { return }
            triggerSelectionHaptic()
            withAnimation(.easeOut(duration: 0.12)) {
                tappedActivity = activity
            }
            onSelect(activity)
        } label: {
            VStack(spacing: 12) {
                Image(systemName: activity.activityPickerIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(isSelected ? .blue : .primary)

                Text(activity.displayName)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .opacity(isTapped ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .disabled(sessionLocked)
        .accessibilityLabel(activity.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
