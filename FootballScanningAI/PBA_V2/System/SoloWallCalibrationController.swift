//
//  SoloWallCalibrationController.swift
//  FootballScanningAI
//
//  Shared inline Solo wall calibration for all PBA display sessions (DOP, OTP, AFP, 2MT, etc.).
//

import Foundation
import Combine

/// Owns inline Solo wall calibration state and beep scheduling so individual activity views stay thin.
@MainActor
final class SoloWallCalibrationController: ObservableObject {
    static let passCount = 3
    /// `UserDefaults` value for ``AppStorageKeys/soloReturnTime`` at or below this is treated as missing — inline calibration is required.
    static let minimumUserDefaultsSoloReturnTimeSeconds: TimeInterval = 0.3
    /// Safe baseline written to ``AppStorageKeys/soloReturnTime`` when inline calibration auto-completes.
    static let simulatedBaselineReturnTimeSeconds: TimeInterval = 1.0
    private static let autoCompleteAfterBeepSeconds: TimeInterval = 0.8

    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationCount = 0
    @Published private(set) var calibratedReturnTime: Double = 1.1

    private var calibrationTimes: [Double] = []
    private var calibrationStartTime: Date?
    private var autoCompleteToken = UUID()
    private var calibrationSequenceHasStarted = false
    private var inlineCalibrationCompletion: ((Double) -> Void)?
    private var trainingMode: TrainingMode = .solo

    enum SoloWallBoot {
        case cachedTravelSeconds(Double)
        case needsInlineThreePass
    }

    /// Same source order as ``prepareSoloLocalDisplay`` (``AppStorageKeys/soloReturnTime`` then partner rolling average).
    static func effectiveSoloWallReturnTimeSeconds() -> TimeInterval? {
        let saved = UserDefaults.standard.double(forKey: AppStorageKeys.soloReturnTime)
        if saved > minimumUserDefaultsSoloReturnTimeSeconds {
            return min(max(saved, 0.2), 5.0)
        }
        if let p = PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds(), p > minimumUserDefaultsSoloReturnTimeSeconds {
            return min(max(p, 0.2), 5.0)
        }
        return nil
    }

    /// Call on local (non–Coach Remote) display appear for **Solo** to load `UserDefaults` / partner-rolling time or start inline calibration.
    func prepareSoloLocalDisplay(trainingMode: TrainingMode, nominalTravelSeconds: Double) -> SoloWallBoot {
        self.trainingMode = trainingMode
        // SwiftUI `onAppear` can fire twice; do not reset mid-sequence or `startCalibrationSequence` beeps again.
        if !isCalibrating {
            calibrationSequenceHasStarted = false
        }
        let saved = UserDefaults.standard.double(forKey: AppStorageKeys.soloReturnTime)
        if saved > Self.minimumUserDefaultsSoloReturnTimeSeconds {
            let c = min(max(saved, 0.2), 5.0)
            calibratedReturnTime = c
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(c)
            isCalibrating = false
            calibrationCount = 0
            calibrationTimes = []
            calibrationStartTime = nil
            cancelPendingBeeps()
            return .cachedTravelSeconds(c)
        }
        if let p = PartnerPassTempoCalibrationStore.savedAverageTravelTimeSeconds(), p > Self.minimumUserDefaultsSoloReturnTimeSeconds {
            let c = min(max(p, 0.2), 5.0)
            calibratedReturnTime = c
            CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(c)
            isCalibrating = false
            cancelPendingBeeps()
            return .cachedTravelSeconds(c)
        }
        isCalibrating = true
        calibrationCount = 0
        calibrationTimes = []
        calibrationStartTime = nil
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nominalTravelSeconds)
        calibratedReturnTime = max(0.2, min(nominalTravelSeconds, 5.0))
        cancelPendingBeeps()
        return .needsInlineThreePass
    }

    /// When ``AppStorageKeys/soloReturnTime`` is invalid mid-session, force inline calibration without partner rolling average as a stand-in.
    func forceStartInlineSoloWallCalibration(nominalTravelSeconds: Double, trainingMode: TrainingMode) {
        self.trainingMode = trainingMode
        calibrationSequenceHasStarted = false
        isCalibrating = true
        calibrationCount = 0
        calibrationTimes = []
        calibrationStartTime = nil
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nominalTravelSeconds)
        calibratedReturnTime = max(0.2, min(nominalTravelSeconds, 5.0))
        cancelPendingBeeps()
    }

    func cancelPendingBeeps() {
        autoCompleteToken = UUID()
    }

    /// Partner / non-solo: stop inline calibration and timers.
    func resetForNonSoloSession() {
        isCalibrating = false
        calibrationSequenceHasStarted = false
        inlineCalibrationCompletion = nil
        cancelPendingBeeps()
    }

    /// One beep, then auto-complete after a short pause (no multi-beep tap loop).
    func startCalibrationSequence(
        soundEnabled: Bool,
        activateAudio: @escaping () -> Void,
        preloadBeep: @escaping () -> Void,
        onCompleted: ((Double) -> Void)? = nil
    ) {
        guard isCalibrating else { return }
        guard !calibrationSequenceHasStarted else { return }
        calibrationSequenceHasStarted = true
        inlineCalibrationCompletion = onCompleted

        cancelPendingBeeps()

        let simulatedReturnTime = Self.simulatedBaselineReturnTimeSeconds
        calibratedReturnTime = simulatedReturnTime
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(simulatedReturnTime)

        preloadBeep()
        activateAudio()
        PBABeepSoundManager.shared.play(soundEnabled: soundEnabled)

        let token = autoCompleteToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCompleteAfterBeepSeconds) { [weak self] in
            guard let self, self.autoCompleteToken == token else { return }
            self.finishAutomaticInlineCalibration()
        }
    }

    func handleCalibrationTap(
        soundEnabled: Bool,
        activateAudio: @escaping () -> Void,
        preloadBeep: @escaping () -> Void,
        onCompletedThreePass: @escaping (Double) -> Void
    ) {
        guard isCalibrating else { return }
        // Inline calibration auto-completes; taps are ignored so we never re-enter a multi-beep loop.
        if calibrationSequenceHasStarted { return }
        _ = soundEnabled
        _ = activateAudio
        _ = preloadBeep
        _ = onCompletedThreePass
    }

    private func finishAutomaticInlineCalibration() {
        calibrationSequenceHasStarted = false
        cancelPendingBeeps()

        let clamped = Self.simulatedBaselineReturnTimeSeconds
        calibratedReturnTime = clamped
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(clamped)
        PartnerPassTempoCalibrationStore.save(averageTravelTimeSeconds: clamped, trainingMode: trainingMode)
        UserDefaults.standard.set(clamped, forKey: AppStorageKeys.soloReturnTime)
        isCalibrating = false
        calibrationCount = 0
        calibrationTimes = []
        calibrationStartTime = nil

        let completion = inlineCalibrationCompletion
        inlineCalibrationCompletion = nil
        completion?(clamped)
    }
}
