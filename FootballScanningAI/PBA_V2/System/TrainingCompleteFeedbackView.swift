//
//  TrainingCompleteFeedbackView.swift
//  FootballScanningAI
//
//  PBA V2 — Immediate session feedback after a block: correct decisions, optional decision–action stats, speed vs last block, coach sentence.
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
    /// Used for soccer context + next-step routing in the narrative layer.
    let activityKind: ActivityKind
    let correct: Int
    let total: Int
    /// DOP: optional "X/12" decision–action alignment when coach logged early direction; nil hides the row.
    let firstTouchAccuracy: String?
    /// "Faster" / "Same" / "Slower"
    let decisionSpeedLabel: String
    /// When set, show "Average decision time: X.XX seconds" under Decision Speed.
    let avgDecisionTimeSeconds: Double?
    /// When set, show "Decision Speed Score: XX" (0–100, combines correctness and reaction speed).
    let decisionSpeedScore: Int?
    /// Previous session metrics for comparison (nil = no previous session).
    let previousDecisionSpeedScore: Int?
    let previousAvgReactionTimeSeconds: Double?
    let previousCorrect: Int?
    let previousTotal: Int?
    /// Best Decision Speed Score for this player and activity (from sessions). Shown as "Personal Best: XX".
    let personalBest: Int?
    /// True when this session's score is a new personal best.
    let isNewPersonalBest: Bool
    /// When decision speed score is 0, optionally show a short hint (e.g. why score is 0).
    var decisionSpeedScoreZeroHint: String? = nil
    let coachFeedback: String
    /// When set, debrief headline / trend / next step use the coaching system with same-activity previous session.
    var sessionResultForDebrief: SessionResult? = nil
    var previousSessionRecordForDebrief: SessionRecord? = nil
    let onContinue: () -> Void

    init(
        activityName: String,
        activityKind: ActivityKind,
        correct: Int,
        total: Int,
        firstTouchAccuracy: String?,
        decisionSpeedLabel: String,
        avgDecisionTimeSeconds: Double?,
        decisionSpeedScore: Int? = nil,
        previousDecisionSpeedScore: Int? = nil,
        previousAvgReactionTimeSeconds: Double? = nil,
        previousCorrect: Int? = nil,
        previousTotal: Int? = nil,
        personalBest: Int? = nil,
        isNewPersonalBest: Bool = false,
        decisionSpeedScoreZeroHint: String? = nil,
        coachFeedback: String,
        sessionResultForDebrief: SessionResult? = nil,
        previousSessionRecordForDebrief: SessionRecord? = nil,
        onContinue: @escaping () -> Void
    ) {
        self.activityName = activityName
        self.activityKind = activityKind
        self.correct = correct
        self.total = total
        self.firstTouchAccuracy = firstTouchAccuracy
        self.decisionSpeedLabel = decisionSpeedLabel
        self.avgDecisionTimeSeconds = avgDecisionTimeSeconds
        self.decisionSpeedScore = decisionSpeedScore
        self.previousDecisionSpeedScore = previousDecisionSpeedScore
        self.previousAvgReactionTimeSeconds = previousAvgReactionTimeSeconds
        self.previousCorrect = previousCorrect
        self.previousTotal = previousTotal
        self.personalBest = personalBest
        self.isNewPersonalBest = isNewPersonalBest
        self.decisionSpeedScoreZeroHint = decisionSpeedScoreZeroHint
        self.coachFeedback = coachFeedback
        self.sessionResultForDebrief = sessionResultForDebrief
        self.previousSessionRecordForDebrief = previousSessionRecordForDebrief
        self.onContinue = onContinue
    }

    private var narrative: PBAPostSessionNarrative {
        PBAPostSessionNarrativeBuilder.forTrainingComplete(
            activityName: activityName,
            activity: activityKind,
            correct: correct,
            total: total,
            avgSeconds: avgDecisionTimeSeconds,
            decisionSpeedScore: decisionSpeedScore,
            previousScore: previousDecisionSpeedScore,
            previousAvg: previousAvgReactionTimeSeconds,
            previousCorrect: previousCorrect,
            coachFeedback: coachFeedback,
            currentSessionResult: sessionResultForDebrief,
            previousSessionRecord: previousSessionRecordForDebrief
        )
    }

    private var primaryMetricLabel: String {
        switch activityKind {
        case .awayFromPressure: return "Correct first decisions"
        case .dribbleOrPass: return "Decision correctness"
        case .oneTouchPassing: return "Decision window"
        case .twoMinuteTest: return "Balanced score"
        }
    }

    private var primaryMetricValue: String {
        let accuracy = "\(correct) / \(total)"
        if let avg = avgDecisionTimeSeconds {
            let window = DecisionTimingModel.decisionWindow(rawRepInterval: avg, activity: activityKind)
            switch activityKind {
            case .awayFromPressure, .dribbleOrPass:
                return accuracy
            case .oneTouchPassing:
                return DecisionTimingModel.summaryText(windowSeconds: window)
            case .twoMinuteTest:
                let pct = total > 0 ? Int(round(Double(correct) / Double(total) * 100.0)) : 0
                return "\(pct)% · \(DecisionTimingModel.summaryText(windowSeconds: window))"
            }
        }
        return accuracy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Training Complete")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                Text(activityName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.65))

                PBAPostSessionNarrativeStack(narrative: narrative)

                Text("Your numbers")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white.opacity(0.95))
                Text("Reference only — your coach debrief is above.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))

                VStack(alignment: .leading, spacing: 14) {
                    row(primaryMetricLabel, primaryMetricValue)
                    if let avg = avgDecisionTimeSeconds {
                        let window = DecisionTimingModel.decisionWindow(rawRepInterval: avg, activity: activityKind)
                        if activityKind != .oneTouchPassing {
                            row("Decision window", DecisionTimingModel.summaryText(windowSeconds: window))
                        }
                    }
                    if activityKind != .awayFromPressure && activityKind != .dribbleOrPass {
                        row("Correct decisions", "\(correct) / \(total)")
                    }
                    if let score = decisionSpeedScore {
                        row("Decision Speed Score", "\(score)")
                        if score == 0, let hint = decisionSpeedScoreZeroHint {
                            Text(hint)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.75))
                        }
                        if isNewPersonalBest {
                            Text("New personal best score")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.yellow)
                        }
                        if let best = personalBest {
                            row("Your best score (this activity)", "\(best)")
                        }
                    }
                    if let ft = firstTouchAccuracy {
                        row("Decision–action match", ft)
                    }
                    row("Tempo vs last block", decisionSpeedLabel)
                }
                .padding(.vertical, 8)

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
