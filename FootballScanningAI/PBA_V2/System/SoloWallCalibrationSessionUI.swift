//
//  SoloWallCalibrationSessionUI.swift
//  FootballScanningAI
//
//  Shared inline solo wall calibration: top-of-chain input routing + guided overlay for all PBA display activities.
//

import SwiftUI

/// Call at the **start** of tap / pass / any wall input so calibration always wins over engine phase logic.
enum SoloWallCalibrationInput {
    /// Returns `true` if the event was handled for inline calibration (caller must return immediately).
    @MainActor
    @discardableResult
    static func handleIfSoloCalibrating(
        mode: TrainingMode,
        controller: SoloWallCalibrationController,
        soundEnabled: Bool,
        activateAudio: @escaping () -> Void,
        preloadBeep: @escaping () -> Void,
        onCompletedThreePass: @escaping (Double) -> Void
    ) -> Bool {
        guard mode == .solo, controller.isCalibrating else { return false }
        controller.handleCalibrationTap(
            soundEnabled: soundEnabled,
            activateAudio: activateAudio,
            preloadBeep: preloadBeep,
            onCompletedThreePass: onCompletedThreePass
        )
        return true
    }
}

/// When to show drill focal UI (center X, gates, ball slots) vs calibration-only chrome.
enum SoloWallCalibrationDisplayPolicy {
    static func showsDrillFocalLayout(mode: TrainingMode, isCalibrating: Bool, bootResolved: Bool) -> Bool {
        guard mode == .solo else { return true }
        guard bootResolved else { return false }
        return !isCalibrating
    }

    /// Session status / rep chrome that would look like training should stay hidden during wall calibration.
    static func showsTrainingSessionChrome(mode: TrainingMode, isCalibrating: Bool, bootResolved: Bool = true) -> Bool {
        guard mode == .solo else { return true }
        guard bootResolved else { return false }
        return !isCalibrating
    }
}

/// Guided wall calibration screen (all solo PBA display activities). Replaces drill focal UI while calibrating.
struct SoloWallCalibrationGetReadyOverlay: View {
    let mode: TrainingMode
    @ObservedObject var calibration: SoloWallCalibrationController

    var body: some View {
        Group {
            if mode == .solo, calibration.isCalibrating {
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 14) {
                            Text("Set your wall timing")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text("Tap when you pass • Tap when the ball returns")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.78))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 32)

                        Spacer().frame(height: 40)

                        VStack(spacing: 12) {
                            Text(calibration.promptText)
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.yellow)
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut(duration: 0.2), value: calibration.promptText)

                            Text(calibration.repCounterText)
                                .font(.headline.weight(.medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 32)

                        Spacer(minLength: 0)

                        Text("Complete 3 reps to start training")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 48)
                    }
                }
                .allowsHitTesting(false)
                .zIndex(60)
                .transition(.opacity)
            }
        }
    }
}
