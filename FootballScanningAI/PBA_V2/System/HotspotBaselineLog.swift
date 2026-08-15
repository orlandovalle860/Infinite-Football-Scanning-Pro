//
//  HotspotBaselineLog.swift
//  FootballScanningAI
//
//  Diagnostic-only logging for App Store baseline hotspot walk-away repro.
//  Does not change control flow. Never logs full join codes, tokens, or credentialed URLs.
//

import Foundation

enum HotspotBaselineLog {
    static func emit(_ message: String) {
        print("[HotspotBaseline] \(message)")
    }

    /// Last 2 characters of a join code (or "nil" / "short").
    static func joinSuffix(_ code: String?) -> String {
        guard let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "nil" }
        guard raw.count >= 2 else { return "short" }
        return String(raw.suffix(2))
    }

    /// First 8 characters of a relay session id.
    static func sessionSuffix(_ sessionId: String?) -> String {
        guard let raw = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "nil" }
        return String(raw.prefix(8))
    }

    /// Classify safe control / error tokens from a relay frame without printing the full payload.
    static func classifyRelayFrame(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("peer_joined") { return "control.peer_joined" }
        if lower.contains("peer_left") { return "control.peer_left" }
        if lower.contains("display_already_connected") { return "DISPLAY_ALREADY_CONNECTED" }
        if lower.contains("coach_already_connected") { return "COACH_ALREADY_CONNECTED" }
        if lower.contains("coach_slot") { return "COACH_SLOT_TAKEN" }
        if lower.contains("invalid_token") { return "INVALID_TOKEN" }
        if lower.contains("invalid_join") { return "INVALID_JOIN_CODE" }
        if lower.contains("session_not_found") { return "SESSION_NOT_FOUND" }
        if lower.contains("session_expired") { return "SESSION_EXPIRED" }
        if lower.contains("control.error") { return "control.error" }
        if lower.contains("control.ack") { return "control.ack" }
        if lower.contains("\"nextrep\"") || lower.contains("\"kind\":\"nextrep\"") { return "twoMinute.nextRep" }
        return "other"
    }
}
