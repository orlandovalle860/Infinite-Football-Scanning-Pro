//
//  LifecycleReconnectDebug.swift
//  FootballScanningAI
//
//  DEBUG: relay reconnect / resync tracing for iOS lifecycle (background, calls, app switch).
//

import Foundation

enum LifecycleReconnectDebug {
    private static let prefix = "[LifecycleReconnect-Debug]"

    static func logBackgroundEntered(source: String) {
        #if DEBUG
        print("\(prefix) background_entered source=\(source)")
        #endif
    }

    static func logForegroundEntered(source: String) {
        #if DEBUG
        print("\(prefix) foreground_entered source=\(source)")
        #endif
    }

    static func logWillResignActive() {
        #if DEBUG
        print("\(prefix) will_resign_active")
        #endif
    }

    static func logSocketState(role: String, before: String, after: String) {
        #if DEBUG
        print("\(prefix) socket_state role=\(role) before=\(before) after=\(after)")
        #endif
    }

    static func logReconnectAttempt(context: String) {
        #if DEBUG
        print("\(prefix) reconnect_attempt context=\(context)")
        #endif
    }

    static func logReconnectResult(context: String, success: Bool, detail: String) {
        #if DEBUG
        print("\(prefix) reconnect_result context=\(context) success=\(success) detail=\(detail)")
        #endif
    }

    static func logResyncPayload(_ description: String) {
        #if DEBUG
        print("\(prefix) resync_payload \(description)")
        #endif
    }

    static func logRejoinRequired(reason: String) {
        #if DEBUG
        print("\(prefix) rejoin_required reason=\(reason)")
        #endif
    }
}
