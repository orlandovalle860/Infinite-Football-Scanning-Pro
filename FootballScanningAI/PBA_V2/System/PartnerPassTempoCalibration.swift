import SwiftUI

enum PartnerPassTempoCalibrationStore {
    private static let legacyAverageKey = "partnerPassTempoCalibration.averageTravelTimeSeconds"
    private static let legacyAtKey = "partnerPassTempoCalibration.savedAt"
    private static let legacyModeKey = "partnerPassTempoCalibration.trainingMode"
    private static let keyPrefix = "partnerPassTempoCalibration."
    static let defaultAverageTravelTimeSeconds: Double = 0.7

    private static func averageKey(playerId: UUID) -> String {
        "\(keyPrefix)\(playerId.uuidString.lowercased()).averageTravelTimeSeconds"
    }

    private static func savedAtKey(playerId: UUID) -> String {
        "\(keyPrefix)\(playerId.uuidString.lowercased()).savedAt"
    }

    private static func modeKey(playerId: UUID) -> String {
        "\(keyPrefix)\(playerId.uuidString.lowercased()).trainingMode"
    }

    /// Migrates pre–per-player global keys onto this player once, then removes the globals.
    private static func migrateLegacyIfNeeded(for playerId: UUID) {
        guard UserDefaults.standard.object(forKey: averageKey(playerId: playerId)) == nil,
              UserDefaults.standard.object(forKey: legacyAverageKey) != nil else { return }
        let avg = UserDefaults.standard.double(forKey: legacyAverageKey)
        UserDefaults.standard.set(avg, forKey: averageKey(playerId: playerId))
        if UserDefaults.standard.object(forKey: legacyAtKey) != nil {
            UserDefaults.standard.set(
                UserDefaults.standard.double(forKey: legacyAtKey),
                forKey: savedAtKey(playerId: playerId)
            )
        }
        if let mode = UserDefaults.standard.string(forKey: legacyModeKey) {
            UserDefaults.standard.set(mode, forKey: modeKey(playerId: playerId))
        }
        UserDefaults.standard.removeObject(forKey: legacyAverageKey)
        UserDefaults.standard.removeObject(forKey: legacyAtKey)
        UserDefaults.standard.removeObject(forKey: legacyModeKey)
    }

