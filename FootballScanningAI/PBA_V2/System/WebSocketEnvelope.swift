//
//  WebSocketEnvelope.swift
//  FootballScanningAI
//
//  Wire envelope for PBA messages over WebSocket. `payload` is JSON bytes for `TwoMinuteMessage`.
//

import Foundation

struct WebSocketEnvelope: Codable {
    let version: Int
    let sessionId: String
    let type: String
    let payload: Data

    init(sessionId: String, payload: Data) {
        self.version = 1
        self.sessionId = sessionId
        self.type = "twoMinute"
        self.payload = payload
    }
}

extension WebSocketEnvelope {
    /// Builds envelope with `payload` = JSON-encoded `TwoMinuteMessage`.
    init(sessionId: String, message: TwoMinuteMessage) throws {
        let encoder = JSONEncoder()
        let payload = try encoder.encode(message)
        self.init(sessionId: sessionId, payload: payload)
    }
}
