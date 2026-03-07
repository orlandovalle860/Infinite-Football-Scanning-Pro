//
//  DribbleOrPassCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: Coach logs UP / LEFT / RIGHT / DOWN. DOWN is never correct.
//

import SwiftUI
import AVFoundation
import MediaPlayer

enum DribbleOrPassCoachState {
    case ready
    case logging(repIndex: Int)
    case blockComplete
}

/// Order: PASS → first touch (optional) → exit.
private enum DOPLoggingStep {
    case pass
    case firstTouch
    case exit
}

struct DribbleOrPassCoachRemoteView: View {
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @State private var state: DribbleOrPassCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var volumeTriggerEnabled = true
    @State private var loggingStep: DOPLoggingStep = .pass
    @State private var showFirstTouchPrompt = false
    @State private var pendingRepIndex = 0

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
        .overlay(firstTouchPromptOverlay)
        .onAppear { multipeerManager.startBrowsing() }
        .onDisappear { multipeerManager.stopBrowsing() }
        .preferredColorScheme(.dark)
        .navigationTitle("Coach — Dribble or Pass (12 reps)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            if multipeerManager.connectedPeerName == nil {
                connectionSection
            } else {
                Spacer(minLength: 40)
                Text("Connected to \(multipeerManager.connectedPeerName ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Text("Tap NEXT REP to start the next rep on the Display.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    multipeerManager.lastError = nil
                    multipeerManager.sendTwoMinuteMessage(.nextRep(repIndex: currentRepIndex))
                    loggingStep = .pass
                    showFirstTouchPrompt = false
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
            if loggingStep == .pass {
                Text("When the Display beeps, tap PASS or press volume at strike.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                Button {
                    multipeerManager.sendTwoMinuteMessage(.passTriggered(repIndex: repIndex, timestamp: Date()))
                    pendingRepIndex = repIndex
                    loggingStep = .firstTouch
                    showFirstTouchPrompt = true
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
                Text("Volume button also triggers pass.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            if loggingStep == .exit {
                Text("Log direction (Green = pass, Clear = dribble). Down = backward (always incorrect).")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                directionPad(repIndex: repIndex)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func directionPad(repIndex: Int) -> some View {
        VStack(spacing: 10) {
            directionButton(repIndex: repIndex, gate: .up)
            HStack(spacing: 10) {
                directionButton(repIndex: repIndex, gate: .left)
                directionButton(repIndex: repIndex, gate: .right)
            }
            directionButton(repIndex: repIndex, gate: .down)
        }
        .frame(height: 170)
    }

    private var connectionSection: some View {
        VStack(spacing: 20) {
            Text("Connect to the device showing the grid (Display).")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if !multipeerManager.isBrowsing {
                Button("Connect to Display") {
                    multipeerManager.lastError = nil
                    multipeerManager.startBrowsing()
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.yellow)
                .cornerRadius(12)
                .padding(.horizontal, 40)
            } else if multipeerManager.connectedPeerName == nil {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.2)
                Text("Searching for Display…").font(.subheadline).foregroundColor(.white.opacity(0.8))
                Button("Cancel") { multipeerManager.stopBrowsing() }.foregroundColor(.white.opacity(0.9))
            }
            if let error = multipeerManager.lastError {
                Text(error).font(.subheadline).foregroundColor(.orange).multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
        }
        .padding(.top, 60)
    }

    private var volumeTriggerOverlay: some View {
        DribbleOrPassVolumeTriggerView(
            connected: multipeerManager.connectedPeerName != nil,
            enabled: volumeTriggerEnabled && loggingStep == .pass,
            repIndex: { if case .logging(let r) = state { return r }; return nil },
            onTrigger: {
                if case .logging(let repIndex) = state, loggingStep == .pass {
                    multipeerManager.sendTwoMinuteMessage(.passTriggered(repIndex: repIndex, timestamp: Date()))
                    pendingRepIndex = repIndex
                    loggingStep = .firstTouch
                    showFirstTouchPrompt = true
                }
            }
        )
        .allowsHitTesting(false)
        .frame(width: 1, height: 1)
    }

    private var blockCompleteView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Block complete — check iPad")
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private func directionButton(repIndex: Int, gate: Gate) -> some View {
        let name: String
        switch gate {
        case .up: name = "arrow.up"
        case .down: name = "arrow.down"
        case .left: name = "arrow.left"
        case .right: name = "arrow.right"
        }
        return Button { logExit(repIndex: repIndex, gate: gate) } label: {
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

    private func logExit(repIndex: Int, gate: Gate) {
        guard case .logging(let ri) = state, ri == repIndex, loggingStep == .exit else { return }
        multipeerManager.sendTwoMinuteMessage(.exitLogged(repIndex: repIndex, gate: gate, timestamp: Date()))
        advanceToNextRep(after: repIndex)
    }

    private func advanceToNextRep(after repIndex: Int) {
        showFirstTouchPrompt = false
        loggingStep = .pass
        currentRepIndex = repIndex + 1
        state = currentRepIndex >= totalReps ? .blockComplete : .ready
    }

    private func logFirstTouch(_ gate: Gate) {
        multipeerManager.sendTwoMinuteMessage(.firstTouchLogged(repIndex: pendingRepIndex, gate: gate, timestamp: Date()))
        showFirstTouchPrompt = false
        loggingStep = .exit
    }

    private func skipFirstTouch() {
        showFirstTouchPrompt = false
        loggingStep = .exit
    }

    @ViewBuilder
    private var firstTouchPromptOverlay: some View {
        if showFirstTouchPrompt {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { }
            VStack(spacing: 20) {
                Text("First touch?")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Optional — tap direction or Skip.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                VStack(spacing: 16) {
                    Button { logFirstTouch(.up) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    HStack(spacing: 16) {
                        Button { logFirstTouch(.left) } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        Button { logFirstTouch(.right) } label: {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Button { logFirstTouch(.down) } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 32)
                Button("Skip") {
                    skipFirstTouch()
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(28)
            .background(Color(red: 0.12, green: 0.12, blue: 0.18))
            .cornerRadius(20)
            .padding(40)
        }
    }
}

private struct DribbleOrPassVolumeTriggerView: UIViewRepresentable {
    let connected: Bool
    let enabled: Bool
    let repIndex: () -> Int?
    let onTrigger: () -> Void
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ uiView: UIView, context: Context) {
        guard connected, enabled else { context.coordinator.stopPolling(); return }
        context.coordinator.onTrigger = onTrigger
        context.coordinator.repIndex = repIndex
        context.coordinator.startPolling()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        var timer: Timer?
        var lastVolume: Float = 0
        var savedVolume: Float = 0
        var onTrigger: (() -> Void) = {}
        var repIndex: (() -> Int?) = { nil }
        var startGeneration: Int = 0
        func startPolling() {
            guard timer == nil else { return }
            do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
            lastVolume = AVAudioSession.sharedInstance().outputVolume
            savedVolume = lastVolume
            startGeneration += 1
            let gen = startGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.timer == nil, self.startGeneration == gen else { return }
                self.lastVolume = AVAudioSession.sharedInstance().outputVolume
                self.savedVolume = self.lastVolume
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.checkVolume() }
                RunLoop.main.add(self.timer!, forMode: .common)
            }
        }
        func stopPolling() { startGeneration += 1; timer?.invalidate(); timer = nil }
        private func checkVolume() {
            let current = AVAudioSession.sharedInstance().outputVolume
            if abs(current - lastVolume) > 0.01 {
                lastVolume = current
                onTrigger()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in MPVolumeView.setVolume(self?.savedVolume ?? 0.5) }
            }
        }
    }
}
