//
//  TwoMinuteSessionTransport.swift
//  FootballScanningAI
//
//  PBA V2 — Two Minute partner: transport mode + factory (Multipeer vs relay WebSocket).
//

import Foundation

/// Transport used for a Two Minute **partner** session (one mode per session; no mid-session fallback).
enum SessionTransportMode: Equatable {
    case multipeer
    case relayWebSocket
}

enum TwoMinuteSessionTransport {
    /// Initial transport before relay join completes (coach only). Multipeer uses real transport immediately.
    static func makeInitial(for mode: SessionTransportMode) -> RemoteTransport {
        switch mode {
        case .multipeer:
            return MultipeerRemoteTransport()
        case .relayWebSocket:
            return RelayPendingRemoteTransport()
        }
    }
}

/// Placeholder until HTTP join + `WebSocketRemoteTransport` is installed via `RemoteService.replaceTransport`.
final class RelayPendingRemoteTransport: RemoteTransport {
    var connectionState: ConnectionState { .disconnected }
    var onConnectionStateChanged: ((ConnectionState) -> Void)?
    var onTwoMinuteMessageReceived: ((TwoMinuteMessage) -> Void)?

    func connect() {}
    func disconnect() {}
    func send(_ message: TwoMinuteMessage) {}
}
