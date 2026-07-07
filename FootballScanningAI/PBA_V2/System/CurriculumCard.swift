//
//  CurriculumCard.swift
//  FootballScanningAI
//
//  Reusable "Today's Training Path" card for the Home screen. Shows curriculum progress and View Path (secondary) or "Start 2-Minute Test" when path is locked.
//

import SwiftUI

/// Total blocks in the Decision Making Curriculum (e.g. 8 per activity × 3 activities).
let curriculumTotalBlocks = 24

/// Card showing Today's Training Path: progress (Block X of Y), recommended drill, and "View Path" (navigate to curriculum) or "Take 2-Minute Test" when path is locked.
struct CurriculumCard: View {
    let currentBlock: Int
    let totalBlocks: Int
    let recommendedActivity: ActivityKind?
    let hasCompletedInitialTest: Bool
    /// Navigate to Perception Training Path / curriculum screen (secondary action).
    let onViewPath: () -> Void
    let onStartTwoMinuteTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Training Path")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                Text("Decision Making Curriculum")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
            }

            if hasCompletedInitialTest {
                Text("Block \(currentBlock) of \(totalBlocks)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))

                if let activity = recommendedActivity {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended Drill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text(activity.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                }

                Button(action: onViewPath) {
                    Text("View Path")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.yellow, lineWidth: 1.5)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                Text("Train \(ActivityKind.twoMinuteTest.displayName) to unlock your training path.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onStartTwoMinuteTest) {
                    Text("Start \(ActivityKind.twoMinuteTest.displayName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
