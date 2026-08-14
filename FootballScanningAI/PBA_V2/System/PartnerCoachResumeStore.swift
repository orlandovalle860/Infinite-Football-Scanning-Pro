//
//  PartnerCoachResumeStore.swift
//  FootballScanningAI
//
//  Durable coach Partner resume: non-secret metadata in UserDefaults + coach token in Keychain.
//

import Foundation

/// Non-secret fields needed to reconnect a coach to an existing relay room after process death.
struct PartnerCoachResumeRecord: Codable, Equatable {
    var schemaVersion: Int
    var sessionId: String
    var joinCode: String
    /// Public relay `wsUrl` from create/join (not a secret).
    var wsUrl: String
    var activityId: String?
    /// True only while a live Partner timed session may still be recoverable on the display.
    var isRecoverableLivePartnerSession: Bool
    var savedAt: Date
    var expiresAt: Date?

    static let currentSchemaVersion = 1
}

enum PartnerCoachResumeStore {
    private static let metadataKey = "partnerCoachResume.metadata.v1"
    /// Client-side max age if relay did not provide expiresAt (aligns with room TTL order of magnitude).
    private static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    static func save(
        sessionId: String,
        joinCode: String,
        wsUrl: String,
        coachToken: String,
        activityId: String?,
        isRecoverableLivePartnerSession: Bool,
        expiresAt: Date?
    ) {
        guard PartnerCoachResumeKeychain.saveCoachToken(coachToken) else {
            PartnerSetupLog.emitResume("resume record save FAILED keychain")
            return
        }
        let record = PartnerCoachResumeRecord(
            schemaVersion: PartnerCoachResumeRecord.currentSchemaVersion,
            sessionId: sessionId,
            joinCode: joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            wsUrl: wsUrl,
            activityId: activityId,
            isRecoverableLivePartnerSession: isRecoverableLivePartnerSession,
            savedAt: Date(),
            expiresAt: expiresAt
        )
        guard let data = try? JSONEncoder().encode(record) else {
            PartnerSetupLog.emitResume("resume record save FAILED encode")
            return
        }
        UserDefaults.standard.set(data, forKey: metadataKey)
        PartnerSetupLog.emitResume(
            "resume record saved joinSuffix=\(PartnerSetupLog.joinCodeSuffix(record.joinCode)) sessionSuffix=\(sessionSuffix(record.sessionId)) recoverableLive=\(record.isRecoverableLivePartnerSession) activity=\(record.activityId ?? "nil")"
        )
    }

    /// Updates non-secret fields without rotating the Keychain token.
    static func updateMetadata(
        activityId: String? = nil,
        isRecoverableLivePartnerSession: Bool? = nil,
        clearActivityId: Bool = false
    ) {
        guard var record = loadRawMetadata() else { return }
        if clearActivityId {
            record.activityId = nil
        } else if let activityId {
            record.activityId = activityId
        }
        if let isRecoverableLivePartnerSession {
            record.isRecoverableLivePartnerSession = isRecoverableLivePartnerSession
        }
        record.savedAt = Date()
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: metadataKey)
        PartnerSetupLog.emitResume(
            "resume record updated joinSuffix=\(PartnerSetupLog.joinCodeSuffix(record.joinCode)) recoverableLive=\(record.isRecoverableLivePartnerSession) activity=\(record.activityId ?? "nil")"
        )
    }

    /// Valid resume for cold-start live recovery (token present, not expired, recoverable flag).
    static func loadValidLiveResume() -> (record: PartnerCoachResumeRecord, coachToken: String)? {
        guard let record = loadRawMetadata() else { return nil }
        PartnerSetupLog.emitResume(
            "resume record loaded joinSuffix=\(PartnerSetupLog.joinCodeSuffix(record.joinCode)) sessionSuffix=\(sessionSuffix(record.sessionId)) recoverableLive=\(record.isRecoverableLivePartnerSession) activity=\(record.activityId ?? "nil")"
        )
        guard record.schemaVersion == PartnerCoachResumeRecord.currentSchemaVersion else {
            clear(reason: "schema_mismatch")
            return nil
        }
        guard record.isRecoverableLivePartnerSession else { return nil }
        if isExpired(record) {
            clear(reason: "expired")
            return nil
        }
        guard let token = PartnerCoachResumeKeychain.loadCoachToken(), !token.isEmpty else {
            clear(reason: "missing_token")
            return nil
        }
        guard !record.sessionId.isEmpty, !record.joinCode.isEmpty, !record.wsUrl.isEmpty else {
            clear(reason: "incomplete")
            return nil
        }
        return (record, token)
    }

    /// Credentials for same-process reconnect without POST /join (may be non-live recoverable).
    static func loadCredentialsForReconnect() -> (record: PartnerCoachResumeRecord, coachToken: String)? {
        guard let record = loadRawMetadata() else { return nil }
        if isExpired(record) {
            clear(reason: "expired")
            return nil
        }
        guard let token = PartnerCoachResumeKeychain.loadCoachToken(), !token.isEmpty else { return nil }
        guard !record.sessionId.isEmpty, !record.wsUrl.isEmpty else { return nil }
        return (record, token)
    }

    static func clear(reason: String) {
        let had = UserDefaults.standard.data(forKey: metadataKey) != nil
            || PartnerCoachResumeKeychain.loadCoachToken() != nil
        UserDefaults.standard.removeObject(forKey: metadataKey)
        PartnerCoachResumeKeychain.clearCoachToken()
        if had {
            PartnerSetupLog.emitResume("stale resume record cleared reason=\(reason)")
        }
    }

    private static func loadRawMetadata() -> PartnerCoachResumeRecord? {
        guard let data = UserDefaults.standard.data(forKey: metadataKey) else { return nil }
        return try? JSONDecoder().decode(PartnerCoachResumeRecord.self, from: data)
    }

    private static func isExpired(_ record: PartnerCoachResumeRecord) -> Bool {
        let now = Date()
        if let expiresAt = record.expiresAt, now > expiresAt { return true }
        if now.timeIntervalSince(record.savedAt) > defaultMaxAge { return true }
        return false
    }

    private static func sessionSuffix(_ sessionId: String) -> String {
        sessionId.count >= 4 ? String(sessionId.suffix(4)) : sessionId
    }
}

extension PartnerSetupLog {
    /// Resume logs are coach-side; allow from any role so Keychain save during join is visible.
    static func emitResume(_ message: String) {
        let ts = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[PartnerSetup] \(formatter.string(from: ts)) COACH \(message)")
    }
}
