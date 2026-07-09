//
//  SoloSessionUserStartGate.swift
//  FootballScanningAI
//
//  Solo local display: after calibration, wait for an explicit tap before the first rep and session clock.
//

import SwiftUI

enum SoloSessionStartPhase: Equatable {
    case calibrating
    case waitingForUserStart
    case running
}

@MainActor
enum SoloSessionUserStartGate {
    private static var hasUserConfirmedStart = false

    static func reset() {
        hasUserConfirmedStart = false
    }

    static var hasConfirmedUserStart: Bool { hasUserConfirmedStart }

    static func phase(
        mode: TrainingMode,
        hasCompletedCalibration: Bool,
        isCalibrating: Bool
    ) -> SoloSessionStartPhase {
        guard mode == .solo, !mode.requiresPhoneDisplayRelay else { return .running }
        if isCalibrating || !hasCompletedCalibration { return .calibrating }
        if !hasUserConfirmedStart { return .waitingForUserStart }
        return .running
    }

    static func isWaitingForUserStart(
        mode: TrainingMode,
        hasCompletedCalibration: Bool,
        isCalibrating: Bool
    ) -> Bool {
        phase(mode: mode, hasCompletedCalibration: hasCompletedCalibration, isCalibrating: isCalibrating) == .waitingForUserStart
    }

    static func shouldBlockSoloRepFlow(
        mode: TrainingMode,
        hasCompletedCalibration: Bool,
        isCalibrating: Bool
    ) -> Bool {
        isWaitingForUserStart(mode: mode, hasCompletedCalibration: hasCompletedCalibration, isCalibrating: isCalibrating)
    }

    static func beginSessionAfterUserTap(
        mode: TrainingMode,
        localTimer: SoloSessionTimerController,
        tryAutoloop: () -> Void
    ) {
        guard mode == .solo, !mode.requiresPhoneDisplayRelay else { return }
        guard !hasUserConfirmedStart else {
            tryAutoloop()
            return
        }
        hasUserConfirmedStart = true
        SoloTimeBasedSession.beginSessionClock()
        CurrentSessionStore.shared.startAnalyticsClockIfNeeded()

        if TimedSessionDisplayIntegration.usesSharedSession {
            TimedSessionController.shared.onUserConfirmedSessionStart()
        } else {
            SoloTimeBasedDisplaySessionSupport.startTimerIfNeeded(
                mode: mode,
                timer: TimedSessionDisplayIntegration.sessionTimer(local: localTimer)
            )
        }
        tryAutoloop()
    }
}

// MARK: - TAP TO START overlay (solo local display only)

private struct SoloTapToStartPromptView: View {
    @State private var pulseDim = false

    var body: some View {
        Text("TAP TO START")
            .foregroundColor(.white.opacity(pulseDim ? 0.72 : 1.0))
            .font(.largeTitle.weight(.bold))
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)
            .onAppear {
                pulseDim = false
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    pulseDim = true
                }
            }
    }
}

private struct SoloTapToStartGateModifier: ViewModifier {
    let mode: TrainingMode
    let hasCompletedCalibration: Bool
    let isCalibrating: Bool
    let sessionStartCueActive: Bool
    let localTimer: SoloSessionTimerController
    let onUserStart: () -> Void

    private var showsOverlay: Bool {
        SoloSessionUserStartGate.isWaitingForUserStart(
            mode: mode,
            hasCompletedCalibration: hasCompletedCalibration,
            isCalibrating: isCalibrating
        ) && !sessionStartCueActive
    }

    func body(content: Content) -> some View {
        ZStack {
            content
            if showsOverlay {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        SoloSessionUserStartGate.beginSessionAfterUserTap(
                            mode: mode,
                            localTimer: localTimer,
                            tryAutoloop: onUserStart
                        )
                    }

                SoloTapToStartPromptView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsOverlay)
    }
}

extension View {
    /// Blocks solo reps until the player taps to start after calibration. Partner mode is unchanged.
    func soloTapToStartGate(
        mode: TrainingMode,
        hasCompletedCalibration: Bool,
        isCalibrating: Bool,
        sessionStartCueActive: Bool,
        localTimer: SoloSessionTimerController,
        onUserStart: @escaping () -> Void
    ) -> some View {
        modifier(
            SoloTapToStartGateModifier(
                mode: mode,
                hasCompletedCalibration: hasCompletedCalibration,
                isCalibrating: isCalibrating,
                sessionStartCueActive: sessionStartCueActive,
                localTimer: localTimer,
                onUserStart: onUserStart
            )
        )
    }
}
