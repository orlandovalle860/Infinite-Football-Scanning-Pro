//
//  PartnerSetupLog.swift
//  FootballScanningAI
//
//  Release-safe Partner Mode setup diagnostics. No tokens, URLs, or secrets.
//

import Foundation

enum PartnerSetupLog {
    enum Role: String {
        case display = "DISPLAY"
        case coach = "COACH"
    }

    @MainActor
    static func display(_ message: String) {
        emit(.display, message)
    }

    @MainActor
    static func coach(_ message: String) {
        guard !CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        emit(.coach, message)
    }

    /// Last two characters only — never the full join code.
    static func joinCodeSuffix(_ code: String?) -> String {
        guard let code, code.count >= 2 else { return "nil" }
        return String(code.suffix(2))
    }

    @MainActor
    static func activityTag() -> String {
        let id = TrainingPartnerConnectionCoordinator.shared.currentTimedSessionActivityId
            ?? TimedSessionController.shared.currentActivity?.sessionActivityActivityId
            ?? "nil"
        return "activity=\(id)"
    }

    private static var lastLoggedCoachRemoteRepControlEnabled: Bool?

    /// Logs only when ``TimedSessionDisplayIntegration.coachRemoteRepControlEnabled`` flips.
    @MainActor
    static func logCoachRepControlIfChanged() {
        let enabled = TimedSessionDisplayIntegration.coachRemoteRepControlEnabled
        guard lastLoggedCoachRemoteRepControlEnabled != enabled else { return }
        let previous = lastLoggedCoachRemoteRepControlEnabled.map(String.init) ?? "nil"
        lastLoggedCoachRemoteRepControlEnabled = enabled
        coach("coachRemoteRepControlEnabled \(previous)→\(enabled) \(coachRepControlReason()) \(activityTag())")
    }

    /// Mirrors ``TimedSessionDisplayIntegration.coachRemoteRepControlEnabled`` without changing it.
    @MainActor
    static func coachRepControlReason() -> String {
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        let enabled = TimedSessionDisplayIntegration.coachRemoteRepControlEnabled
        if enabled {
            return "coachRemoteRepControlEnabled=true"
        }
        if coordinator.isPartnerTrainingSessionActive {
            var parts: [String] = ["coachRemoteRepControlEnabled=false"]
            if coordinator.currentTimedSessionActivityId == nil {
                parts.append("reason=currentTimedSessionActivityId=nil")
            }
            if !coordinator.isDisplayRepEngineReady {
                parts.append("reason=isDisplayRepEngineReady=false")
            }
            return parts.joined(separator: " ")
        }
        if TimedSessionController.shared.isSessionActive {
            return "coachRemoteRepControlEnabled=true"
        }
        return "coachRemoteRepControlEnabled=false reason=partnerSessionInactive"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func emit(_ role: Role, _ message: String) {
        let ts = timeFormatter.string(from: Date())
        print("[PartnerSetup] \(ts) \(role.rawValue) \(message)")
    }
}
