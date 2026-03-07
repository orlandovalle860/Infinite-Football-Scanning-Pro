//
//  SessionVolumeTriggerView.swift
//  FootballScanningAI
//
//  PBA V2 — Volume-button trigger for Wall/Solo mode on the display device.
//

import SwiftUI
import AVFoundation
import MediaPlayer

struct SessionVolumeTriggerView: UIViewRepresentable {
    let enabled: Bool
    let onTrigger: () -> Void

    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard enabled else {
            context.coordinator.stopPolling()
            return
        }
        context.coordinator.onTrigger = onTrigger
        context.coordinator.startPolling()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var timer: Timer?
        var lastVolume: Float = 0
        var savedVolume: Float = 0
        var onTrigger: (() -> Void) = {}
        /// Incremented on stop; delayed start checks this so we don't start after being disabled.
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
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                    self?.checkVolume()
                }
                RunLoop.main.add(self.timer!, forMode: .common)
            }
        }

        func stopPolling() {
            startGeneration += 1
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
