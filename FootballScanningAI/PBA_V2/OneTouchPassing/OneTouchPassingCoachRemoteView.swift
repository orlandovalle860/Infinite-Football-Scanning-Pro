//
//  OneTouchPassingCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: Coach logs UP / LEFT / RIGHT / DOWN. Any green = correct.
//

import SwiftUI
import AVFoundation
import MultipeerConnectivity

enum OneTouchPassingCoachState {
    case ready
    case logging(repIndex: Int)
    case blockComplete
}

struct OneTouchPassingCoachRemoteView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @StateObject private var remoteService = RemoteService()
    @State private var state: OneTouchPassingCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var volumeTriggerEnabled = true
    @State private var showVolumeEdgeWarning = false

    private let totalReps = 12

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            Color.clear.contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 24) {
                switch state {
                case .ready: readyView
                case .logging(let repIndex): loggingView(repIndex: repIndex)
                case .blockComplete: blockCompleteView
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(volumeTriggerOverlay)
        .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived)) { notification in
            guard let msg = notification.object as? TwoMinuteMessage else { return }
            if case .sessionEnded = msg {
                state = .ready
                volumeTriggerEnabled = true
            }
        }
        .onAppear {
#if DEBUG
            print("[RemoteService] OTP Coach onAppear -> connect()")
#endif
            remoteService.connect()
        }
        .onDisappear {
#if DEBUG
            print("[RemoteService] OTP Coach onDisappear -> disconnect()")
#endif
            remoteService.disconnect()
        }
        .onChange(of: connectionManager.connectedPeerName) { _, newName in
            if newName == nil {
                resetLocalUIForDisconnect(source: "connectedPeerName=nil")
            }
        }
        .onChange(of: connectionManager.connectionState) { _, newState in
            if newState == .disconnected {
                resetLocalUIForDisconnect(source: "connectionState=disconnected")
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Coach — One-Touch Passing (12 reps)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            if connectionManager.connectedPeerName == nil {
                connectionSection
            } else {
                Spacer(minLength: 40)
                Text("Connected to \(connectionManager.connectedPeerName ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Text("Tap NEXT REP to start the next rep on the Display.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    connectionManager.lastError = nil
                    remoteService.sendNextRep(repIndex: currentRepIndex)
                    state = .logging(repIndex: currentRepIndex)
                } label: {
                    Text("NEXT REP")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(Color.yellow)
                        .cornerRadius(18)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 32)
                Text("Rep \(currentRepIndex + 1) of \(totalReps)")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
    }

    private func loggingView(repIndex: Int) -> some View {
        VStack(spacing: 16) {
            Text("Rep \(repIndex + 1) of \(totalReps)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
            Text("When the Display shows CHECK, tap PASS at the strike.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            if showVolumeEdgeWarning {
                Text(CoachRemoteVolumeTriggerConfig.edgeWarningMessage)
                    .font(.caption)
                    .foregroundColor(.orange.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
            Button {
                remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
            } label: {
                Text("PASS")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.yellow)
                    .cornerRadius(16)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)
            Text("Tap the direction the player chose, or ✕ if incorrect.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
            directionPad
            Text("Volume buttons also trigger PASS (use PASS if volume is stuck at the top or bottom).")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var directionPad: some View {
        VStack(spacing: 10) {
            directionButton(gate: .up)
            HStack(spacing: 10) {
                directionButton(gate: .left)
                Button { logIncorrect() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.red.opacity(0.7))
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                directionButton(gate: .right)
            }
            directionButton(gate: .down)
        }
        .frame(height: 200)
    }

    private var connectionSection: some View {
        VStack(spacing: 20) {
            Text("Rep \(currentRepIndex + 1) of \(totalReps)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
            Text("Connect to the device showing the grid (Display).")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if !connectionManager.isBrowsing {
                Button("Connect to Display") {
                    connectionManager.lastError = nil
                    #if DEBUG
                    print("[RemoteService] OTP Coach Connect button -> connect()")
                    #endif
                    remoteService.connect()
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.yellow)
                .cornerRadius(12)
                .padding(.horizontal, 40)
            } else if connectionManager.connectedPeerName == nil {
                if connectionManager.availablePeers.isEmpty {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.2)
                    Text("Searching for Display…").font(.subheadline).foregroundColor(.white.opacity(0.8))
                } else {
                    Text("Select a device to connect:").font(.subheadline).foregroundColor(.white.opacity(0.9))
                    List {
                        ForEach(Array(connectionManager.availablePeers.enumerated()), id: \.offset) { _, peer in
                            Button { connectionManager.invite(peerID: peer) } label: {
                                HStack {
                                    Image(systemName: "tv").foregroundColor(.white.opacity(0.8))
                                    Text(peer.displayName).foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
                Button("Cancel") {
                    #if DEBUG
                    print("[RemoteService] OTP Coach Cancel button -> disconnect()")
                    #endif
                    remoteService.disconnect()
                }
                .foregroundColor(.white.opacity(0.9))
            }
            if let error = connectionManager.lastError {
                Text(error).font(.subheadline).foregroundColor(.orange).multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
        }
        .padding(.top, 60)
    }

    private var volumeTriggerOverlay: some View {
        CoachRemoteVolumeTriggerView(
            connected: connectionManager.connectedPeerName != nil,
            enabled: volumeTriggerEnabled,
            repIndex: { if case .logging(let r) = state { return r }; return nil },
            onTrigger: {
                if case .logging(let repIndex) = state {
                    remoteService.sendPassTriggered(repIndex: repIndex, timestamp: Date())
                }
            },
            onVolumeEdgeWarningChange: { showVolumeEdgeWarning = $0 }
        )
        .id("vol-\(currentRepIndex)-\(state)")
        .allowsHitTesting(false)
        .frame(width: 1, height: 1)
    }

    private var blockCompleteView: some View {
        VStack(spacing: 20) {
            Text("Rep \(totalReps) of \(totalReps)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text("Block complete — check iPad")
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private func directionButton(gate: Gate) -> some View {
        let name: String
        switch gate {
        case .up: name = "arrow.up"
        case .down: name = "arrow.down"
        case .left: name = "arrow.left"
        case .right: name = "arrow.right"
        }
        return Button { logExit(gate) } label: {
            Image(systemName: name)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func logExit(_ gate: Gate) {
        guard case .logging(let repIndex) = state else { return }
        remoteService.sendExitLogged(repIndex: repIndex, gate: gate, timestamp: Date())
        currentRepIndex = repIndex + 1
        state = currentRepIndex >= totalReps ? .blockComplete : .ready
    }

    private func logIncorrect() {
        guard case .logging(let repIndex) = state else { return }
        remoteService.sendIncorrectDecision(repIndex: repIndex, timestamp: Date())
        currentRepIndex = repIndex + 1
        state = currentRepIndex >= totalReps ? .blockComplete : .ready
    }

    private func resetLocalUIForDisconnect(source: String) {
        guard case .logging = state else { return }
#if DEBUG
        print("[OTP Coach] disconnect reset -> state=.ready [\(source)]")
#endif
        state = .ready
        volumeTriggerEnabled = true
    }
}
