//
//  TrainingCompleteFeedbackView.swift
//  FootballScanningAI
//
//  PBA V2 — Immediate session feedback after a block: correct decisions, first touch, speed vs last block, coach sentence.
//

import SwiftUI

/// Ordinal for percentile display: 1st, 2nd, 3rd, 4th, 21st, 22nd, etc.
func ordinalPercentile(_ n: Int) -> String {
    let s = "\(n)"
    let lastTwo = (n % 100)
    if (11...13).contains(lastTwo) { return s + "th" }
    switch n % 10 {
    case 1: return s + "st"
    case 2: return s + "nd"
    case 3: return s + "rd"
    default: return s + "th"
    }
}

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
    /// When set, show "Decision Speed Score: XX" (0–100, combines correctness and reaction speed).
    let decisionSpeedScore: Int?
    /// When set, show "XXth percentile" and "Faster decision-making than XX% of players."
    let decisionSpeedPercentile: Int?
    /// Previous session metrics for comparison (nil = no previous session).
    let previousDecisionSpeedScore: Int?
    let previousAvgReactionTimeSeconds: Double?
    let previousCorrect: Int?
    let previousTotal: Int?
    /// Best Decision Speed Score for this player and activity (from sessions). Shown as "Personal Best: XX".
    let personalBest: Int?
    /// True when this session's score is a new personal best.
    let isNewPersonalBest: Bool
    let coachFeedback: String
    let onContinue: () -> Void

    init(
        activityName: String,
        correct: Int,
        total: Int,
        firstTouchAccuracy: String?,
        decisionSpeedLabel: String,
        avgDecisionTimeSeconds: Double?,
        decisionSpeedScore: Int? = nil,
        decisionSpeedPercentile: Int? = nil,
        previousDecisionSpeedScore: Int? = nil,
        previousAvgReactionTimeSeconds: Double? = nil,
        previousCorrect: Int? = nil,
        previousTotal: Int? = nil,
        personalBest: Int? = nil,
        isNewPersonalBest: Bool = false,
        coachFeedback: String,
        onContinue: @escaping () -> Void
    ) {
        self.activityName = activityName
        self.correct = correct
        self.total = total
        self.firstTouchAccuracy = firstTouchAccuracy
        self.decisionSpeedLabel = decisionSpeedLabel
        self.avgDecisionTimeSeconds = avgDecisionTimeSeconds
        self.decisionSpeedScore = decisionSpeedScore
        self.decisionSpeedPercentile = decisionSpeedPercentile
        self.previousDecisionSpeedScore = previousDecisionSpeedScore
        self.previousAvgReactionTimeSeconds = previousAvgReactionTimeSeconds
        self.previousCorrect = previousCorrect
        self.previousTotal = previousTotal
        self.personalBest = personalBest
        self.isNewPersonalBest = isNewPersonalBest
        self.coachFeedback = coachFeedback
        self.onContinue = onContinue
    }

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
                    if let score = decisionSpeedScore {
                        VStack(alignment: .leading, spacing: 4) {
                            row("Decision Speed Score", "\(score)")
                            if isNewPersonalBest {
                                Text("New Personal Best 🎉")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.yellow)
                            }
                            if let best = personalBest {
                                row("Personal Best", "\(best)")
                            }
                            if let pct = decisionSpeedPercentile {
                                Text(ordinalPercentile(pct) + " percentile")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Text("Faster decision-making than \(pct)% of players.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            sessionComparisonLine(scoreChange: previousDecisionSpeedScore.map { score - $0 })
                        }
                    }
                    if let avg = avgDecisionTimeSeconds {
                        VStack(alignment: .leading, spacing: 2) {
                            row("Average Reaction Time", String(format: "%.2f s", avg))
                            if let prev = previousAvgReactionTimeSeconds {
                                reactionTimeComparisonLine(previousSeconds: prev, currentSeconds: avg)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        row("Correct Decisions", "\(correct) / \(total)")
                        if let prevCorrect = previousCorrect {
                            accuracyComparisonLine(correctChange: correct - prevCorrect)
                        }
                    }
                    row("First Touch Accuracy", firstTouchAccuracy ?? "—")
                    VStack(alignment: .leading, spacing: 4) {
                        row("Decision Speed", decisionSpeedLabel)
                        if let avg = avgDecisionTimeSeconds, let band = DecisionSpeedBand.band(forSeconds: avg) {
                            Text(band.label)
                                .font(.caption.weight(.medium))
                                .foregroundColor(band.color)
                            Text(band.explanation)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
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

    @ViewBuilder
    private func sessionComparisonLine(scoreChange: Int?) -> some View {
        if let delta = scoreChange {
            Text(delta == 0 ? "Same as last session" : (delta > 0 ? "+\(delta)" : "\(delta)") + " from last session")
                .font(.caption)
                .foregroundColor(delta >= 0 ? .green : .white.opacity(0.85))
        }
    }

    @ViewBuilder
    private func reactionTimeComparisonLine(previousSeconds: Double, currentSeconds: Double) -> some View {
        let diff = previousSeconds - currentSeconds
        if diff > 0 {
            Text("↓ \(String(format: "%.2f", diff)) s faster")
                .font(.caption)
                .foregroundColor(.green)
        } else if diff < 0 {
            Text("↑ \(String(format: "%.2f", -diff)) s slower")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
        } else {
            Text("Same as last session")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    @ViewBuilder
    private func accuracyComparisonLine(correctChange: Int) -> some View {
        if correctChange == 0 {
            Text("Same as last session")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        } else if correctChange > 0 {
            Text("+\(correctChange) correct decision\(correctChange == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.green)
        } else {
            Text("\(correctChange) correct decision\(correctChange == -1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
        }
    }
}
