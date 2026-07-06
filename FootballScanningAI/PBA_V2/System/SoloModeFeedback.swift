//
//  SoloModeFeedback.swift
//  FootballScanningAI
//
//  Pattern-based solo summary copy (tempo bucket → feedback tone). No numbers shown.
//

import Foundation

/// Coarse pass-speed bucket for solo copy (not a measured quantity in the UI).
enum SoloTempo: Equatable {
    case slow
    case game
    case fast
}

extension SoloTempo {
    /// Maps session ``PassTempo`` to a simple solo bucket (slow / game / fast).
    init(passTempo: PassTempo) {
        switch passTempo {
        case .controlled: self = .slow
        case .gameSpeed: self = .game
        case .elite: self = .fast
        }
    }
}

enum SoloFeedbackType: Equatable {
    case early
    case neutral
    case late
}

func resolveSoloFeedbackType(tempo: SoloTempo) -> SoloFeedbackType {
    switch tempo {
    case .slow:
        return .early
    case .game:
        return .neutral
    case .fast:
        return .late
    }
}

struct SoloFeedback: Equatable {
    let focusOptions: [String]
    let nextOptions: [String]
}

/// Remembers the last focus/next line shown so the next summary can avoid the same phrase consecutively.
/// Persists across new ``SoloSessionSummaryView`` instances (e.g. Run It Back), unlike view-only `@State`.
enum SoloFeedbackLastPhraseMemory {
    static var lastFocus: String?
    static var lastNext: String?
}

/// Picks a random line, avoiding `last` when other options exist.
func pickNonRepeating(from options: [String], last: String?) -> String {
    let filtered = options.filter { $0 != last }
    return (filtered.isEmpty ? options : filtered).randomElement() ?? ""
}

func soloFeedback(for type: SoloFeedbackType) -> SoloFeedback {
    switch type {
    case .early:
        return SoloFeedback(
            focusOptions: [
                "Keep the rhythm",
                "Stay ahead of it",
                "Control the tempo"
            ],
            nextOptions: [
                "Play forward when it's on",
                "Attack the next space",
                "Look forward first"
            ]
        )
    case .neutral:
        return SoloFeedback(
            focusOptions: [
                "Decide before it arrives",
                "See it early",
                "Picture it sooner"
            ],
            nextOptions: [
                "Scan early, not on the touch",
                "Check before the pass",
                "Find the picture sooner"
            ]
        )
    case .late:
        return SoloFeedback(
            focusOptions: [
                "React on the pass",
                "Move sooner",
                "Don't wait on it"
            ],
            nextOptions: [
                "Trust the first touch",
                "Commit to the first action",
                "Play it without hesitation"
            ]
        )
    }
}
