//
//  ActivityStatsStore.swift
//  FootballScanningAI
//
//  Cumulative per-activity rep totals for progress surfaces.
//

import Foundation
import Combine

@MainActor
final class ActivityStatsStore: ObservableObject {
    static let shared = ActivityStatsStore()

    @Published private(set) var totalCounts: [String: Int] = [:]
    @Published private(set) var weeklyCounts: [String: Int] = [:]
    @Published private(set) var sessionsToday: Int = 0

    private let totalCountsKey = "activity_stats_total_counts_v1"
    private let weeklyCountsKey = "activity_stats_weekly_counts_v1"
    private let weeklyAnchorKey = "activity_stats_weekly_anchor_v1"
    private let sessionsTodayKey = "activity_stats_sessions_today_v1"
    private let sessionsTodayAnchorKey = "activity_stats_sessions_today_anchor_v1"
    private let defaults: UserDefaults
    private let calendar: Calendar

    private init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.calendar = calendar
        load()
    }

    func ingestSessionCounts(_ counts: [String: Int]) {
        rollDayIfNeeded()
        rollWeekIfNeeded()
        sessionsToday += 1
        for (activityId, count) in counts where count > 0 {
            totalCounts[activityId, default: 0] += count
            weeklyCounts[activityId, default: 0] += count
        }
        persist()
    }

    private func load() {
        totalCounts = defaults.dictionary(forKey: totalCountsKey) as? [String: Int] ?? [:]
        weeklyCounts = defaults.dictionary(forKey: weeklyCountsKey) as? [String: Int] ?? [:]
        sessionsToday = defaults.integer(forKey: sessionsTodayKey)
        rollDayIfNeeded()
        rollWeekIfNeeded()
    }

    private func persist() {
        defaults.set(totalCounts, forKey: totalCountsKey)
        defaults.set(weeklyCounts, forKey: weeklyCountsKey)
        defaults.set(sessionsToday, forKey: sessionsTodayKey)
    }

    private func rollWeekIfNeeded(now: Date = Date()) {
        if let anchor = defaults.object(forKey: weeklyAnchorKey) as? Date,
           calendar.isDate(anchor, equalTo: now, toGranularity: .weekOfYear) {
            return
        }
        weeklyCounts = [:]
        defaults.set(now, forKey: weeklyAnchorKey)
        defaults.set(weeklyCounts, forKey: weeklyCountsKey)
    }

    private func rollDayIfNeeded(now: Date = Date()) {
        if let anchor = defaults.object(forKey: sessionsTodayAnchorKey) as? Date,
           calendar.isDate(anchor, inSameDayAs: now) {
            return
        }
        sessionsToday = 0
        defaults.set(now, forKey: sessionsTodayAnchorKey)
        defaults.set(sessionsToday, forKey: sessionsTodayKey)
    }
}
