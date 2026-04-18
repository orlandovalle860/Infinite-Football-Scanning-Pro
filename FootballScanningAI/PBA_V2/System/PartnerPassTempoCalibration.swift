import SwiftUI

enum PartnerPassTempoCalibrationStore {
    private static let storedAverageKey = "partnerPassTempoCalibration.averageTravelTimeSeconds"
    private static let storedAtKey = "partnerPassTempoCalibration.savedAt"
    private static let storedModeKey = "partnerPassTempoCalibration.trainingMode"
    static let defaultAverageTravelTimeSeconds: Double = 0.7

    static func save(averageTravelTimeSeconds: Double?, trainingMode: TrainingMode? = nil) {
        guard let averageTravelTimeSeconds else { return }
        UserDefaults.standard.set(averageTravelTimeSeconds, forKey: storedAverageKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: storedAtKey)
        if let trainingMode {
            UserDefaults.standard.set(trainingMode.rawValue, forKey: storedModeKey)
        }
    }

    static func savedAverageTravelTimeSeconds() -> Double? {
        guard UserDefaults.standard.object(forKey: storedAverageKey) != nil else { return nil }
        return UserDefaults.standard.double(forKey: storedAverageKey)
    }

    static func seededAverageTravelTimeSeconds() -> Double {
        savedAverageTravelTimeSeconds() ?? defaultAverageTravelTimeSeconds
    }

    /// Silent rolling refinement used by partner sessions (no UI/blocking).
    @discardableResult
    static func updateRollingAverageTravelTime(
        observedSeconds: Double,
        trainingMode: TrainingMode? = .partner,
        smoothingFactor: Double = 0.25
    ) -> Double {
        let clampedObserved = min(1.5, max(0.35, observedSeconds))
        let previous = seededAverageTravelTimeSeconds()
        let alpha = min(0.6, max(0.05, smoothingFactor))
        let updated = previous + (clampedObserved - previous) * alpha
        save(averageTravelTimeSeconds: updated, trainingMode: trainingMode)
        return updated
    }

    static var hasSavedCalibration: Bool {
        savedAverageTravelTimeSeconds() != nil
    }

    static func lastCalibratedDate() -> Date? {
        guard UserDefaults.standard.object(forKey: storedAtKey) != nil else { return nil }
        return Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: storedAtKey))
    }

    static func lastCalibratedLabel() -> String? {
        guard let date = lastCalibratedDate() else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func lastCalibratedTrainingMode() -> TrainingMode? {
        guard let raw = UserDefaults.standard.string(forKey: storedModeKey) else { return nil }
        return TrainingMode(rawValue: raw)
    }

    static func requiresCalibration(for trainingMode: TrainingMode) -> Bool {
        guard hasSavedCalibration else { return true }
        // Backward compatibility: older installs may have a saved average without stored mode metadata.
        // Treat that as valid calibration to avoid forcing users into unexpected recalibration screens.
        guard let lastMode = lastCalibratedTrainingMode() else { return false }
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

