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
        task: inout Task<Void, Never>?,
        message: Binding<String?>,
        opacity: Binding<Double>
    ) {
        task?.cancel()
        task = nil
        opacity.wrappedValue = 0
        message.wrappedValue = nil
    }

    /// ~0.2s fade in, ~1.6s readable, ~0.2s fade out (non-blocking).
    @MainActor
    static func schedule(
        text: String,
        task: inout Task<Void, Never>?,
        message: Binding<String?>,
        opacity: Binding<Double>
    ) {
        task?.cancel()
        message.wrappedValue = text
        opacity.wrappedValue = 0
        task = Task { @MainActor in
            withAnimation(.easeIn(duration: 0.2)) {
                opacity.wrappedValue = 1
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                opacity.wrappedValue = 0
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
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
                VStack {
                    Spacer()
                    Text(message)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        )
                        .cornerRadius(14)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
                .allowsHitTesting(false)
                .opacity(opacity)
            }
        }
    }
}
