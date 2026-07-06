//
//  PlayerFirstRunGuidance.swift
//  FootballScanningAI
//
//  First-block-only player cues (reps 0–1) per activity; separate UserDefaults namespace from coach guidance.
//

import SwiftUI

enum PlayerFirstRunGuidanceStore {
    private static let keyPrefix = "playerFirstRunGuidanceCompleted."

    static func hasCompletedFirstRun(activityId: String) -> Bool {
        guard !activityId.isEmpty else { return true }
        return UserDefaults.standard.bool(forKey: keyPrefix + activityId)
    }

    static func markCompletedFirstRun(activityId: String) {
        guard !activityId.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: keyPrefix + activityId)
    }
}

enum PlayerFirstRunGuidanceCopy {
    static func message(for activity: ActivityKind, repIndexZeroBased: Int) -> String? {
        switch (activity, repIndexZeroBased) {
        case (.twoMinuteTest, 0): return "Match the ball with your first touch"
        case (.twoMinuteTest, 1): return "Decide before the pass arrives"
        case (.awayFromPressure, 0): return "Go the opposite direction of the signal"
        case (.awayFromPressure, 1): return "Decide before the pass arrives"
        case (.dribbleOrPass, 0): return "Avoid the red direction"
        case (.dribbleOrPass, 1): return "Choose a better direction early"
        case (.oneTouchPassing, 0): return "Avoid the red direction"
        case (.oneTouchPassing, 1): return "Play to the first green direction"
        default: return nil
        }
    }
}

enum PlayerFirstRunGuidanceToastAnimator {
    @MainActor
    static func cancel(
        token: Binding<UUID>,
        message: Binding<String?>,
        opacity: Binding<Double>
    ) {
        token.wrappedValue = UUID()
        opacity.wrappedValue = 0
        message.wrappedValue = nil
    }

    /// Quick fade in, ~1.4s read, fade out (~1.8s total) — centered player guidance only.
    @MainActor
    static func schedule(
        text: String,
        token: Binding<UUID>,
        message: Binding<String?>,
        opacity: Binding<Double>
    ) {
        token.wrappedValue = UUID()
        let scheduleToken = token.wrappedValue
        message.wrappedValue = text
        opacity.wrappedValue = 0
        Task { @MainActor in
            guard token.wrappedValue == scheduleToken else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                opacity.wrappedValue = 1
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard token.wrappedValue == scheduleToken else { return }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard token.wrappedValue == scheduleToken else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                opacity.wrappedValue = 0
            }
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard token.wrappedValue == scheduleToken else { return }
            message.wrappedValue = nil
        }
    }
}

struct PlayerFirstRunGuidanceToastOverlay: View {
    let message: String?
    let opacity: Double

    var body: some View {
        Group {
            if let message {
                Text(message)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                    .opacity(opacity)
            }
        }
    }
}
