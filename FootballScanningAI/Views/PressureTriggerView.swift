//
//  PressureTriggerView.swift
//  FootballScanningAI
//
//  Use on iPhone: connect to iPad running Pressure Response (e.g. Playing Away from Pressure). Trigger via tap or volume button.
//

import AVFoundation
import MediaPlayer
import SwiftUI

struct PressureTriggerView: View {
    @EnvironmentObject var multipeerManager: MultipeerManager
    @Environment(\.dismiss) private var dismiss
    @State private var volumeButtonTriggerEnabled = true

    var body: some View {
        VStack(spacing: 24) {
            Text("Training Trigger")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Connect this iPhone to the iPad running an activity (e.g. Playing Away from Pressure), then tap to trigger (e.g. when you check to the passer, or when the pass is made).")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. On iPad: Start Training → choose activity (e.g. Playing Away from Pressure) → Start.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                Text("2. Keep iPhone and iPad nearby. Same Wi‑Fi is not required; they can connect over peer-to-peer. Allow Local Network if prompted.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                Text("3. Then tap Connect to iPad below.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal)

            if let error = multipeerManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
            }

            if multipeerManager.connectedPeerName != nil {
                Text("Connected to \(multipeerManager.connectedPeerName!)")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                Text("Not connected")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            if !multipeerManager.isBrowsing {
                Button("Connect to iPad") {
                    multipeerManager.lastError = nil
                    multipeerManager.startBrowsing()
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .padding(.horizontal, 40)
            } else if multipeerManager.connectedPeerName == nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                Text("Searching for iPad…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Button("Cancel") {
                    multipeerManager.stopBrowsing()
                }
                .foregroundColor(.white.opacity(0.9))
            }

            if multipeerManager.connectedPeerName != nil {
                Text("Tap below or press a volume button to trigger")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Button(action: {
                    multipeerManager.lastError = nil
                    multipeerManager.sendTrigger()
                }) {
                    Text("Pass Made")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color.green)
                        .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 8)

                Button(action: {
                    multipeerManager.lastError = nil
                }) {
                    Text("Clear error")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .overlay(VolumeButtonTriggerView(
            connected: multipeerManager.connectedPeerName != nil,
            volumeTriggerEnabled: volumeButtonTriggerEnabled,
            onTrigger: {
                multipeerManager.lastError = nil
                multipeerManager.sendTrigger()
            }
        ).allowsHitTesting(false).frame(width: 1, height: 1))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    multipeerManager.stopBrowsing()
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .onDisappear {
            multipeerManager.stopBrowsing()
        }
    }
}

// MARK: - Volume button trigger (invisible; observes volume and fires trigger, then restores level)
private struct VolumeButtonTriggerView: UIViewRepresentable {
    let connected: Bool
    let volumeTriggerEnabled: Bool
    let onTrigger: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard connected, volumeTriggerEnabled else {
            context.coordinator.stopPolling()
            return
        }
        context.coordinator.onTrigger = onTrigger
        context.coordinator.startPolling()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var timer: Timer?
        var lastVolume: Float = 0
        var savedVolume: Float = 0
        var onTrigger: (() -> Void) = {}

        func startPolling() {
            guard timer == nil else { return }
            let session = AVAudioSession.sharedInstance()
            do { try session.setActive(true) } catch {}
            lastVolume = session.outputVolume
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
                    self?.restoreVolume()
                }
            }
        }

        private func restoreVolume() {
            MPVolumeView.setVolume(savedVolume)
        }
    }
}

extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView(frame: .zero)
        guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            slider.value = volume
        }
    }
}
