//
//  PBAPostSessionNarrative.swift
//  FootballScanningAI
//
//  Post-session copy: headline insight, trend vs previous same-activity session, soccer meaning, next step.
//  Uses existing SessionResult / SessionRecord metrics only — no new scoring system.
//

import Foundation

/// Coaching debrief: headline → trend (same activity) → coach insight → next step → (caller: your numbers).
struct PBAPostSessionNarrative: Equatable {
    /// A. Headline — short, impactful debrief hook.
    var headlineInsight: String
    /// B. Trend section title (explicit same-activity framing).
    var progressSectionTitle: String
    /// B. Trend bullets: decision time + correct decisions vs last same activity.
    var progressLines: [String]
    /// C. Coach insight — data → soccer meaning; may include anchor phrases.
    var coachInsight: String
    /// D. Next step title.
    var nextStepTitle: String
    /// D. Next step — one clear action tied to the coaching theme.
    var nextStepBody: String
    /// When true, trend lines are placeholders (not enough history).
    var usesProgressPlaceholder: Bool

    static let progressPlaceholderNote = "Keep training to unlock session-to-session trends."

    static func emptyPlaceholder(activityTitle: String) -> PBAPostSessionNarrative {
        PBAPostSessionNarrative(
            headlineInsight: "Session complete — \(activityTitle)",
            progressSectionTitle: "Compared to your last \(activityTitle) session",
            progressLines: [progressPlaceholderNote],
            coachInsight: "Every rep trains habits that show up under pressure — keep stacking quality reps.",
            nextStepTitle: "Next step",
            nextStepBody: "Train again to build consistency.",
            usesProgressPlaceholder: true
        )
    }
}

enum PBAPostSessionNarrativeBuilder {

    // MARK: - Session summary (AFP, DOP, OTP, 2-min block path)

    static func fromSessionResult(
        _ session: SessionResult,
        previousSession: SessionRecord?,
        progressStore: ProgressStore
    ) -> PBAPostSessionNarrative {
        let activityTitle = session.activityType.displayName
        let headline = primaryMetricHeadline(for: session)

        var lines: [String] = []
        var placeholder = false
        if let prev = previousSession {
            lines.append(contentsOf: trendLinesDecisionTimeAndCorrect(session: session, previous: prev, activityTitle: activityTitle, block: false))
            if lines.isEmpty {
                lines.append("Compared to your last \(activityTitle) session: similar overall level. Small gains add up.")
            }
        } else {
            lines.append(PBAPostSessionNarrative.progressPlaceholderNote)
            placeholder = true
        }

        let insightText = coachInsightBlock(for: session)
        let next = nextStepRecommendation(session: session, previous: previousSession)

        return PBAPostSessionNarrative(
            headlineInsight: headline,
            progressSectionTitle: "Trend — compared to your last \(activityTitle) session",
            progressLines: lines,
            coachInsight: insightText,
            nextStepTitle: next.title,
            nextStepBody: next.body,
            usesProgressPlaceholder: placeholder
        )
    }

    // MARK: - 2-Minute Test (initial test results)

    static func fromTwoMinuteTestResult(
        _ result: TwoMinuteTestResult,
        playerType: PlayerType,
        previousTwoMinute: SessionRecord?,
        progressStore: ProgressStore,
        playerId: UUID?
    ) -> PBAPostSessionNarrative {
        let accPct = result.totalReps > 0 ? Int(round(Double(result.correctCount) / Double(result.totalReps) * 100)) : 0
        let window = result.avgDecisionWindowSeconds ?? 0

        let headline = previousTwoMinute == nil
            ? headlineForFirstTwoMinute(playerType: playerType, accuracyPercent: accPct, decisionWindowSeconds: window)
            : primaryMetricHeadline(for: twoMinuteSyntheticSession(result: result, playerId: playerId))

        var lines: [String] = []
        var placeholder = false
        if let prev = previousTwoMinute {
            let syn = twoMinuteSyntheticSession(result: result, playerId: playerId)
            lines.append(contentsOf: trendLinesDecisionTimeAndCorrect(session: syn, previous: prev, activityTitle: ActivityKind.twoMinuteTest.displayName, block: false))
            if lines.isEmpty {
                lines.append("Consistent with your last \(ActivityKind.twoMinuteTest.displayName) — keep sharpening scanning and first decisions.")
            }
        } else {
            lines.append("First session logged — next time you'll see how you trend.")
            placeholder = true
        }

        let synForInsight = twoMinuteSyntheticSession(result: result, playerId: playerId)
        let coachText = coachInsightBlock(for: synForInsight)
        let next = nextStepTwoMinute(result: result, previous: previousTwoMinute)

        return PBAPostSessionNarrative(
            headlineInsight: headline,
            progressSectionTitle: "Compared to your last \(ActivityKind.twoMinuteTest.displayName)",
            progressLines: lines,
            coachInsight: coachText.trimmingCharacters(in: .whitespacesAndNewlines),
            nextStepTitle: next.title,
            nextStepBody: next.body,
            usesProgressPlaceholder: placeholder
        )
    }

