//
//  PostSessionFeedbackStore.swift
//  FootballScanningAI
//
//  Lightweight post-session stats from real tracked data only (reps, duration, streak).
//

import Foundation

struct PostSessionFeedbackContent: Equatable {
    let repCount: Int
    let isLongestSessionYet: Bool
    let isFirstSessionOfDay: Bool
    /// Shown only on the first session of a calendar day when streak >= 2.
    let streakDays: Int?
    /// Shown only on the first session of a calendar day.
    let showComeBackTomorrow: Bool
    /// Shown on additional same-day sessions instead of streak / come-back copy.
    let showExtraWorkToday: Bool
}

struct HomeTrainingMessage: Equatable {
    let primary: String
    let secondary: String?
}

enum PostSessionFeedbackStore {
    static let totalSessionsKey = "pba.postSession.totalSessions"
    static let totalRepsKey = "pba.postSession.totalReps"
    static let longestSessionDurationKey = "pba.postSession.longestSessionDurationSeconds"
    static let lastTrainingDayKey = "pba.postSession.lastTrainingDay"
    static let currentStreakDaysKey = "pba.postSession.currentStreakDays"

    static var totalSessions: Int {
        max(0, UserDefaults.standard.integer(forKey: totalSessionsKey))
    }

    static var totalReps: Int {
        max(0, UserDefaults.standard.integer(forKey: totalRepsKey))
    }

    static var longestSessionDurationSeconds: TimeInterval {
        max(0, UserDefaults.standard.double(forKey: longestSessionDurationKey))
    }

    static var currentStreakDays: Int {
        max(0, UserDefaults.standard.integer(forKey: currentStreakDaysKey))
    }

    static var lastTrainingDay: String? {
        UserDefaults.standard.string(forKey: lastTrainingDayKey)
    }

    static func hasTrainedToday(on date: Date = Date()) -> Bool {
        lastTrainingDay == calendarDayString(for: date)
    }

    static func isFirstSessionOfDay(on date: Date = Date()) -> Bool {
        lastTrainingDay != calendarDayString(for: date)
    }

    /// Contextual home copy above Start Session — no streak after user has trained today.
    static func homeTrainingMessage(on date: Date = Date()) -> HomeTrainingMessage? {
        guard totalSessions > 0, let lastDay = lastTrainingDay else { return nil }

        let today = calendarDayString(for: date)
        let yesterday = yesterdayString(before: date)

        if lastDay == today {
            return HomeTrainingMessage(primary: "You're back for more.", secondary: nil)
        }

        if lastDay == yesterday {
            let streakLine = currentStreakDays >= 2
                ? "🔥 \(currentStreakDays)-day streak — keep it going"
                : nil
            return HomeTrainingMessage(primary: "Back again today.", secondary: streakLine)
        }

        return HomeTrainingMessage(primary: "Ready to get back to it?", secondary: nil)
    }

    /// Records a completed session and returns copy for the post-session overlay.
    static func recordSession(
        repCount: Int,
        durationSeconds: TimeInterval,
        on date: Date = Date()
    ) -> PostSessionFeedbackContent {
        let reps = max(0, repCount)
        let duration = max(0, durationSeconds)
        let today = calendarDayString(for: date)

        let previousSessions = totalSessions
        let previousReps = totalReps
        let previousLongest = longestSessionDurationSeconds
        let previousLastDay = lastTrainingDay
        let previousStreak = currentStreakDays

        let isFirstSessionOfDay = previousLastDay != today

        let newSessions = previousSessions + 1
        let newReps = previousReps + reps
        let isLongestSession = duration > previousLongest

        var newStreak = previousStreak

        if isFirstSessionOfDay {
            if previousLastDay == yesterdayString(before: date) {
                newStreak = max(1, previousStreak) + 1
            } else {
                newStreak = 1
            }
        }

        UserDefaults.standard.set(newSessions, forKey: totalSessionsKey)
        UserDefaults.standard.set(newReps, forKey: totalRepsKey)
        if isLongestSession {
            UserDefaults.standard.set(duration, forKey: longestSessionDurationKey)
        }
        UserDefaults.standard.set(today, forKey: lastTrainingDayKey)
        UserDefaults.standard.set(newStreak, forKey: currentStreakDaysKey)

        let showLongestSession = isLongestSession && newSessions > 1
        let streakDays = isFirstSessionOfDay && newStreak >= 2 ? newStreak : nil

        return PostSessionFeedbackContent(
            repCount: reps,
            isLongestSessionYet: showLongestSession,
            isFirstSessionOfDay: isFirstSessionOfDay,
            streakDays: streakDays,
            showComeBackTomorrow: isFirstSessionOfDay,
            showExtraWorkToday: !isFirstSessionOfDay
        )
    }

    static func calendarDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func yesterdayString(before date: Date) -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        return calendarDayString(for: yesterday)
    }
}
