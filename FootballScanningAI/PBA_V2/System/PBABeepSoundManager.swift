//
//  PBABeepSoundManager.swift
//  FootballScanningAI
//
//  PBA training trigger beep: 4 variations (A/B/C/D), preloaded for low-latency playback.
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

    var resourceName: String {
        "pba_beep_\(rawValue.lowercased())"
    }

    var label: String {
        switch self {
        case .a: return "A Clear"
        case .b: return "B Punchy"
        case .c: return "C Warm"
        case .d: return "D Signature"
        }
    }
}

/// Manages PBA training beep: loads selected WAV, preloads for low latency, plays on demand.
final class PBABeepSoundManager {
    static let shared = PBABeepSoundManager()

    private var player: AVAudioPlayer?
    private var currentVariant: PBABeepVariant?

    private init() {}

    /// AppStorage key for selected beep. Use with @AppStorage("selectedBeepSound").
    static let selectedBeepStorageKey = "selectedBeepSound"

    /// New installs and invalid stored values: D (hybrid / signature in generated `pba_beep_d.wav`).
    static let defaultSelectedBeepRawValue = PBABeepVariant.d.rawValue

    /// Preload the given variant so playback has minimal latency. Call on launch and when selection changes.
    func preload(variant: PBABeepVariant) {
        guard currentVariant != variant else { return }
        player = nil
        currentVariant = variant
        guard let url = Bundle.main.url(forResource: variant.resourceName, withExtension: "wav") else {
            #if DEBUG
            print("[PBA-Debug] Beep preload missing file: \(variant.resourceName).wav")
            #endif
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.numberOfLoops = 0
            player = p
        } catch {
            #if DEBUG
            print("[PBA-Debug] Beep preload failed: \(variant.resourceName), error=\(error.localizedDescription)")
            #endif
        }
    }

    /// Preload using the current value from UserDefaults (selectedBeepSound). Call from app launch and when selector changes.
    func preloadCurrent() {
        let raw = UserDefaults.standard.string(forKey: Self.selectedBeepStorageKey) ?? Self.defaultSelectedBeepRawValue
        let variant = PBABeepVariant(rawValue: raw) ?? .d
        preload(variant: variant)
    }

    /// Play the currently selected beep. No-op if sound is disabled or preload failed. Activates session if needed; call from main.
    func play(soundEnabled: Bool = true) {
        guard soundEnabled else {
            #if DEBUG
            print("[PBA-Debug] Beep skipped: soundEnabled=false")
            #endif
            return
        }

        activateSessionIfNeeded()
        preloadCurrent()
        guard let p = player else {
            #if DEBUG
            print("[PBA-Debug] Beep play failed: player=nil")
            #endif
            return
        }
        p.currentTime = 0
        let played = p.play()

        // Rarely AVAudioPlayer can fail to start after route/interruption changes.
        // Reload the selected asset and retry once.
        if !played {
            #if DEBUG
            print("[PBA-Debug] Beep first play() returned false; reloading and retrying")
            #endif
            let raw = UserDefaults.standard.string(forKey: Self.selectedBeepStorageKey) ?? Self.defaultSelectedBeepRawValue
            let variant = PBABeepVariant(rawValue: raw) ?? .d
            currentVariant = nil
            preload(variant: variant)
            player?.currentTime = 0
            _ = player?.play()
        }
    }

    /// Activate audio session for playback. Call once before first play (e.g. from display views that already do this).
    func activateSessionIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }
}
