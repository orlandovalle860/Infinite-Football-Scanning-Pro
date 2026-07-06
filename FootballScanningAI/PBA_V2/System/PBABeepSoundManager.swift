//
//  PBABeepSoundManager.swift
//  FootballScanningAI
//
//  PBA training trigger beep: 4 variations (A/B/C/D), preloaded for low latency playback.
//  Selection persisted in AppStorage("selectedBeepSound"); preload on launch and when selection changes.
//

import Foundation
import AVFoundation

/// Beep variation IDs for A/B testing. Must match resource names: pba_beep_a.wav, etc.
enum PBABeepVariant: String, CaseIterable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    nonisolated var resourceName: String {
        "pba_beep_\(rawValue.lowercased())"
    }

    nonisolated var label: String {
        switch self {
        case .a: return "A Clear"
        case .b: return "B Punchy"
        case .c: return "C Warm"
        case .d: return "D Signature"
        }
    }
}

/// Manages PBA training beep: loads selected WAV, preloads for low latency, plays on demand.
/// All session + player work runs on a background serial queue (never blocks the main thread).
/// Methods are `nonisolated` so Swift 6 default `@MainActor` isolation does not marshal queue work back to main.
final class PBABeepSoundManager: @unchecked Sendable {
    nonisolated static let shared = PBABeepSoundManager()

    private let audioQueue = DispatchQueue(label: "com.pba.beep.audio", qos: .userInitiated)
    private nonisolated(unsafe) var player: AVAudioPlayer?
    private nonisolated(unsafe) var currentVariant: PBABeepVariant?
    private nonisolated(unsafe) var playbackCategoryConfigured = false
    private nonisolated(unsafe) var playbackSessionActive = false
    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?

    nonisolated private init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            self?.handleAudioSessionInterruption(notification)
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    /// AppStorage key for selected beep. Use with @AppStorage("selectedBeepSound").
    nonisolated static let selectedBeepStorageKey = "selectedBeepSound"

    /// New installs and invalid stored values: D (hybrid / signature in generated `pba_beep_d.wav`).
    nonisolated static let defaultSelectedBeepRawValue = PBABeepVariant.d.rawValue

    /// Preload the given variant so playback has minimal latency. Call on launch and when selection changes.
    nonisolated func preload(variant: PBABeepVariant) {
        audioQueue.async { [self] in
            guard currentVariant != variant || player == nil else { return }
            activatePlaybackSessionIfNeeded()
            guard let url = Bundle.main.url(forResource: variant.resourceName, withExtension: "wav") else {
                #if DEBUG
                print("[PBA-Debug] Beep preload missing file: \(variant.resourceName).wav")
                #endif
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = 0
                p.prepareToPlay()
                player = p
                currentVariant = variant
            } catch {
                #if DEBUG
                print("[PBA-Debug] Beep preload failed: \(variant.resourceName), error=\(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Preload using the current value from UserDefaults (selectedBeepSound). Call from app launch and when selector changes.
    nonisolated func preloadCurrent() {
        let raw = UserDefaults.standard.string(forKey: Self.selectedBeepStorageKey) ?? Self.defaultSelectedBeepRawValue
        let variant = PBABeepVariant(rawValue: raw) ?? .d
        preload(variant: variant)
    }

    /// Play the currently selected beep. No-op if sound is disabled or preload failed.
    nonisolated func play(soundEnabled: Bool = true) {
        guard soundEnabled else {
            #if DEBUG
            print("[PBA-Debug] Beep skipped: soundEnabled=false")
            #endif
            return
        }

        audioQueue.async { [self] in
            activatePlaybackSessionIfNeeded()
            playLoadedBeepOnAudioQueue()
        }
    }

    /// Non-blocking session warm-up (safe to call from SwiftUI / main thread).
    nonisolated func activateSessionIfNeeded() {
        audioQueue.async { [self] in
            activatePlaybackSessionIfNeeded()
        }
    }

    nonisolated private func handleAudioSessionInterruption(_ notification: Notification) {
        let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        audioQueue.async { [self] in
            guard let typeValue,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            switch type {
            case .began, .ended:
                playbackSessionActive = false
            @unknown default:
                playbackSessionActive = false
            }
        }
    }

    /// Configures and activates AVAudioSession on `audioQueue` only. iOS has no async setActive API (watchOS-only).
    nonisolated private func activatePlaybackSessionIfNeeded() {
        #if DEBUG
        assert(!Thread.isMainThread, "AVAudioSession must not be configured on the main thread")
        #endif

        let session = AVAudioSession.sharedInstance()
        do {
            if !playbackCategoryConfigured {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                playbackCategoryConfigured = true
            }
            guard !playbackSessionActive else { return }
            try session.setActive(true, options: [])
            playbackSessionActive = true
        } catch {
            playbackSessionActive = false
        }
    }

    nonisolated private func playLoadedBeepOnAudioQueue() {
        let raw = UserDefaults.standard.string(forKey: Self.selectedBeepStorageKey) ?? Self.defaultSelectedBeepRawValue
        let variant = PBABeepVariant(rawValue: raw) ?? .d

        if player == nil || currentVariant != variant {
            guard let loaded = loadPlayer(for: variant) else { return }
            player = loaded
            currentVariant = variant
        }

        guard let p = player else {
            #if DEBUG
            print("[PBA-Debug] Beep play failed: player=nil")
            #endif
            return
        }

        p.currentTime = 0
        if p.play() { return }

        #if DEBUG
        print("[PBA-Debug] Beep first play() returned false; reloading and retrying")
        #endif
        guard let reloaded = loadPlayer(for: variant) else { return }
        player = reloaded
        currentVariant = variant
        reloaded.currentTime = 0
        _ = reloaded.play()
    }

    nonisolated private func loadPlayer(for variant: PBABeepVariant) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: variant.resourceName, withExtension: "wav") else {
            #if DEBUG
            print("[PBA-Debug] Beep play failed: missing file \(variant.resourceName).wav")
            #endif
            return nil
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = 0
            p.prepareToPlay()
            return p
        } catch {
            #if DEBUG
            print("[PBA-Debug] Beep play load failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

// MARK: - PBA flow timing (beep vs PASS vs reveal — display sessions)

/// Training design: beep = perception cue; PASS = decision moment; reveal timestamp = UI live after preload.
enum PBAFlowDebugLog {
    static func beep(repId: Int, timestamp: Date = Date()) {
        #if DEBUG
        print("[PBAFlow-Debug] beep repId=\(repId) ts=\(timestamp.timeIntervalSince1970)")
        #endif
    }

    static func passReceived(repId: Int, timestamp: Date) {
        #if DEBUG
        print("[PBAFlow-Debug] PASS received repId=\(repId) ts=\(timestamp.timeIntervalSince1970)")
        #endif
    }

    static func reveal(repId: Int, timestamp: Date = Date()) {
        #if DEBUG
        print("[PBAFlow-Debug] reveal repId=\(repId) ts=\(timestamp.timeIntervalSince1970)")
        #endif
    }
}
