//
//  CueTimingDebugLog.swift
//  FootballScanningAI
//
//  Temporary audit logging for decision-cue visibility windows (engine-driven).
//  Prefix: [CueTiming-Debug]
//

import Foundation

enum CueTimingDebugLog {
    /// Engine begins the fixed visibility window for decision cues (wedge/greens/ball).
    static func logVisible(activity: String, repIndex: Int, configuredWindowSeconds: Double?, note: String = "") {
        let t = Date()
        let cfg = configuredWindowSeconds.map { String(format: "%.4f", $0) } ?? "nil"
        let extra = note.isEmpty ? "" : " note=\(note)"
        print("[CueTiming-Debug] event=visible activity=\(activity) repIndex=\(repIndex) timestamp=\(t.timeIntervalSince1970) configuredWindowSeconds=\(cfg)\(extra)")
    }

    /// Decision cues end (timer, coach log, etc.).
    static func logHidden(activity: String, repIndex: Int, visibleAt: Date?, hiddenAt: Date, reason: String) {
        let vis = visibleAt ?? hiddenAt
        let ms = max(0, hiddenAt.timeIntervalSince(vis) * 1000)
        print("[CueTiming-Debug] event=hidden activity=\(activity) repIndex=\(repIndex) visibleTimestamp=\(vis.timeIntervalSince1970) hiddenTimestamp=\(hiddenAt.timeIntervalSince1970) durationMs=\(String(format: "%.1f", ms)) reason=\(reason)")
    }
}