    // MARK: - Training complete (immediate block feedback)

    static func forTrainingComplete(
        activityName: String,
        activity: ActivityKind,
        correct: Int,
        total: Int,
        avgSeconds: Double?,
        decisionSpeedScore: Int?,
        previousScore: Int?,
        previousAvg: Double?,
        previousCorrect: Int?,
        coachFeedback: String,
        currentSessionResult: SessionResult? = nil,
        previousSessionRecord: SessionRecord? = nil
    ) -> PBAPostSessionNarrative {
        let accPct = total > 0 ? Int(round(Double(correct) / Double(total) * 100)) : 0

        let headline: String
        if let cur = currentSessionResult {
            headline = primaryMetricHeadline(for: cur)
        } else if let ps = previousScore, let cs = decisionSpeedScore {
            let d = cs - ps
            if d >= 5 {
                headline = "Your decision quality improved this block"
            } else if d <= -5 {
                headline = "Tough block — reset and come back sharper"
            } else if accPct >= 75 {
                headline = "Solid reading — you're building match habits"
            } else {
                headline = "Keep stacking reps — consistency builds speed"
            }
        } else if accPct >= 80 {
            headline = "Strong choices — you're ahead of the play"
        } else if accPct >= 65 {
            headline = "Good foundation — push for earlier decisions next block"
        } else {
            headline = "Every rep counts — one clear picture before expected arrival"
        }

        var lines: [String] = []
        var placeholder = false
        if let prev = previousSessionRecord, let cur = currentSessionResult {
            lines.append(contentsOf: trendLinesDecisionTimeAndCorrect(session: cur, previous: prev, activityTitle: activityName, block: true))
        } else {
            if let pRaw = previousAvg, let cRaw = avgSeconds {
                let p = DecisionTimingModel.decisionWindow(rawRepInterval: pRaw, activity: activity)
                let c = DecisionTimingModel.decisionWindow(rawRepInterval: cRaw, activity: activity)
                let diff = c - p
                if diff > 0.02 {
                    lines.append(String(format: "Decision window: +%.2f s vs your last %@ block", diff, activityName))
                } else if diff < -0.02 {
                    lines.append(String(format: "Decision window: %.2f s vs your last %@ block", diff, activityName))
                } else {
                    lines.append("Decision window: similar to your last \(activityName) block")
                }
            }
            if let pc = previousCorrect {
                let d = correct - pc
                if d > 0 { lines.append("Correct decisions: +\(d) vs your last \(activityName) block") }
                else if d < 0 { lines.append("Correct decisions: \(d) vs your last \(activityName) block") }
                else { lines.append("Correct decisions: same as your last \(activityName) block") }
            }
        }
        if lines.isEmpty {
            lines.append(PBAPostSessionNarrative.progressPlaceholderNote)
            placeholder = true
        }

        let nextFallback = trainingCompleteNextStep(
            activity: activity,
            accuracyPercent: accPct,
            correct: correct,
            total: total
        )
        if let cur = currentSessionResult {
            let coachText = coachInsightBlock(for: cur)
            let nextBody = simpleNextStep(for: cur, previous: previousSessionRecord)
            return PBAPostSessionNarrative(
                headlineInsight: headline,
                progressSectionTitle: "Compared to your last \(activityName) block",
                progressLines: lines,
                coachInsight: coachText.trimmingCharacters(in: .whitespacesAndNewlines),
                nextStepTitle: nextFallback.title,
                nextStepBody: nextBody,
                usesProgressPlaceholder: placeholder
            )
        }

        let gameLine = trainingCompleteGameLine(activity: activity)
        let coachText = "\(coachFeedback) \(gameLine)".trimmingCharacters(in: .whitespacesAndNewlines)

        return PBAPostSessionNarrative(
            headlineInsight: headline,
            progressSectionTitle: "Compared to your last \(activityName) block",
            progressLines: lines,
            coachInsight: coachText,
            nextStepTitle: nextFallback.title,
            nextStepBody: nextFallback.body,
            usesProgressPlaceholder: placeholder
        )
    }

