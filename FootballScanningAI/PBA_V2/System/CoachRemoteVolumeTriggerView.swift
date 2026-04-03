//
//  CoachRemoteVolumeTriggerView.swift
//  FootballScanningAI
//
//  Shared volume-button → PASS detection for coach remotes. Uses outputVolume deltas;
//  near min/max there is no delta — UI should show CoachRemoteVolumeTriggerConfig.edgeWarningMessage.
//

import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

enum CoachRemoteVolumeTriggerConfig {
    /// Below this: "volume up" may not change level → no trigger.
    static let edgeLow: Float = 0.08
    /// Above this: "volume down" may not change level → no trigger.
    static let edgeHigh: Float = 0.92
    /// After a successful trigger, nudge level into this band so both buttons can move volume again.
    static let restoreLow: Float = 0.12
    static let restoreHigh: Float = 0.88

    static let edgeWarningMessage = "Set volume near the middle for both volume buttons to work."

    static func clampToRestorableBand(_ v: Float) -> Float {
        min(restoreHigh, max(restoreLow, v))
    }

    static func isNearVolumeEdge(_ v: Float) -> Bool {
        v < edgeLow || v > edgeHigh
    }
}

/// Invisible overlay; polls `outputVolume` on main. Reports edge band for UI messaging.
struct CoachRemoteVolumeTriggerView: UIViewRepresentable {
    let connected: Bool
    let enabled: Bool
    let repIndex: () -> Int?
    let onTrigger: () -> Void
    /// `true` when level is near min/max while polling — show guidance; `false` when safe or when inactive.
    let onVolumeEdgeWarningChange: ((Bool) -> Void)?

    init(
        connected: Bool,
        enabled: Bool,
        repIndex: @escaping () -> Int?,
        onTrigger: @escaping () -> Void,
        onVolumeEdgeWarningChange: ((Bool) -> Void)? = nil
    ) {
        self.connected = connected
        self.enabled = enabled
        self.repIndex = repIndex
        self.onTrigger = onTrigger
        self.onVolumeEdgeWarningChange = onVolumeEdgeWarningChange
    }

    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard connected, enabled else {
            context.coordinator.stopPolling()
            return
        }
        context.coordinator.onTrigger = onTrigger
        context.coordinator.repIndex = repIndex
        context.coordinator.onVolumeEdgeWarningChange = onVolumeEdgeWarningChange
        context.coordinator.startPolling()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var timer: Timer?
        var lastVolume: Float = 0
        var onTrigger: () -> Void = {}
        var repIndex: (() -> Int?) = { nil }
        var onVolumeEdgeWarningChange: ((Bool) -> Void)?
        var startGeneration: Int = 0
        private var lastEdgeWarning: Bool?

        func startPolling() {
            guard timer == nil else { return }
            do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
            lastVolume = AVAudioSession.sharedInstance().outputVolume
            startGeneration += 1
            let gen = startGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.timer == nil, self.startGeneration == gen else { return }
                self.lastVolume = AVAudioSession.sharedInstance().outputVolume
                self.publishEdgeIfNeeded(for: self.lastVolume)
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
            lastEdgeWarning = nil
            notifyVolumeEdgeWarning(false)
        }

        /// Defer to the next main run loop turn so we never mutate SwiftUI `@State` during `updateUIView` / layout.
        private func notifyVolumeEdgeWarning(_ edge: Bool) {
            guard let cb = onVolumeEdgeWarningChange else { return }
            DispatchQueue.main.async {
                cb(edge)
            }
        }

        private func publishEdgeIfNeeded(for v: Float) {
            let edge = CoachRemoteVolumeTriggerConfig.isNearVolumeEdge(v)
            if lastEdgeWarning != edge {
                lastEdgeWarning = edge
                notifyVolumeEdgeWarning(edge)
            }
        }

        private func checkVolume() {
            let current = AVAudioSession.sharedInstance().outputVolume
            publishEdgeIfNeeded(for: current)
            if abs(current - lastVolume) > 0.01 {
                lastVolume = current
                onTrigger()
                let clamped = CoachRemoteVolumeTriggerConfig.clampToRestorableBand(current)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    MPVolumeView.setVolume(clamped)
                    self?.lastVolume = clamped
                    self?.publishEdgeIfNeeded(for: clamped)
                }
            }
        }
    }
}
