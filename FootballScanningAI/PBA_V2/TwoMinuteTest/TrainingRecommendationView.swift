//
//  TrainingRecommendationView.swift
//  FootballScanningAI
//
//  PBA V2 — Actionable training plan after 2-Minute Test results.
//

import SwiftUI

// MARK: - Content model

struct TrainingRecommendationContent {
    /// Stable key for logging (not user-facing).
    let logKey: String
    let primaryTitle: String
    let primaryBody: String
    /// At most two activities (title + short description).
    let activities: [(title: String, detail: String)]
    let goalText: String
}

enum TrainingRecommendationModel {
    static func make(
        primaryProfileTitle: String,
        earlyCount: Int,
        idealCount: Int,
        lateCount: Int
    ) -> TrainingRecommendationContent {
        let ft = TwoMinuteBehaviorBadgeEvaluator.forwardThinkerTitle()
        let ot = TwoMinuteBehaviorBadgeEvaluator.onTimeTitle()
        let re = TwoMinuteBehaviorBadgeEvaluator.reactiveTitle()

        switch primaryProfileTitle {
        case ft:
            return TrainingRecommendationContent(
                logKey: "forwardThinker",
                primaryTitle: "Keep attacking your pocket moments early.",
                primaryBody: "Add pressure. Reduce time. Decide earlier under stress.",
                activities: [
                    (title: "2-Minute Test", detail: "Repeat and aim for earlier decisions."),
                    (title: "Playing Away From Pressure", detail: "Play away from pressure with a clear first action.")
                ],
                goalText: "Aim for 8 out of 10 early decisions."
            )
        case ot:
            return TrainingRecommendationContent(
                logKey: "onTime",
                primaryTitle: "Train deciding before the pocket closes.",
                primaryBody: "Know your next action before the ball reaches you.",
                activities: [
                    (title: "2-Minute Test", detail: "Repeat and aim for earlier decisions."),
                    (title: "Playing Away From Pressure", detail: "Play away from pressure with a clear first action.")
                ],
                goalText: "Aim for on-time to lead 6+ of 10 reps."
            )
        case re:
            return TrainingRecommendationContent(
                logKey: "reactive",
                primaryTitle: "Train winning your pocket moment earlier.",
                primaryBody: "See the picture before the ball arrives.",
                activities: [
                    (title: "Playing Away From Pressure", detail: "Play away from pressure with a clear first action."),
                    (title: "2-Minute Test", detail: "Repeat and aim for earlier decisions.")
                ],
                goalText: "Aim for under 5 late decisions in your next 10 reps."
            )
        default:
            return TrainingRecommendationContent(
                logKey: "mixedOrProfile",
                primaryTitle: "Train deciding before the pocket closes.",
                primaryBody: "Know your next action before the ball reaches you.",
                activities: [
                    (title: "2-Minute Test", detail: "Repeat and aim for earlier decisions."),
                    (title: "Playing Away From Pressure", detail: "Play away from pressure with a clear first action.")
                ],
                goalText: "Aim for 8 out of 10 early decisions."
            )
        }
    }
}

// MARK: - View

struct TrainingRecommendationView: View {
    let primaryProfileTitle: String
    let earlyCount: Int
    let idealCount: Int
    let lateCount: Int

    /// Dismisses this screen and opens Away From Pressure training (same behavior as results).
    var onStartTrainingAFP: () -> Void
    var onRunTestAgain: () -> Void

    private var content: TrainingRecommendationContent {
        TrainingRecommendationModel.make(
            primaryProfileTitle: primaryProfileTitle,
            earlyCount: earlyCount,
            idealCount: idealCount,
            lateCount: lateCount
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your Next Step")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(content.primaryTitle)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.95))
                    Text(content.primaryBody)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recommended Training")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.95))
                    ForEach(Array(content.activities.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.95))
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.95))
                    Text(content.goalText)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    Button {
                        onStartTrainingAFP()
                    } label: {
                        Text("Start Training")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)

                    Button {
                        onRunTestAgain()
                    } label: {
                        Text("Run Test Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let names = content.activities.map(\.title).joined(separator: ", ")
            print("[TrainingRecommendation-Debug] profile=\(primaryProfileTitle) recommendation=\(content.logKey) activities=[\(names)] earlyCount=\(earlyCount) idealCount=\(idealCount) lateCount=\(lateCount)")
        }
    }
}
