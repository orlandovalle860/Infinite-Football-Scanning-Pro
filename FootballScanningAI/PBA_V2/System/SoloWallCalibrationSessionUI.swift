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

/// Guided two-tap wall calibration overlay (all solo PBA display activities).
struct SoloWallCalibrationGetReadyOverlay: View {
    let mode: TrainingMode
    @ObservedObject var calibration: SoloWallCalibrationController

    var body: some View {
        Group {
            if mode == .solo, calibration.isCalibrating {
                GeometryReader { geo in
                    VStack(spacing: 14) {
                        Text(calibration.promptText)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text(calibration.repCounterText)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))
                    }
                    .frame(maxWidth: min(geo.size.width - 48, 360))
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.35)
                }
                .allowsHitTesting(false)
                .zIndex(55)
            }
        }
    }
}