    static func save(
        averageTravelTimeSeconds: Double?,
        trainingMode: TrainingMode? = nil,
        playerId: UUID? = nil
    ) {
        guard let averageTravelTimeSeconds else { return }
        guard let playerId = playerId ?? CalibrationPlayerScope.activePlayerId() else {
            print("[Calibration] partner save skipped — no active playerId")
            return
        }
        UserDefaults.standard.set(averageTravelTimeSeconds, forKey: averageKey(playerId: playerId))
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: savedAtKey(playerId: playerId))
        if let trainingMode {
            UserDefaults.standard.set(trainingMode.rawValue, forKey: modeKey(playerId: playerId))
        }
    }

    static func savedAverageTravelTimeSeconds(playerId: UUID? = nil) -> Double? {
        guard let playerId = playerId ?? CalibrationPlayerScope.activePlayerId() else { return nil }
        migrateLegacyIfNeeded(for: playerId)
        guard UserDefaults.standard.object(forKey: averageKey(playerId: playerId)) != nil else { return nil }
        return UserDefaults.standard.double(forKey: averageKey(playerId: playerId))
    }

    static func seededAverageTravelTimeSeconds(playerId: UUID? = nil) -> Double {
        savedAverageTravelTimeSeconds(playerId: playerId) ?? defaultAverageTravelTimeSeconds
    }

    /// Silent rolling refinement used by partner sessions (no UI/blocking).
    @discardableResult
    static func updateRollingAverageTravelTime(
        observedSeconds: Double,
        trainingMode: TrainingMode? = .partner,
        smoothingFactor: Double = 0.25,
        playerId: UUID? = nil
    ) -> Double {
        let clampedObserved = min(1.5, max(0.35, observedSeconds))
        let previous = seededAverageTravelTimeSeconds(playerId: playerId)
        let alpha = min(0.6, max(0.05, smoothingFactor))
        let updated = previous + (clampedObserved - previous) * alpha
        save(averageTravelTimeSeconds: updated, trainingMode: trainingMode, playerId: playerId)
        return updated
    }

    static var hasSavedCalibration: Bool {
        savedAverageTravelTimeSeconds() != nil
    }

    static func hasSavedCalibration(playerId: UUID) -> Bool {
        savedAverageTravelTimeSeconds(playerId: playerId) != nil
    }

    /// Clears all pass-tempo calibration (legacy + every player). Call on account deletion.
    static func clearSavedCalibration() {
        UserDefaults.standard.removeObject(forKey: legacyAverageKey)
        UserDefaults.standard.removeObject(forKey: legacyAtKey)
        UserDefaults.standard.removeObject(forKey: legacyModeKey)
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Clears calibration for one player (e.g. player deleted).
    static func clearSavedCalibration(playerId: UUID) {
        UserDefaults.standard.removeObject(forKey: averageKey(playerId: playerId))
        UserDefaults.standard.removeObject(forKey: savedAtKey(playerId: playerId))
        UserDefaults.standard.removeObject(forKey: modeKey(playerId: playerId))
    }

    static func lastCalibratedDate(playerId: UUID? = nil) -> Date? {
        guard let playerId = playerId ?? CalibrationPlayerScope.activePlayerId() else { return nil }
        migrateLegacyIfNeeded(for: playerId)
        guard UserDefaults.standard.object(forKey: savedAtKey(playerId: playerId)) != nil else { return nil }
        return Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: savedAtKey(playerId: playerId)))
    }

    static func lastCalibratedLabel(playerId: UUID? = nil) -> String? {
        guard let date = lastCalibratedDate(playerId: playerId) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func lastCalibratedTrainingMode(playerId: UUID? = nil) -> TrainingMode? {
        guard let playerId = playerId ?? CalibrationPlayerScope.activePlayerId() else { return nil }
        migrateLegacyIfNeeded(for: playerId)
        guard let raw = UserDefaults.standard.string(forKey: modeKey(playerId: playerId)) else { return nil }
        return TrainingMode(rawValue: raw)
    }

    static func requiresCalibration(for trainingMode: TrainingMode, playerId: UUID? = nil) -> Bool {
        guard let playerId = playerId ?? CalibrationPlayerScope.activePlayerId() else { return true }
        guard hasSavedCalibration(playerId: playerId) else { return true }
        // Backward compatibility: older installs may have a saved average without stored mode metadata.
        guard let lastMode = lastCalibratedTrainingMode(playerId: playerId) else { return false }
        return lastMode != trainingMode
    }
}

enum PartnerPassCalibrationStep {
    case waitingForPass
    case waitingForArrival
}

struct PartnerPassTempoCalibrationTracker {
    private(set) var step: PartnerPassCalibrationStep = .waitingForPass
    private(set) var sampleCount: Int = 0
    private(set) var travelTimes: [Double] = []
    private var passTimestamp: Date?

    let minimumSamples: Int
    let targetSamples: Int

    init(minimumSamples: Int = 2, targetSamples: Int = 3) {
        self.minimumSamples = minimumSamples
        self.targetSamples = targetSamples
    }

    mutating func reset() {
        step = .waitingForPass
        sampleCount = 0
        travelTimes.removeAll(keepingCapacity: true)
        passTimestamp = nil
    }

    mutating func handlePassTap(timestamp: Date) {
        passTimestamp = timestamp
        step = .waitingForArrival
    }

    mutating func handleArrivalTap(timestamp: Date) {
        guard let passTimestamp else { return }
        let travelTime = timestamp.timeIntervalSince(passTimestamp)
        if travelTime > 0 {
            travelTimes.append(travelTime)
            sampleCount = travelTimes.count
        }
        self.passTimestamp = nil
        step = .waitingForPass
    }

    var canFinish: Bool {
        sampleCount >= minimumSamples
    }

    var reachedTarget: Bool {
        sampleCount >= targetSamples
    }

    var averageTravelTime: Double? {
        guard !travelTimes.isEmpty else { return nil }
        return travelTimes.reduce(0, +) / Double(travelTimes.count)
    }
}

struct DisplayCalibrationWaitingView: View {
    let sampleCount: Int
    let targetSamples: Int

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 11.0 / 255.0, green: 15.0 / 255.0, blue: 26.0 / 255.0),
                    Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()
                Text("Ready")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Waiting for coach...")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.82))
                if sampleCount > 0 {
                    Text("Calibration \(sampleCount) of \(targetSamples)")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.yellow)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}
