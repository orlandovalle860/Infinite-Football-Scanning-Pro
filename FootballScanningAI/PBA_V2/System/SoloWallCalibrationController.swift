//
//  SoloWallCalibrationController.swift
//  FootballScanningAI
//
//  Shared inline Solo wall calibration for all PBA display sessions (DOP, OTP, AFP, 2MT, etc.).
//

import Foundation
import Combine

/// Transient launch intent for solo display sessions (activity picker long-press, summary recalibrate).
enum SoloWallCalibrationLaunchIntent {
    static func setForceInlineCalibration() {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.soloForceInlineCalibration)
    }

    /// Returns whether force was requested; clears the flag when consumed.
    static func consumeForceInlineCalibration() -> Bool {
        let force = UserDefaults.standard.bool(forKey: AppStorageKeys.soloForceInlineCalibration)
        if force {
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.soloForceInlineCalibration)
        }
        return force
    }
}

enum SoloWallCalibrationRepPhase: Equatable {
    case betweenReps
    case waitingForPassTap
    case waitingForReturnTap
    case repComplete
}

/// Owns inline Solo wall calibration state and beep scheduling so individual activity views stay thin.
@MainActor
final class SoloWallCalibrationController: ObservableObject {
    static let passCount = 3
    /// `UserDefaults` value for ``AppStorageKeys/soloReturnTime`` at or below this is treated as missing — inline calibration is required.
    static let minimumUserDefaultsSoloReturnTimeSeconds: TimeInterval = 0.3
    static let minTapSeparationSeconds: TimeInterval = 0.2
    /// Per-rep and session average pass→return taps; upper bound matches ``effectiveSoloWallReturnTimeSeconds()`` / inline nominal cap (5.0s).
    static let clampedReturnTimeRange: ClosedRange<TimeInterval> = 0.4...5.0
    static let interRepDelayRange: ClosedRange<TimeInterval> = 0.8...1.2

    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationCount = 0
    @Published private(set) var calibratedReturnTime: Double = 1.1
    @Published private(set) var repPhase: SoloWallCalibrationRepPhase = .betweenReps
    @Published private(set) var activeRepNumber: Int = 1

    private var calibrationTimes: [Double] = []
    private var passTapTime: Date?
    private var lastTapTime: Date?
    private var sequenceToken = UUID()
    private var calibrationSequenceHasStarted = false
    private var inlineCalibrationCompletion: ((Double) -> Void)?
    private var trainingMode: TrainingMode = .solo

    var promptText: String {
        switch repPhase {
        case .betweenReps, .repComplete:
            return "Follow the beep"
        case .waitingForPassTap:
            return "Tap when you pass"
        case .waitingForReturnTap:
            return "Tap when the ball returns"
        }
    }

    var repCounterText: String {
        "Rep \(activeRepNumber) / \(Self.passCount)"
    }

    enum SoloWallBoot {
        case cachedTravelSeconds(Double)
        case needsInlineThreePass
    }

    /// Solo-only cached wall return time for the **active player** (no partner-store fallback).
    static func effectiveSoloWallReturnTimeSeconds(playerId: UUID? = nil) -> TimeInterval? {
        guard let playerId = playerId ?? CalibrationPlayerScope.activePlayerId() else { return nil }
        migrateLegacySoloReturnTimeIfNeeded(for: playerId)
        let key = AppStorageKeys.soloReturnTimeKey(playerId: playerId)
        let saved = UserDefaults.standard.double(forKey: key)
        guard saved > minimumUserDefaultsSoloReturnTimeSeconds else { return nil }
        return min(max(saved, 0.2), 5.0)
    }

