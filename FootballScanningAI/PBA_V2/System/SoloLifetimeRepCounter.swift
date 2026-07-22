//
//  SoloLifetimeRepCounter.swift
//  FootballScanningAI
//
//  Cumulative solo rep totals per activity — no per-session progress pressure.
//

import SwiftUI

enum SoloLifetimeRepCounter {
    private static func storageKey(for activity: ActivityKind) -> String {
        "pba.soloLifetimeReps.\(activity.rawValue)"
    }

    static func totalReps(for activity: ActivityKind) -> Int {
        max(0, UserDefaults.standard.integer(forKey: storageKey(for: activity)))
    }

    @discardableResult
    static func recordRep(for activity: ActivityKind) -> Int {
        let key = storageKey(for: activity)
        let next = totalReps(for: activity) + 1
        UserDefaults.standard.set(next, forKey: key)
        return next
    }

    /// Clears lifetime solo corner-badge totals (account delete / sign-out).
    static func clearAllForSignOut() {
        let defaults = UserDefaults.standard
        let prefix = "pba.soloLifetimeReps."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    static func formattedTotal(_ count: Int) -> String {
        count == 1 ? "1 rep" : "\(count) reps"
    }
}

/// Subtle lifetime rep total for solo display sessions (top-trailing corner).
struct SoloLifetimeRepCornerBadge: View {
    let repCount: Int

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(SoloLifetimeRepCounter.formattedTotal(repCount))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.32))
                    .padding(.trailing, 16)
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityLabel("\(repCount) lifetime reps")
    }
}
