//
//  WebSocketSessionConfig.swift
//  FootballScanningAI
//
//  Minimum connection context for relay WebSocket (scaffolding).
//

import Foundation

struct WebSocketSessionConfig {
    let url: URL
    let sessionId: String
    let authToken: String?
}
