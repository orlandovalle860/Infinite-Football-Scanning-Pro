//
//  SoloSessionStart.swift
//  FootballScanningAI
//
//  Single entry for solo wall timing: all display activities use this instead of duplicating
//  `prepareSoloLocalDisplay` + inline calibration start.
//

import Foundation

@MainActor
enum SoloSessionStart {
    /// Call when `mode == .solo` after any partner-only `onAppear` setup (relay, `hasCompletedPassTempoCalibration`, etc.).
    /// Sets wall state via ``SoloWallCalibrationController/prepareSoloLocalDisplay`` and starts inline calibration when required.
    static func applySoloWallCalibrationBoot(
        trainingMode: TrainingMode,
        controller: SoloWallCalibrationController,
        nominalWallTravelSeconds: Double,
        setHasCompletedPassTempoCalibration: (Bool) -> Void,
        soundEnabled: Bool,
        activateAudio: @escaping () -> Void,
        preloadBeep: @escaping () -> Void,
        onInlineCalibrationFinished: @escaping (Double) -> Void
    ) {
        let boot: SoloWallCalibrationController.SoloWallBoot
        if SoloWallCalibrationLaunchIntent.consumeForceInlineCalibration() {
            controller.forceStartInlineSoloWallCalibration(
                nominalTravelSeconds: nominalWallTravelSeconds,
                trainingMode: trainingMode
            )
            boot = .needsInlineThreePass
        } else {
            boot = controller.prepareSoloLocalDisplay(
                trainingMode: trainingMode,
                nominalTravelSeconds: nominalWallTravelSeconds
            )
        }
        switch boot {
        case .cachedTravelSeconds:
            setHasCompletedPassTempoCalibration(true)
        case .needsInlineThreePass:
            setHasCompletedPassTempoCalibration(false)
            controller.startCalibrationSequence(
                soundEnabled: soundEnabled,
                activateAudio: activateAudio,
                preloadBeep: preloadBeep,
                onCompleted: onInlineCalibrationFinished
            )
        }
    }
}