    // MARK: - Headlines & helpers

    private static func twoMinuteSyntheticSession(result: TwoMinuteTestResult, playerId: UUID?) -> SessionResult {
        SessionResult(
            playerID: playerId ?? UUID(),
            activityType: .twoMinuteTest,
            correctCount: result.correctCount,
            totalReps: result.totalReps,
            speedCounts: SessionSpeedCounts(fast: result.fastCount, medium: result.mediumCount, slow: result.slowCount),
            avgDecisionTime: result.avgDecisionTime,
            biasDirection: result.biasDirection,
            directionCounts: result.directionCounts,
            difficulty: result.difficulty
        )
    }

  private static func trendLinesDecisionTimeAndCorrect(session: SessionResult, previous: SessionRecord, activityTitle: String, block: Bool) -> [String] {
        let suffix = block ? "block" : "session"
        var decisionWindowLine: String?
        if let c = session.avgDecisionWindowSeconds, let p = previous.avgDecisionWindowSeconds {
            let diff = c - p
            if diff > 0.02 {
                decisionWindowLine = String(format: "Decision window: +%.2f s vs your last %@ %@", diff, activityTitle, suffix)
            } else if diff < -0.02 {
                decisionWindowLine = String(format: "Decision window: %.2f s vs your last %@ %@", diff, activityTitle, suffix)
            } else {
                decisionWindowLine = "Decision window: similar to your last \(activityTitle) \(suffix)"
            }
        } else if session.avgDecisionWindowSeconds != nil || previous.avgDecisionWindowSeconds != nil {
            decisionWindowLine = "Decision window: not enough data to compare to your last \(activityTitle) \(suffix)"
        }

        let d = session.correctCount - previous.correct
        let correctnessLabel: String = {
            switch session.activityType {
            case .awayFromPressure: return "Correct first decisions"
            case .dribbleOrPass: return "Decision correctness"
            case .oneTouchPassing: return "Correct decisions"
            case .twoMinuteTest: return "Correct decisions"
            }
        }()
        let correctnessLine: String
        if d > 0 {
            correctnessLine = "\(correctnessLabel): +\(d) vs your last \(activityTitle) \(suffix)"
        } else if d < 0 {
            correctnessLine = "\(correctnessLabel): \(d) vs your last \(activityTitle) \(suffix)"
        } else {
            correctnessLine = "\(correctnessLabel): same count as your last \(activityTitle) \(suffix)"
        }

        switch session.activityType {
        case .awayFromPressure, .dribbleOrPass:
            return [correctnessLine] + (decisionWindowLine.map { [$0] } ?? [])
        case .oneTouchPassing:
            if let decisionWindowLine { return [decisionWindowLine, correctnessLine] }
            return [correctnessLine]
        case .twoMinuteTest:
            if let decisionWindowLine { return [decisionWindowLine, correctnessLine] }
            return [correctnessLine]
        }
    }

    private static func headlineForFirstTwoMinute(playerType: PlayerType, accuracyPercent: Int, decisionWindowSeconds: Double) -> String {
        if accuracyPercent >= 80, decisionWindowSeconds >= 0.51 {
            return "Strong first look — you're ahead of the ball"
        }
        switch playerType {
        case .reactor: return "You're reacting in the moment — next step is earlier pictures"
        case .scanner: return "You're scanning — now commit faster under pressure"
        case .anticipator: return "You're reading patterns — sharpen execution on the first action"
        case .playmaker: return "High standard — keep challenging yourself in more complex scenarios"
        }
    }

