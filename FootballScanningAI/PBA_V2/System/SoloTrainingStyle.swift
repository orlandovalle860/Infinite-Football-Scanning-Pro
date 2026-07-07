//
//  SoloTrainingStyle.swift
//  FootballScanningAI
//
//  Solo training pace: Quick (fast autoloop) vs Action (user-paced reps).
//

import Foundation

enum SoloTrainingStyle: String, CaseIterable, Identifiable {
    case quick = "quick"
    case action = "action"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Quick"
        case .action: return "Action"
        }
    }

    /// Quick auto-advances reps; Action waits for a screen tap between reps.
    var usesAutoloop: Bool {
        self == .quick
    }

    /// Delay after a rep reaches `waitingForNextRep` before the next scan begins (Quick only).
    var postRepAdvanceDelay: TimeInterval { 0.75 }

    static func loadLastSelected() -> SoloTrainingStyle {
        guard let raw = UserDefaults.standard.string(forKey: AppStorageKeys.lastTrainingStyle),
              let style = SoloTrainingStyle(rawValue: raw) else {
            return .quick
        }
        return style
    }

    static func saveLastSelected(_ style: SoloTrainingStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: AppStorageKeys.lastTrainingStyle)
    }
}
