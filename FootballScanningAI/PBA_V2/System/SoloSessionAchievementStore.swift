//
//  SoloSessionAchievementStore.swift
//  FootballScanningAI
//
//  Solo session completion highlights: daily streak and personal bests (UserDefaults).
//

import Foundation

enum SoloSessionCompletionHighlight: Equatable {
    case newBestReps
    case longestSession
    case dailyStreak(days: Int)

    var displayText: String {
        switch self {
        case .newBestReps:
            return "🏆 New best"
        case .longestSession:
            return "⏱ Longest session"
        case .dailyStreak(let days):
            return "🔥 \(days) day streak"
        }
    }
}

enum SoloSessionAchievementStore {
    private static let bestRepsKey = "pba.soloSession.bestReps"
    private static let bestDurationKey = "pba.soloSession.bestDurationSeconds"
    private static let streakCountKey = "pba.soloSession.dailyStreakCount"
    private static let lastSessionDayKey = "pba.soloSession.lastSessionDay"

    /// Records session completion and returns at most one highlight (priority: reps → time → streak).
    static func recordCompletion(elapsedSeconds: TimeInterval, repCount: Int) -> SoloSessionCompletionHighlight? {
        let previousBestReps = UserDefaults.standard.integer(forKey: bestRepsKey)
        let previousBestDuration = UserDefaults.standard.double(forKey: bestDurationKey)
        let previousStreak = UserDefaults.standard.integer(forKey: streakCountKey)

        let newBestReps = repCount > previousBestReps
        let newLongestSession = elapsedSeconds > previousBestDuration

        let streakUpdate = updateDailyStreak()
        let streakIncreased = streakUpdate.newCount > previousStreak

        if repCount > previousBestReps {
            UserDefaults.standard.set(repCount, forKey: bestRepsKey)
        }
        if elapsedSeconds > previousBestDuration {
            UserDefaults.standard.set(elapsedSeconds, forKey: bestDurationKey)
        }

        if newBestReps { return .newBestReps }
        if newLongestSession { return .longestSession }
        if streakIncreased { return .dailyStreak(days: streakUpdate.newCount) }
        return nil
    }

    private static func updateDailyStreak() -> (newCount: Int, sameDay: Bool) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let previousStreak = max(0, UserDefaults.standard.integer(forKey: streakCountKey))

        let lastDayInterval = UserDefaults.standard.double(forKey: lastSessionDayKey)
        if lastDayInterval > 0 {
            let lastDay = calendar.startOfDay(for: Date(timeIntervalSince1970: lastDayInterval))
            if lastDay == today {
                return (previousStreak, true)
            }
        }

        let newStreak: Int
        if lastDayInterval > 0 {
            let lastDay = calendar.startOfDay(for: Date(timeIntervalSince1970: lastDayInterval))
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               lastDay == yesterday {
                newStreak = previousStreak + 1
            } else {
                newStreak = 1
            }
        } else {
            newStreak = 1
        }

        UserDefaults.standard.set(today.timeIntervalSince1970, forKey: lastSessionDayKey)
        UserDefaults.standard.set(newStreak, forKey: streakCountKey)
        return (newStreak, false)
    }
}
