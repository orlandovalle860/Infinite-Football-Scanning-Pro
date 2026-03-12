//
//  CurriculumCard.swift
//  FootballScanningAI
//
//  Reusable "Today's Training Path" card for the Home screen. Shows curriculum progress and Start Training or prompts for 2-Minute Test.
//

import SwiftUI

/// Total blocks in the Decision Making Curriculum (e.g. 8 per activity × 3 activities).
let curriculumTotalBlocks = 24

/// Card showing Today's Training Path: progress (Block X of Y), recommended drill, and Start Training or "Take 2-Minute Test" when path is locked.
struct CurriculumCard: View {
    let currentBlock: Int
    let totalBlocks: Int
    let recommendedActivity: ActivityKind?
    let hasCompletedInitialTest: Bool
    let onStartTraining: () -> Void
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
                        Text(activityTitle(for: activity))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                }

                Button(action: onStartTraining) {
                    Text("Start Training")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                Text("Take the 2-Minute Test to unlock your training path.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onStartTwoMinuteTest) {
                    Text("Start 2-Minute Test")
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

    private func activityTitle(for activity: ActivityKind) -> String {
        switch activity {
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        case .twoMinuteTest: return "2-Minute Test"
        }
    }
}
