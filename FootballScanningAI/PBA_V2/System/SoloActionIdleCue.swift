//
//  SoloActionIdleCue.swift
//  FootballScanningAI
//
//  Solo Action style: one-shot center focus, haptic, and persistent tap hint while idle.
//

import Combine
import SwiftUI
import UIKit

enum SoloActionIdleCue {
    static let tapHintShowDelay: TimeInterval = 0.2

    static func isActionPaced(mode: TrainingMode) -> Bool {
        mode == .solo && !SoloTimeBasedDisplaySessionSupport.effectiveUsesAutoLoop(mode: mode)
    }

    static func applyPhaseTransition(
        mode: TrainingMode,
        wasWaitingForNextRep: Bool,
        isWaitingForNextRep: Bool,
        cue: SoloActionIdleCueState
    ) {
        guard isActionPaced(mode: mode) else { return }
        if isWaitingForNextRep, !wasWaitingForNextRep {
            cue.onEnteredActionIdle()
        } else if wasWaitingForNextRep, !isWaitingForNextRep {
            cue.onRepStarting()
        }
    }

    /// Action mode: activate idle cues when already `waitingForNextRep` (e.g. after 3–2–1–Go, before first rep).
    static func refreshActionIdleIfWaiting(
        mode: TrainingMode,
        isWaitingForNextRep: Bool,
        cue: SoloActionIdleCueState
    ) {
        guard isActionPaced(mode: mode), isWaitingForNextRep else { return }
        let isFirstRepOfSession = SoloTimeBasedSession.sessionRepCount == 0
        cue.activateWaitingIdle(
            haptic: isFirstRepOfSession ? .sessionReady : .repCompleted
        )
    }

    /// Call when session countdown clears (Go → drill visible).
    static func handleCountdownEnded(
        mode: TrainingMode,
        wasBlocking: Bool,
        isBlocking: Bool,
        isWaitingForNextRep: Bool,
        cue: SoloActionIdleCueState
    ) {
        guard wasBlocking, !isBlocking else { return }
        refreshActionIdleIfWaiting(mode: mode, isWaitingForNextRep: isWaitingForNextRep, cue: cue)
    }
}

@MainActor
final class SoloActionIdleCueState: ObservableObject {
    @Published private(set) var focusPulseTrigger = 0
    @Published private(set) var showTapHint = false

    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private var tapHintShowWorkItem: DispatchWorkItem?

    fileprivate enum IdleHaptic {
        case repCompleted
        case sessionReady
    }

    func onEnteredActionIdle() {
        activateWaitingIdle(haptic: .repCompleted)
    }

    fileprivate func activateWaitingIdle(haptic: IdleHaptic) {
        cancelPendingIdleWork()

        switch haptic {
        case .repCompleted:
            softHaptic.prepare()
            softHaptic.impactOccurred()
        case .sessionReady:
            lightHaptic.prepare()
            lightHaptic.impactOccurred()
        }

        focusPulseTrigger += 1

        let hintWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.tapHintShowWorkItem = nil
            self.showTapHint = true
        }
        tapHintShowWorkItem = hintWork
        DispatchQueue.main.asyncAfter(deadline: .now() + SoloActionIdleCue.tapHintShowDelay, execute: hintWork)
    }

    func onRepStarting() {
        cancelPendingIdleWork()
        hideTapHintIfVisible()
    }

    func onUserTapToStart() {
        cancelPendingIdleWork()
        lightHaptic.prepare()
        lightHaptic.impactOccurred()
        hideTapHintIfVisible()
    }

    private func hideTapHintIfVisible() {
        if showTapHint {
            withAnimation(.easeOut(duration: 0.2)) {
                showTapHint = false
            }
        }
    }

    private func cancelPendingIdleWork() {
        tapHintShowWorkItem?.cancel()
        tapHintShowWorkItem = nil
    }
}

struct SoloActionCenterMarkerView: View {
    let focusPulseTrigger: Int
    var isSessionEnding: Bool = false

    private static let focusPulseScale: CGFloat = 1.06
    private static let focusPulseHalfDuration: TimeInterval = 0.2

    @State private var scale: CGFloat = 1.0

    var body: some View {
        Text("X")
            .font(.system(size: 80, weight: .bold))
            .foregroundColor(.white)
            .shadow(radius: 5)
            .scaleEffect(isSessionEnding ? 1.0 : scale)
            .opacity(isSessionEnding ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isSessionEnding)
            .onAppear {
                if focusPulseTrigger > 0 {
                    runFocusPulse()
                }
            }
            .onChange(of: focusPulseTrigger) { _, _ in
                runFocusPulse()
            }
    }

    private func runFocusPulse() {
        guard !isSessionEnding else { return }
        scale = 1.0
        withAnimation(.easeInOut(duration: Self.focusPulseHalfDuration)) {
            scale = Self.focusPulseScale
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusPulseHalfDuration) {
            withAnimation(.easeInOut(duration: Self.focusPulseHalfDuration)) {
                scale = 1.0
            }
        }
    }
}

struct SoloActionTapHintView: View {
    private static let fadeInDuration: TimeInterval = 0.2
    private static let emphasisDelay: TimeInterval = 0.5
    private static let fadedOpacity = 0.6

    @State private var displayOpacity = 0.0

    var body: some View {
        VStack {
            Spacer()
            Text("Tap to start")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.7))
                .opacity(displayOpacity)
                .padding(.bottom, 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear(perform: beginHintPresentation)
    }

    private func beginHintPresentation() {
        displayOpacity = 0
        withAnimation(.easeIn(duration: Self.fadeInDuration)) {
            displayOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.emphasisDelay) {
            withAnimation(.easeOut(duration: 0.5)) {
                displayOpacity = Self.fadedOpacity
            }
        }
    }
}
