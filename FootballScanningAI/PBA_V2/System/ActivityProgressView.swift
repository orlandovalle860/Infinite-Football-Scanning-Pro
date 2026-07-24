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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                trainingTotalsBlock
                aboutFooter
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }

    /// Title + week/all-time sections as one block so a summary can sit above without reflowing the page.
    private var trainingTotalsBlock: some View {
        VStack(alignment: .leading, spacing: 28) {
            if showTitle {
                Text("Training Totals")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
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

    private var aboutFooter: some View {
        Text("VisionPlay")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}
