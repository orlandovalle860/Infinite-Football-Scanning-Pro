//
//  TimedSessionSummaryView.swift
//  FootballScanningAI
//
//  Modal post-session summary for timed solo/partner sessions — reps, time, and next-step actions.
//

import SwiftUI

struct TimedSessionSummaryView: View {
    let totalRepCount: Int
    let durationText: String
    let completionType: SessionCompletionType
    let isFreeMode: Bool
    let mode: TrainingMode
    let activityRepCounts: [String: Int]
    let onTrainAgain: () -> Void
    let onDone: () -> Void

    private var summaryTitle: String {
        if isFreeMode { return "Session Complete" }
        return completionType == .completed ? "Session Complete" : "Session Ended Early"
    }

    private var activityCounts: [ActivityKind: Int] {
        ActivityKind.timedSessionActivityCounts(from: activityRepCounts)
    }

    private var sortedActivityRows: [(ActivityKind, Int)] {
        SessionSummaryExperienceCopy.sortedActivities(activityCounts)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                VisionPlayBrandingView(style: .prominentDark)
                    .padding(.bottom, 20)

                sessionMetaHeader
                    .padding(.bottom, 20)

                if !sortedActivityRows.isEmpty {
                    sessionExperienceCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    Spacer(minLength: 0)
                }

                summaryActions
                    .padding(.top, 20)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private var sessionMetaHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryTitle.uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            Text("\(durationText) • \(totalRepCount) reps")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(.secondary.opacity(0.9))
            Text(mode == .partner ? "Partner Session" : "Solo Session")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionExperienceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(SessionSummaryExperienceCopy.headline(
                totalReps: totalRepCount,
                activityCount: activityCounts.count
            ))
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)

            Text(SessionSummaryExperienceCopy.insight(activityCounts: activityCounts))
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 16) {
                ForEach(sortedActivityRows, id: \.0) { activity, reps in
                    activityRepBarRow(activity: activity, reps: reps)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func activityRepBarRow(activity: ActivityKind, reps: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(activity.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Text("\(reps)")
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.gray)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))

                    Capsule()
                        .fill(Color.yellow.opacity(0.85))
                        .frame(
                            width: geo.size.width * CGFloat(reps) / CGFloat(max(totalRepCount, 1))
                        )
                }
            }
            .frame(height: 6)
        }
    }

    private var summaryActions: some View {
        VStack(spacing: 12) {
            Button("Train Again", action: onTrainAgain)
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundColor(.black)

            Button("Done", action: onDone)
                .foregroundColor(.gray)

            if !activityCounts.isEmpty {
                Text(SessionSummaryExperienceCopy.nextFocusSuggestion(activityCounts: activityCounts))
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
