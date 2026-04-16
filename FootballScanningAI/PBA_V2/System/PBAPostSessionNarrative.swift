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
            nextStepBody: "Train again to build consistency, or explore the next activity in your curriculum when you're ready.",
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
        let activityTitle = activityDisplayName(session.activityType)
        let insight = CoachInsightGenerator.insightPackage(for: session, previous: previousSession)
        let headline = primaryMetricHeadlineLead(session: session, baseHeadline: insight.headline)

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

        let insightText = coachInsightBlock(for: session, coachFieldMeaning: insight.fieldMeaning)
        let next = nextStepRecommendation(session: session, progressStore: progressStore, previous: previousSession)
        let nextBody = next.body

        return PBAPostSessionNarrative(
            headlineInsight: headline,
            progressSectionTitle: "Trend — compared to your last \(activityTitle) session",
            progressLines: lines,
            coachInsight: insightText,
            nextStepTitle: next.title,
            nextStepBody: nextBody,
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

        let insight = CoachInsightGenerator.insightPackage(forTwoMinute: result, previous: previousTwoMinute)
        let headline = previousTwoMinute == nil
            ? headlineForFirstTwoMinute(playerType: playerType, accuracyPercent: accPct, decisionWindowSeconds: window)
            : insight.headline

        var lines: [String] = []
        var placeholder = false
        if let prev = previousTwoMinute {
            let syn = twoMinuteSyntheticSession(result: result, playerId: playerId)
            lines.append(contentsOf: trendLinesDecisionTimeAndCorrect(session: syn, previous: prev, activityTitle: "2-Minute Test", block: false))
            if lines.isEmpty {
                lines.append("Consistent with your last 2-Minute Test — keep sharpening scanning and first decisions.")
            }
        } else {
            lines.append("First test logged — next time you'll see how you trend.")
            placeholder = true
        }

        let synForInsight = twoMinuteSyntheticSession(result: result, playerId: playerId)
        let coachText = coachInsightBlock(for: synForInsight, coachFieldMeaning: insight.fieldMeaning)

        let next = nextStepTwoMinute(result: result, previous: previousTwoMinute, progressStore: progressStore, playerType: playerType, playerId: playerId)
        let nextBody = next.body

        return PBAPostSessionNarrative(
            headlineInsight: headline,
            progressSectionTitle: "Compared to your last 2-Minute Test",
            progressLines: lines,
            coachInsight: coachText.trimmingCharacters(in: .whitespacesAndNewlines),
            nextStepTitle: next.title,
            nextStepBody: nextBody,
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
            let pkg = CoachInsightGenerator.insightPackage(for: cur, previous: previousSessionRecord)
            headline = primaryMetricHeadlineLead(session: cur, baseHeadline: pkg.headline)
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
            avgSeconds: avgSeconds,
            correct: correct,
            total: total,
            previous: previousSessionRecord
        )
        if let cur = currentSessionResult {
            let insight = CoachInsightGenerator.insightPackage(for: cur, previous: previousSessionRecord)
            let coachText = coachInsightBlock(for: cur, coachFieldMeaning: insight.fieldMeaning)
            let nextBody = CoachInsightGenerator.nextStepPackage(for: cur, previous: previousSessionRecord).instruction
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

    /// Activity-aware primary + secondary trend lines (B). No score / percentile.
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
        case .playmaker: return "High standard — keep testing yourself in more complex scenarios"
        }
    }

    private static func accuracyPercent(_ session: SessionResult) -> Int {
        guard session.totalReps > 0 else { return 0 }
        return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100))
    }

    private static func primaryMetricHeadlineLead(session: SessionResult, baseHeadline: String) -> String {
        let acc = accuracyPercent(session)
        let window = session.avgDecisionWindowSeconds ?? -0.9
        switch session.activityType {
        case .awayFromPressure:
            if acc >= 85 { return "First-decision accuracy is improving — \(baseHeadline)" }
            if acc < 70 { return "Opposite-direction choices are the focus — \(baseHeadline)" }
            return baseHeadline
        case .dribbleOrPass:
            if acc >= 82 { return "Choice quality is strong — \(baseHeadline)" }
            if acc < 70 { return "Fix decision quality first — \(baseHeadline)" }
            return baseHeadline
        case .oneTouchPassing:
            if window >= 0.53 { return "One-touch timing is ahead of arrival — \(baseHeadline)" }
            if window < 0.0 { return "One-touch timing is still late — \(baseHeadline)" }
            return baseHeadline
        case .twoMinuteTest:
            if acc >= 80, window >= 0.51 { return "Balanced test: timing and choices both improved — \(baseHeadline)" }
            return baseHeadline
        }
    }

    /// Narrative anchor + `CoachInsightGenerator` field meaning can both resolve to the same coach line (e.g. “Speed of play is speed of thought.”).
    /// Dedupe so the insight card doesn’t show the same sentence twice.
    private static func coachInsightBlock(for session: SessionResult, coachFieldMeaning: String) -> String {
        let anchor = maybeNarrativeAnchor(activity: session.activityType, sessionId: session.id, context: .fieldMeaning)
        let field = coachFieldMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let ctx = gameContextLine(for: session.activityType).trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        func appendIfDistinct(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            if parts.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                return
            }
            parts.append(t)
        }
        if let anchor {
            appendIfDistinct(anchor)
        }
        appendIfDistinct(field)
        appendIfDistinct(ctx)
        return parts.joined(separator: " ")
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

    private static func nextStepRecommendation(session: SessionResult, progressStore: ProgressStore, previous: SessionRecord?) -> (title: String, body: String) {
        _ = progressStore
        let next = CoachInsightGenerator.nextStepPackage(for: session, previous: previous)
        return ("Next step", next.instruction)
    }

    private static func nextStepTwoMinute(result: TwoMinuteTestResult, previous: SessionRecord?, progressStore: ProgressStore, playerType: PlayerType, playerId: UUID?) -> (title: String, body: String) {
        _ = playerType
        _ = progressStore
        _ = playerId
        let next = CoachInsightGenerator.nextStepPackage(forTwoMinute: result, previous: previous)
        return ("Next step", next.instruction)
    }

    private static func trainingCompleteGameLine(activity: ActivityKind) -> String {
        gameContextLine(for: activity)
    }

    private static func trainingCompleteNextStep(
        activity: ActivityKind,
        accuracyPercent: Int,
        avgSeconds: Double?,
        correct: Int,
        total: Int,
        previous: SessionRecord?
    ) -> (title: String, body: String) {
        let synthetic = SessionResult(
            playerID: previous?.playerId ?? UUID(),
            activityType: activity,
            correctCount: correct,
            totalReps: max(total, 1),
            speedCounts: SessionSpeedCounts(fast: 0, medium: 0, slow: 0),
            avgDecisionTime: avgSeconds,
            difficulty: previous?.difficulty
        )
        _ = accuracyPercent
        let next = CoachInsightGenerator.nextStepPackage(for: synthetic, previous: previous)
        return ("Next step", next.instruction)
    }

    private static func activityDisplayName(_ kind: ActivityKind) -> String {
        switch kind {
        case .twoMinuteTest: return "2-Minute Test"
        case .awayFromPressure: return "Playing Away From Pressure"
        case .dribbleOrPass: return "Dribble or Pass"
        case .oneTouchPassing: return "One-Touch Passing"
        }
    }

    private enum NarrativeAnchorContext {
        case fieldMeaning
        case nextStep
    }

    private static func maybeNarrativeAnchor(activity: ActivityKind, sessionId: UUID, context: NarrativeAnchorContext) -> String? {
        guard shouldUseNarrativeAnchor(sessionId: sessionId, salt: context == .fieldMeaning ? 401 : 409, threshold: 35) else {
            return nil
        }
        switch (activity, context) {
        case (.awayFromPressure, .fieldMeaning):
            return "The window closes before the ball gets to you."
        case (.dribbleOrPass, .fieldMeaning):
            return "Speed of play is speed of thought."
        case (.oneTouchPassing, .fieldMeaning):
            return "One-touch only works if your decision is made before expected arrival."
        case (.twoMinuteTest, .fieldMeaning):
            return "Decide before expected arrival."
        case (.awayFromPressure, .nextStep):
            return "Decide before expected arrival"
        case (.dribbleOrPass, .nextStep):
            return "The window closes before the ball gets to you"
        case (.oneTouchPassing, .nextStep):
            return "Speed of play is speed of thought"
        case (.twoMinuteTest, .nextStep):
            return "Decide before expected arrival"
        }
    }

    private static func shouldUseNarrativeAnchor(sessionId: UUID, salt: Int, threshold: Int) -> Bool {
        var hasher = Hasher()
        hasher.combine(sessionId)
        hasher.combine(salt)
        let value = abs(hasher.finalize()) % 100
        return value < threshold
    }
}
