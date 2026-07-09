//
//  ActivityProgressView.swift
//  FootballScanningAI
//
//  Progress totals by activity (this week + all-time).
//

import SwiftUI

struct ActivityProgressView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ActivityProgressPanelView(showTitle: true)
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ActivityProgressPanelView: View {
    let showTitle: Bool
    var showsInsights: Bool = true
    @ObservedObject private var stats = ActivityStatsStore.shared

    private static let activityIds = [
        "two_minute_test",
        "one_touch_passing",
        "dribble_or_pass",
        "away_from_pressure"
    ]

    private var weeklyTotal: Int { stats.weeklyCounts.values.reduce(0, +) }
    private var allTimeTotal: Int { stats.totalCounts.values.reduce(0, +) }

    private var weeklyRows: [(id: String, name: String, count: Int)] {
        rows(from: stats.weeklyCounts)
    }

    private var allTimeRows: [(id: String, name: String, count: Int)] {
        rows(from: stats.totalCounts)
    }

    private var weeklyMaxCount: Int { max(weeklyRows.map(\.count).max() ?? 0, 1) }
    private var allTimeMaxCount: Int { max(allTimeRows.map(\.count).max() ?? 0, 1) }

    private var insightLines: [String] {
        guard let maxWeekly = weeklyRows.max(by: { $0.count < $1.count }),
              let minWeekly = weeklyRows.min(by: { $0.count < $1.count }),
              maxWeekly.count > 0 else {
            return ["Complete a session to start building your trend lines."]
        }
        let threshold = 10
        guard maxWeekly.count - minWeekly.count >= threshold else {
            return ["Your weekly training is balanced across activities."]
        }
        return [
            "You trained \(maxWeekly.name) most this week.",
            "You trained \(minWeekly.name) least this week."
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if showTitle {
                    header
                }
                sectionCard(
                    title: "THIS WEEK",
                    totalReps: weeklyTotal,
                    rows: weeklyRows,
                    maxCount: weeklyMaxCount
                )
                sectionCard(
                    title: "ALL TIME",
                    totalReps: allTimeTotal,
                    rows: allTimeRows,
                    maxCount: allTimeMaxCount
                )
                if showsInsights {
                    insightCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Training Totals")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Text("Activity Name • Reps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rows(from counts: [String: Int]) -> [(id: String, name: String, count: Int)] {
        Self.activityIds
            .map { id in
                (id: id, name: ActivityKind.fromSessionActivityId(id)?.displayName ?? id, count: counts[id, default: 0])
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
    }

    private func sectionCard(
        title: String,
        totalReps: Int,
        rows: [(id: String, name: String, count: Int)],
        maxCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeaderView(title: title, total: totalReps)

            VStack(spacing: 16) {
                ForEach(rows, id: \.id) { activity in
                    ActivityRowView(
                        title: activity.name,
                        value: activity.count,
                        maxValue: maxCount
                    )
                }
            }
        }
        .padding(18)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSIGHT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(insightLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
