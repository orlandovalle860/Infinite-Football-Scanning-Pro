//
//  SoloStimulusPicker.swift
//  FootballScanningAI
//
//  Solo-only: per-rep stimulus selection with consecutive-repeat guard.
//

import Foundation

/// Tracks the last chosen stimulus and limits consecutive identical picks (max 2).
struct SoloStimulusAntiRepeatPicker<Key: Hashable> {
    private var lastKey: Key?
    private var repeatCount = 0
    private let maxConsecutiveRepeats = 2

    mutating func reset() {
        lastKey = nil
        repeatCount = 0
    }

    /// Picks from `candidates`, avoiding more than `maxConsecutiveRepeats` identical keys in a row.
    mutating func pick<C: Collection>(from candidates: C, key: (C.Element) -> Key) -> C.Element? where C: RandomAccessCollection {
        guard !candidates.isEmpty else { return nil }
        let pool = Array(candidates)
        var chosen = pool.randomElement()!
        var chosenKey = key(chosen)

        if let lastKey, chosenKey == lastKey {
            repeatCount += 1
        } else {
            repeatCount = 1
        }

        if repeatCount > maxConsecutiveRepeats {
            let alternatives = pool.filter { key($0) != lastKey }
            if let alt = alternatives.randomElement() {
                chosen = alt
                chosenKey = key(chosen)
                repeatCount = 1
            }
        }

        lastKey = chosenKey
        return chosen
    }
}

enum SoloStimulusDebugLog {
    static func log(repNumber: Int, stimulus: String) {
        #if DEBUG
        print("[SoloStimulus] Rep \(repNumber): Stimulus = \(stimulus)")
        #endif
    }
}