    /// One-time: copy legacy device-wide `soloReturnTime` onto this player, then remove the legacy key.
    private static func migrateLegacySoloReturnTimeIfNeeded(for playerId: UUID) {
        let scoped = AppStorageKeys.soloReturnTimeKey(playerId: playerId)
        guard UserDefaults.standard.object(forKey: scoped) == nil,
              UserDefaults.standard.object(forKey: AppStorageKeys.soloReturnTime) != nil else { return }
        let legacy = UserDefaults.standard.double(forKey: AppStorageKeys.soloReturnTime)
        UserDefaults.standard.set(legacy, forKey: scoped)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.soloReturnTime)
    }

    /// Clears all solo wall calibration (legacy + every player). Call on account deletion.
    static func clearSavedSoloWallCalibration() {
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.soloReturnTime)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.soloForceInlineCalibration)
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("soloReturnTime.") {
            defaults.removeObject(forKey: key)
        }
    }

    /// Clears solo wall calibration for one player.
    static func clearSavedSoloWallCalibration(playerId: UUID) {
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.soloReturnTimeKey(playerId: playerId))
    }

    /// Call on local (non–Coach Remote) display appear for **Solo** to load this player's return time or start inline calibration.
    func prepareSoloLocalDisplay(trainingMode: TrainingMode, nominalTravelSeconds: Double) -> SoloWallBoot {
        self.trainingMode = trainingMode
        if !isCalibrating {
            calibrationSequenceHasStarted = false
        }
        guard let playerId = CalibrationPlayerScope.activePlayerId() else {
            print("[Calibration] solo boot — no active playerId; requiring inline calibration")
            resetForInlineCalibration(nominalTravelSeconds: nominalTravelSeconds)
            return .needsInlineThreePass
        }
        Self.migrateLegacySoloReturnTimeIfNeeded(for: playerId)
        let key = AppStorageKeys.soloReturnTimeKey(playerId: playerId)
        let saved = UserDefaults.standard.double(forKey: key)
        if saved > Self.minimumUserDefaultsSoloReturnTimeSeconds {
            let c = min(max(saved, 0.2), 5.0)
            applyCachedReturnTime(c)
            print("[Calibration] solo boot playerId=\(playerId.uuidString.lowercased()) usingCached=\(c)")
            return .cachedTravelSeconds(c)
        }
        print("[Calibration] solo boot playerId=\(playerId.uuidString.lowercased()) needsInlineThreePass")
        resetForInlineCalibration(nominalTravelSeconds: nominalTravelSeconds)
        return .needsInlineThreePass
    }

    /// When ``AppStorageKeys/soloReturnTime`` is invalid mid-session, force inline calibration without partner rolling average as a stand-in.
    func forceStartInlineSoloWallCalibration(nominalTravelSeconds: Double, trainingMode: TrainingMode) {
        self.trainingMode = trainingMode
        resetForInlineCalibration(nominalTravelSeconds: nominalTravelSeconds)
    }

    func cancelPendingBeeps() {
        sequenceToken = UUID()
    }

    /// Partner / non-solo: stop inline calibration and timers.
    func resetForNonSoloSession() {
        isCalibrating = false
        calibrationSequenceHasStarted = false
        inlineCalibrationCompletion = nil
        repPhase = .betweenReps
        cancelPendingBeeps()
    }

    /// Guided 3-rep calibration: beep → pass tap → return tap → pause → repeat.
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
        calibrationCount = 0
        calibrationTimes = []
        passTapTime = nil
        lastTapTime = nil
        activeRepNumber = 1
        cancelPendingBeeps()
        beginRep(
            soundEnabled: soundEnabled,
            activateAudio: activateAudio,
            preloadBeep: preloadBeep
        )
    }

    func handleCalibrationTap(
        soundEnabled: Bool,
        activateAudio: @escaping () -> Void,
        preloadBeep: @escaping () -> Void,
        onCompletedThreePass: @escaping (Double) -> Void
    ) {
        guard isCalibrating, calibrationSequenceHasStarted else { return }

        let now = Date()
        if let lastTapTime, now.timeIntervalSince(lastTapTime) < Self.minTapSeparationSeconds {
            return
        }
        lastTapTime = now

        switch repPhase {
        case .waitingForPassTap:
            passTapTime = now
            repPhase = .waitingForReturnTap
        case .waitingForReturnTap:
            guard let passTapTime else { return }
            if now.timeIntervalSince(passTapTime) < Self.minTapSeparationSeconds {
                return
            }
            let rawReturn = now.timeIntervalSince(passTapTime)
            let clamped = min(max(rawReturn, Self.clampedReturnTimeRange.lowerBound), Self.clampedReturnTimeRange.upperBound)
            calibrationTimes.append(clamped)
            calibrationCount += 1
            repPhase = .repComplete

            if calibrationCount >= Self.passCount {
                finishCalibration(onCompletedThreePass: onCompletedThreePass)
            } else {
                scheduleNextRep(
                    soundEnabled: soundEnabled,
                    activateAudio: activateAudio,
                    preloadBeep: preloadBeep
                )
            }
        case .betweenReps, .repComplete:
            break
        }
    }

    private func resetForInlineCalibration(nominalTravelSeconds: Double) {
        calibrationSequenceHasStarted = false
        isCalibrating = true
        calibrationCount = 0
        calibrationTimes = []
        passTapTime = nil
        lastTapTime = nil
        activeRepNumber = 1
        repPhase = .betweenReps
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(nominalTravelSeconds)
        calibratedReturnTime = max(0.2, min(nominalTravelSeconds, 5.0))
        cancelPendingBeeps()
    }

    private func applyCachedReturnTime(_ seconds: TimeInterval) {
        calibratedReturnTime = seconds
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(seconds)
        isCalibrating = false
        calibrationCount = 0
        calibrationTimes = []
        passTapTime = nil
        lastTapTime = nil
        repPhase = .betweenReps
        cancelPendingBeeps()
    }

    private func beginRep(
        soundEnabled: Bool,
        activateAudio: @escaping () -> Void,
        preloadBeep: @escaping () -> Void
    ) {
        passTapTime = nil
        repPhase = .waitingForPassTap
        preloadBeep()
        activateAudio()
        PBABeepSoundManager.shared.play(soundEnabled: soundEnabled)
    }

    private func scheduleNextRep(
        soundEnabled: Bool,
        activateAudio: @escaping () -> Void,
        preloadBeep: @escaping () -> Void
    ) {
        repPhase = .betweenReps
        activeRepNumber = calibrationCount + 1
        let delay = Double.random(in: Self.interRepDelayRange)
        let token = sequenceToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sequenceToken == token, self.isCalibrating else { return }
            self.beginRep(
                soundEnabled: soundEnabled,
                activateAudio: activateAudio,
                preloadBeep: preloadBeep
            )
        }
    }

    private func finishCalibration(onCompletedThreePass: @escaping (Double) -> Void) {
        calibrationSequenceHasStarted = false
        cancelPendingBeeps()

        let average: TimeInterval
        if calibrationTimes.isEmpty {
            average = calibratedReturnTime
        } else {
            average = calibrationTimes.reduce(0, +) / Double(calibrationTimes.count)
        }
        let clamped = min(max(average, Self.clampedReturnTimeRange.lowerBound), Self.clampedReturnTimeRange.upperBound)

        calibratedReturnTime = clamped
        CurrentSessionStore.shared.setExpectedBallTravelTimeOverrideSeconds(clamped)
        let playerId = CalibrationPlayerScope.activePlayerId()
        PartnerPassTempoCalibrationStore.save(
            averageTravelTimeSeconds: clamped,
            trainingMode: trainingMode,
            playerId: playerId
        )
        if let playerId {
            UserDefaults.standard.set(clamped, forKey: AppStorageKeys.soloReturnTimeKey(playerId: playerId))
            print("[Calibration] solo saved playerId=\(playerId.uuidString.lowercased()) returnTime=\(clamped)")
        } else {
            print("[Calibration] solo finish — no active playerId; value not persisted to UserDefaults")
        }
        isCalibrating = false
        calibrationCount = 0
        calibrationTimes = []
        passTapTime = nil
        lastTapTime = nil
        repPhase = .betweenReps

        let completion = inlineCalibrationCompletion
        inlineCalibrationCompletion = nil
        if let completion {
            completion(clamped)
        } else {
            onCompletedThreePass(clamped)
        }
    }
}