    private static func accuracyPercent(_ session: SessionResult) -> Int {
        guard session.totalReps > 0 else { return 0 }
        return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100))
    }

    private static func primaryMetricHeadline(for session: SessionResult) -> String {
        let acc = accuracyPercent(session)
        switch session.activityType {
        case .awayFromPressure:
            if acc >= 85 { return "First-decision accuracy is improving" }
            if acc < 70 { return "Focus on opposite-direction choices under pressure" }
            return "Solid away-from-pressure block"
        case .dribbleOrPass:
            if acc >= 82 { return "Choice quality is strong" }
            if acc < 70 { return "Fix decision quality first" }
            return "Good dribble-or-pass reps"
        case .oneTouchPassing:
            let window = session.avgDecisionWindowSeconds ?? -0.9
            if window >= 0.53 { return "One-touch timing is ahead of arrival" }
            if window < 0.0 { return "One-touch timing is still late" }
            return "Keep sharpening one-touch decisions"
        case .twoMinuteTest:
            if acc >= 80 { return "Balanced session: timing and choices both on track" }
            return "Keep building scanning habits"
        }
    }

    private static func coachInsightBlock(for session: SessionResult) -> String {
        let ctx = gameContextLine(for: session.activityType).trimmingCharacters(in: .whitespacesAndNewlines)
        let acc = accuracyPercent(session)
        let performance: String
        if acc >= 80 {
            performance = "Strong decision quality this session."
        } else if acc >= 65 {
            performance = "Decent foundation — aim for earlier, clearer choices."
        } else {
            performance = "Reset and look for one clear picture before the ball arrives."
        }
        return "\(performance) \(ctx)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func gameContextLine(for activity: ActivityKind) -> String {
        switch activity {
        case .twoMinuteTest:
            return "On the field, that maps to cleaner decisions when a defender closes you down."
        case .awayFromPressure:
            return "In matches, that means turning away from pressure into space — not just finding any open lane."
        case .dribbleOrPass:
            return "In real soccer, that shows up as picking forward or safe options faster when you're pressed."
        case .oneTouchPassing:
            return "In games, that translates to sharper one-touch choices when tempo is high."
        }
    }

    private static func nextStepRecommendation(session: SessionResult, previous: SessionRecord?) -> (title: String, body: String) {
        ("Next step", simpleNextStep(for: session, previous: previous))
    }

    private static func nextStepTwoMinute(result: TwoMinuteTestResult, previous: SessionRecord?) -> (title: String, body: String) {
        let syn = twoMinuteSyntheticSession(result: result, playerId: nil)
        return ("Next step", simpleNextStep(for: syn, previous: previous))
    }

    private static func simpleNextStep(for session: SessionResult, previous: SessionRecord?) -> String {
        let acc = accuracyPercent(session)
        if let prev = previous, session.correctCount < prev.correct {
            return "Run another block and commit to your first decision before pressure arrives."
        }
        switch session.activityType {
        case .awayFromPressure:
            return acc >= 75 ? "Train again to lock in first-touch escapes under pressure." : "Slow the picture down — pick the opposite gate earlier."
        case .dribbleOrPass:
            return acc >= 75 ? "Keep stacking reps with forward intent when space is there." : "Prioritize correct choices before speed."
        case .oneTouchPassing:
            return "Train again and decide before the pass arrives."
        case .twoMinuteTest:
            return "Start a training block or retest when you want a fresh baseline."
        }
    }

    private static func trainingCompleteGameLine(activity: ActivityKind) -> String {
        gameContextLine(for: activity)
    }

    private static func trainingCompleteNextStep(
        activity: ActivityKind,
        accuracyPercent: Int,
        correct: Int,
        total: Int
    ) -> (title: String, body: String) {
        let synthetic = SessionResult(
            playerID: UUID(),
            activityType: activity,
            correctCount: correct,
            totalReps: max(total, 1),
            speedCounts: SessionSpeedCounts(fast: 0, medium: 0, slow: 0)
        )
        _ = accuracyPercent
        return ("Next step", simpleNextStep(for: synthetic, previous: nil))
    }
}
