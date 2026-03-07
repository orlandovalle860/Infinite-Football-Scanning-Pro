//
//  TrainingCompleteFeedbackView.swift
//  FootballScanningAI
//
//  PBA V2 — Immediate session feedback after a block: correct decisions, first touch, speed vs last block, coach sentence.
//

import SwiftUI

/// Compares current block speed to the previous block. Used for "Decision Speed: Faster / Same / Slower".
func decisionSpeedComparisonLabel(current: SpeedBucket?, previous: SpeedBucket?) -> String {
    guard let c = current else { return "Same" }
    guard let p = previous else { return "Same" }
    let order: [SpeedBucket] = [.slow, .medium, .fast]
    guard let ci = order.firstIndex(of: c), let pi = order.firstIndex(of: p) else { return "Same" }
    if ci > pi { return "Faster" }
    if ci < pi { return "Slower" }
    return "Same"
}

struct TrainingCompleteFeedbackView: View {
    let activityName: String
    let correct: Int
    let total: Int
    /// e.g. "8/12" or "67%" or nil to show "—"
    let firstTouchAccuracy: String?
    /// "Faster" / "Same" / "Slower"
    let decisionSpeedLabel: String
    /// When set, show "Average decision time: X.XX seconds" under Decision Speed.
    let avgDecisionTimeSeconds: Double?
    let coachFeedback: String
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Training Complete")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(activityName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))

                VStack(alignment: .leading, spacing: 16) {
                    row("Correct Decisions", "\(correct) / \(total)")
                    row("First Touch Accuracy", firstTouchAccuracy ?? "—")
                    VStack(alignment: .leading, spacing: 4) {
                        row("Decision Speed", decisionSpeedLabel)
                        if let avg = avgDecisionTimeSeconds {
                            Text("Average decision time: \(String(format: "%.2f", avg)) seconds")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Coach Feedback")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.yellow)
                    Text(coachFeedback)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 24)

                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
        }
    }
}
