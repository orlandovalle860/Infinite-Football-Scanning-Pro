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

    /// Preload the given variant so playback has minimal latency. Call on launch and when selection changes.
    func preload(variant: PBABeepVariant) {
        guard currentVariant != variant else { return }
        player = nil
        currentVariant = variant
        guard let url = Bundle.main.url(forResource: variant.resourceName, withExtension: "wav") else {
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.numberOfLoops = 0
            player = p
        } catch {}
    }

    /// Preload using the current value from UserDefaults (selectedBeepSound). Call from app launch and when selector changes.
    func preloadCurrent() {
        let raw = UserDefaults.standard.string(forKey: Self.selectedBeepStorageKey) ?? "A"
        let variant = PBABeepVariant(rawValue: raw) ?? .a
        preload(variant: variant)
    }

    /// Play the currently selected beep. No-op if sound is disabled or preload failed. Activates session if needed; call from main.
    func play(soundEnabled: Bool = true) {
        guard soundEnabled else { return }
        preloadCurrent()
        guard let p = player else { return }
        p.currentTime = 0
        p.play()
    }

    /// Activate audio session for playback. Call once before first play (e.g. from display views that already do this).
    func activateSessionIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }
}
