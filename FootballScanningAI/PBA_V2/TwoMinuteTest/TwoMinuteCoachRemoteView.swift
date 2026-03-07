//
//  TwoMinuteCoachRemoteView.swift
//  FootballScanningAI
//
//  PBA V2 — Coach remote: Connect, NEXT REP, PASS (button + volume trigger), arrow log.
//

import SwiftUI
import AVFoundation
import MediaPlayer

enum TwoMinuteCoachState: Equatable {
    case ready
    case logging(repIndex: Int)
    case complete
}

struct TwoMinuteCoachRemoteView: View {
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @State private var state: TwoMinuteCoachState = .ready
    @State private var currentRepIndex = 0
    @State private var volumeTriggerEnabled = true

    private let totalReps = 10

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
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { }
            VStack(spacing: 24) {
                switch state {
                case .ready: readyView
                case .logging(let repIndex): loggingView(repIndex: repIndex)
                case .complete: completeView
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(volumeTriggerOverlay)
        .onDisappear { multipeerManager.stopBrowsing() }
        .onChange(of: state) { _, newState in
            if case .complete = newState {
                UserDefaults.standard.set(true, forKey: "hasCompletedInitialTest")
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Coach — 2-Minute (10 reps)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            if multipeerManager.connectedPeerName == nil {
                connectionSection
            } else {
                Spacer(minLength: 40)
                if let name = multipeerManager.connectedPeerName {
                    Text("Connected to \(name)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                Text("Tap NEXT REP to start the next rep on the Display.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    multipeerManager.lastError = nil
                    multipeerManager.sendTwoMinuteMessage(.nextRep(repIndex: currentRepIndex))
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
            Text("When the Display beeps, tap PASS or press volume at strike.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Button {
                multipeerManager.sendTwoMinuteMessage(.passTriggered(repIndex: repIndex, timestamp: Date()))
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

            Text("Tap arrow when player exits:")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))

            directionPad

            Text("Volume button also triggers pass.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var directionPad: some View {
        VStack(spacing: 10) {
            Button { logExit(.up) } label: { arrowLabel("arrow.up") }
                .buttonStyle(PlainButtonStyle())
            HStack(spacing: 10) {
                Button { logExit(.left) } label: { arrowLabel("arrow.left") }
                    .buttonStyle(PlainButtonStyle())
                Button { logExit(.right) } label: { arrowLabel("arrow.right") }
                    .buttonStyle(PlainButtonStyle())
            }
            Button { logExit(.down) } label: { arrowLabel("arrow.down") }
                .buttonStyle(PlainButtonStyle())
        }
        .frame(height: 170)
    }

    private func arrowLabel(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.12))
            .cornerRadius(12)
            .contentShape(Rectangle())
    }

    private var connectionSection: some View {
        VStack(spacing: 20) {
            Text("Connect to the device showing the grid (Display). Keep both devices nearby and allow Local Network if prompted.")
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
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                Text("Searching for Display…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Text("Make sure the other device chose \"Display\" and is on the grid screen.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Button("Cancel") {
                    multipeerManager.stopBrowsing()
                }
                .foregroundColor(.white.opacity(0.9))
            }

            if let error = multipeerManager.lastError {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 60)
    }

    private var volumeTriggerOverlay: some View {
        TwoMinuteVolumeTriggerView(
            connected: multipeerManager.connectedPeerName != nil,
            enabled: volumeTriggerEnabled,
            repIndex: { if case .logging(let r) = state { return r }; return nil },
            onTrigger: {
                if case .logging(let repIndex) = state {
                    multipeerManager.sendTwoMinuteMessage(.passTriggered(repIndex: repIndex, timestamp: Date()))
                }
            }
        )
        .allowsHitTesting(false)
        .frame(width: 1, height: 1)
    }

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Test complete")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Results are on the iPad.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Text("Choose the next activity (e.g. Playing Away From Pressure) below.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            NavigationLink(destination: CoachRemoteHubView(settingsViewModel: settingsViewModel, profileManager: profileManager)) {
                Text("Open Coach Remote")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
    }

    private func logExit(_ gate: Gate) {
        if case .logging(let repIndex) = state {
            multipeerManager.sendTwoMinuteMessage(.exitLogged(repIndex: repIndex, gate: gate, timestamp: Date()))
            currentRepIndex = repIndex + 1
            state = currentRepIndex >= totalReps ? .complete : .ready
        }
    }
}

// MARK: - Volume button trigger

private struct TwoMinuteVolumeTriggerView: UIViewRepresentable {
    let connected: Bool
    let enabled: Bool
    let repIndex: () -> Int?
    let onTrigger: () -> Void

    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard connected, enabled else {
            context.coordinator.stopPolling()
            return
        }
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

        func startPolling() {
            guard timer == nil else { return }
            do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
            lastVolume = AVAudioSession.sharedInstance().outputVolume
            savedVolume = lastVolume
            timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                self?.checkVolume()
            }
            RunLoop.main.add(timer!, forMode: .common)
        }

        func stopPolling() {
            timer?.invalidate()
            timer = nil
        }

        private func checkVolume() {
            let current = AVAudioSession.sharedInstance().outputVolume
            if abs(current - lastVolume) > 0.01 {
                lastVolume = current
                onTrigger()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    MPVolumeView.setVolume(self?.savedVolume ?? 0.5)
                }
            }
        }
    }
}
