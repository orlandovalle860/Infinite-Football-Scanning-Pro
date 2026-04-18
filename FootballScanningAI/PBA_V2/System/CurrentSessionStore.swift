//
//  CurrentSessionStore.swift
//  FootballScanningAI
//
//  PBA V2 — On the display device: when a session/drill starts we create a session row and store id + session_activity id here.
//  Completion flow and events/decisions use these ids. Cleared when session ends.
//

import Foundation
import Combine

/// Holds the current display session id and session_activity id (iPad only). Set when session/drill starts, cleared when session ends.
final class CurrentSessionStore: ObservableObject {
    static let shared = CurrentSessionStore()

    @Published private(set) var sessionId: UUID?
    /// Id of the row in session_activities for the current drill. Events and decisions use session_activity_id = currentSessionActivityId.
    @Published private(set) var currentSessionActivityId: UUID?
    @Published private(set) var expectedBallTravelTimeOverrideSeconds: Double?

    /// In-session only, keyed by ``ActivityKind/sessionActivityActivityId``. Omitted entries = 1.0.
    @Published private(set) var decisionTimingCalibrationFactors: [ActivityID: Double] = [:]

    private var calibrationEarlyStreakByActivity: [ActivityID: Int] = [:]
    private var calibrationLateStreakByActivity: [ActivityID: Int] = [:]
    private var factorStorage: [ActivityID: Double] = [:]

    private init() {}

    /// Call when a drill starts. Sets sessionId so the block save and decisions update the same row.
    func setSessionIdOnly(_ id: UUID) {
        sessionId = id
    }

    /// Call when a drill starts after inserting into session_activities; saves the returned id so events and decisions link to the correct block.
    func setCurrentSessionActivityId(_ id: UUID) {
        currentSessionActivityId = id
    }

    /// Optional per-session override from quick pass-tempo calibration on display.
    func setExpectedBallTravelTimeOverrideSeconds(_ value: Double?) {
        expectedBallTravelTimeOverrideSeconds = value
    }

    func calibrationFactor(for activityId: ActivityID) -> Double {
        factorStorage[activityId] ?? 1.0
    }

    func setCalibrationFactor(_ value: Double, for activityId: ActivityID) {
        let clamped = min(SessionTimingCalibration.maxFactor, max(SessionTimingCalibration.minFactor, value))
        if abs(clamped - 1.0) < 1e-9 {
            factorStorage.removeValue(forKey: activityId)
        } else {
            factorStorage[activityId] = clamped
        }
        publishFactors()
    }

    func resetDecisionTimingCalibrationForNewDrillBlock(activityId: ActivityID) {
        factorStorage.removeValue(forKey: activityId)
        calibrationEarlyStreakByActivity.removeValue(forKey: activityId)
        calibrationLateStreakByActivity.removeValue(forKey: activityId)
        publishFactors()
    }

    /// Call after each scored rep with the decision window (expected arrival − decision time).
    func recordDecisionTimingCalibrationSample(decisionWindowSeconds: Double, activityId: ActivityID) {
        let w = decisionWindowSeconds

        if abs(w) <= SessionTimingCalibration.neutralBandMax {
            calibrationEarlyStreakByActivity[activityId] = 0
            calibrationLateStreakByActivity[activityId] = 0
            let current = calibrationFactor(for: activityId)
            var next = current
            if current > 1.0 {
                next = max(1.0, current - SessionTimingCalibration.neutralDecayStep)
            } else if current < 1.0 {
                next = min(1.0, current + SessionTimingCalibration.neutralDecayStep)
            }
            if abs(next - current) > 1e-9 {
                setCalibrationFactor(next, for: activityId)
            } else if abs(current - 1.0) < 1e-9 {
                factorStorage.removeValue(forKey: activityId)
                publishFactors()
            }
            return
        }

        var early = calibrationEarlyStreakByActivity[activityId] ?? 0
        var late = calibrationLateStreakByActivity[activityId] ?? 0

        if w > SessionTimingCalibration.earlyBand {
            early += 1
            late = 0
            if early >= SessionTimingCalibration.streakRequired {
                early = 0
                let f = calibrationFactor(for: activityId)
                let next = f - SessionTimingCalibration.step
                setCalibrationFactor(max(SessionTimingCalibration.minFactor, next), for: activityId)
            }
        } else if w < SessionTimingCalibration.lateBand {
            late += 1
            early = 0
            if late >= SessionTimingCalibration.streakRequired {
                late = 0
                let f = calibrationFactor(for: activityId)
                let next = f + SessionTimingCalibration.step
                setCalibrationFactor(min(SessionTimingCalibration.maxFactor, next), for: activityId)
            }
        } else {
            early = 0
            late = 0
        }

        calibrationEarlyStreakByActivity[activityId] = early
        calibrationLateStreakByActivity[activityId] = late
    }

    func calibratedBallTravelSeconds(baseNominal: Double, activityId: ActivityID) -> Double {
        SessionTimingCalibration.effectiveTravelTime(
            baseNominal: baseNominal,
            factor: calibrationFactor(for: activityId)
        )
    }

    func clear() {
        sessionId = nil
        currentSessionActivityId = nil
        expectedBallTravelTimeOverrideSeconds = nil
        factorStorage.removeAll()
        calibrationEarlyStreakByActivity.removeAll()
        calibrationLateStreakByActivity.removeAll()
        publishFactors()
    }

    private func publishFactors() {
        decisionTimingCalibrationFactors = factorStorage
    }
}
