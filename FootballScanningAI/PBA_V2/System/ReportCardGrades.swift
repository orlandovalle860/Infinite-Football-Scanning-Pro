//
//  ReportCardGrades.swift
//  FootballScanningAI
//
//  PBA V2 — Letter grades for Player Report Card from training metrics (0–100%).
//

import Foundation

/// Letter grade for a single category. Uses standard +/- scale.
enum ReportCardGrade: String {
    case aPlus = "A+"
    case a = "A"
    case aMinus = "A-"
    case bPlus = "B+"
    case b = "B"
    case bMinus = "B-"
    case cPlus = "C+"
    case c = "C"
    case cMinus = "C-"
    case dPlus = "D+"
    case d = "D"
    case dMinus = "D-"
    case f = "F"

    /// Convert a percentage (0–100) to a letter grade.
    static func from(percentage: Double) -> ReportCardGrade {
        switch percentage {
        case 97...: return .aPlus
        case 93..<97: return .a
        case 90..<93: return .aMinus
        case 87..<90: return .bPlus
        case 83..<87: return .b
        case 80..<83: return .bMinus
        case 77..<80: return .cPlus
        case 73..<77: return .c
        case 70..<73: return .cMinus
        case 67..<70: return .dPlus
        case 63..<67: return .d
        case 60..<63: return .dMinus
        default: return .f
        }
    }

    /// Convert average decision window (seconds before arrival) to Decision Timing grade.
    static func from(decisionWindowSeconds: Double) -> ReportCardGrade {
        switch decisionWindowSeconds {
        case 0.25...: return .a
        case 0.10..<0.25: return .b
        case 0.00..<0.10: return .c
        case -0.10..<0.00: return .d
        default: return .f
        }
    }

    var display: String { rawValue }
}

/// Decision Speed report-card grading: rolling average decision time (3–5 sessions). Minimum 3 sessions required for a letter grade.
private enum DecisionSpeedGrading {
    static let maxSessionsForAverage: Int = 5
    static let minSessionsForGrade: Int = 3
}

/// Data for the Player Report Card screen: four category grades, overall, and coaching insight.
struct ReportCardData {
    let decisionBeforeContact: String   // "B+" or "—"
    let decisionSpeed: String
    let firstTouchCommitment: String
    let pressureEscape: String
    let overallGrade: String
    let overallTier: String
    let overallTierDisplay: String
    let overallStageContext: String
    let overallSupportMessage: String
    let overallProgressionMessage: String
    let overallNextTarget: String
    let focusNext: String
    let nextLevelName: String
    let nextLevelRequirements: [String]
    let strength: String
    let limiter: String
    let decisionSpeedTier: String
    let decisionSpeedAvgTime: Double?
    let decisionSpeedZone: String
    let decisionSpeedMessage: String
    let accuracyPercent: Int?
    let accuracyTier: String
    let accuracyMessage: String
    let forwardThinkingPercent: Int?
    let forwardThinkingTier: String
    let forwardThinkingMessage: String
    let coachingInsight: String
}

// MARK: - Report Card Generator

enum ReportCardGenerator {
    /// Build report card from current profile's session results and training recommendation.
    static func reportCard(
        chartSessions: [SessionResult],
        last5: [SessionRecord],
        trainingRecommendation: TrainingRecommendationResult
    ) -> ReportCardData {
        let speed = gradeDecisionSpeed(sessions: chartSessions)
        let pressure = gradePressureEscape(sessions: chartSessions)
        let overall = gradeOverall(last5: last5, categoryGrades: [speed, pressure])
        let overallTier = overallTierName(from: overall)
        let overallTierDisplay = overallTierDisplay(from: overall)
        let stageContext = overallStageContext(from: overall)
        let supportMessage = overallSupportMessage(chartSessions: chartSessions)
        let progressionMessage = overallProgressionMessage(from: overall)
        let nextTarget = overallNextTarget(chartSessions: chartSessions)
        let speedAvg = rollingAverageDecisionTime(chartSessions: chartSessions)
        let speedZone = decisionSpeedZone(from: speedAvg)
        let speedTier = decisionSpeedTier(from: speedAvg)
        let speedMsg = decisionSpeedMessage(from: speedZone)
        let accuracyPercent = rollingAccuracyPercent(chartSessions: chartSessions)
        let accuracyTier = accuracyTier(from: accuracyPercent)
        let accuracyMsg = accuracyMessage(from: accuracyPercent, speedZone: speedZone)
        let forwardPercent = rollingForwardThinkingPercent(chartSessions: chartSessions)
        let forwardTier = forwardThinkingTier(from: forwardPercent)
        let forwardMsg = forwardThinkingMessage(from: forwardPercent)
        let focusNext = focusNext(speedZone: speedZone, accuracyPercent: accuracyPercent, forwardPercent: forwardPercent)
        let nextLevel = nextLevelName(currentTier: overallTier)
        let nextRequirements = nextLevelRequirements(currentTier: overallTier, speedAvg: speedAvg, accuracyPercent: accuracyPercent)
        let strength = strengthInsight(speedZone: speedZone, accuracyPercent: accuracyPercent, forwardPercent: forwardPercent)
        let limiter = limiterInsight(speedZone: speedZone, accuracyPercent: accuracyPercent, forwardPercent: forwardPercent)
        let insight = coachingInsight(
            trainingRecommendation: trainingRecommendation,
            decisionSpeed: speed,
            pressureEscape: pressure
        )
        let decisionSpeedDisplay = decisionSpeedDisplayString(sessions: chartSessions, grade: speed)
        return ReportCardData(
            decisionBeforeContact: "—",
            decisionSpeed: decisionSpeedDisplay,
            firstTouchCommitment: "—",
            pressureEscape: pressure?.display ?? "—",
            overallGrade: overall?.display ?? "—",
            overallTier: overallTier,
            overallTierDisplay: overallTierDisplay,
            overallStageContext: stageContext,
            overallSupportMessage: supportMessage,
            overallProgressionMessage: progressionMessage,
            overallNextTarget: nextTarget,
            focusNext: focusNext,
            nextLevelName: nextLevel,
            nextLevelRequirements: nextRequirements,
            strength: strength,
            limiter: limiter,
            decisionSpeedTier: speedTier,
            decisionSpeedAvgTime: speedAvg,
            decisionSpeedZone: speedZone,
            decisionSpeedMessage: speedMsg,
            accuracyPercent: accuracyPercent,
            accuracyTier: accuracyTier,
            accuracyMessage: accuracyMsg,
            forwardThinkingPercent: forwardPercent,
            forwardThinkingTier: forwardTier,
            forwardThinkingMessage: forwardMsg,
            coachingInsight: insight
        )
    }

    private static func nextLevelName(currentTier: String) -> String {
        switch currentTier {
        case "Needs Work", "Emerging": return "Developing"
        case "Developing": return "Strong"
        case "Strong": return "Elite"
        default: return "Elite"
        }
    }

    private static func nextLevelRequirements(currentTier: String, speedAvg: Double?, accuracyPercent: Int?) -> [String] {
        switch currentTier {
        case "Needs Work", "Emerging":
            return [
                "Decision window >= 0.00s",
                "Accuracy >= 80%"
            ]
        case "Developing":
            return [
                "Decision window >= +0.10s",
                "Accuracy >= 85%"
            ]
        case "Strong":
            return [
                "Decision window >= +0.25s",
                "Accuracy >= 90%"
            ]
        default:
            var requirements: [String] = []
            if let speedAvg { requirements.append("Maintain decision window around \(DecisionTimingModel.summaryText(windowSeconds: speedAvg))") }
            if let accuracyPercent { requirements.append("Maintain accuracy around \(accuracyPercent)%") }
            return requirements.isEmpty ? ["Maintain elite consistency"] : requirements
        }
    }

    private static func strengthInsight(speedZone: String, accuracyPercent: Int?, forwardPercent: Int?) -> String {
        if let accuracyPercent, accuracyPercent >= 90 { return "Decision Accuracy (\(accuracyPercent)%)" }
        if speedZone == "Elite" || speedZone == "Advanced" || speedZone == "Competent" { return "Decision Window (\(speedZone))" }
        if let forwardPercent, forwardPercent >= 60 { return "Forward Thinking (\(forwardPercent)%)" }
        return "Consistency in training sessions"
    }

    private static func limiterInsight(speedZone: String, accuracyPercent: Int?, forwardPercent: Int?) -> String {
        if speedZone == "Too Late" || speedZone == "Late" { return "Decision window timing is late" }
        if let accuracyPercent, accuracyPercent < 75 { return "Decision Accuracy consistency" }
        if let forwardPercent, forwardPercent < 50 { return "Forward Thinking choices" }
        return "Maintaining consistency under pressure"
    }

    private static func overallTierName(from grade: ReportCardGrade?) -> String {
        guard let grade else { return "No grade yet" }
        switch grade {
        case .aPlus, .a, .aMinus: return "Elite"
        case .bPlus, .b, .bMinus: return "Strong"
        case .cPlus, .c, .cMinus: return "Developing"
        case .dPlus, .d, .dMinus: return "Emerging"
        case .f: return "Needs Work"
        }
    }

    private static func overallTierDisplay(from grade: ReportCardGrade?) -> String {
        guard let grade else { return "⚪ No Grade Yet" }
        let label = overallTierName(from: grade)
        let icon: String
        switch label {
        case "Elite": icon = "🟢"
        case "Strong": icon = "🔵"
        case "Developing": icon = "🟡"
        case "Emerging": icon = "🟠"
        default: icon = "🔴"
        }
        return "\(icon) \(label) Timing"
    }

    private static func overallSupportMessage(chartSessions: [SessionResult]) -> String {
        let recent = Array(chartSessions.prefix(5))
        let withTime = recent.compactMap(\.avgDecisionWindowSeconds)
        let avgTime = withTime.isEmpty ? nil : withTime.reduce(0, +) / Double(withTime.count)
        let accuracyPct: Double? = {
            guard !recent.isEmpty else { return nil }
            let valid = recent.filter { $0.totalReps > 0 }
            guard !valid.isEmpty else { return nil }
            let accs = valid.map { Double($0.correctCount) / Double($0.totalReps) }
            return accs.reduce(0, +) / Double(accs.count)
        }()

        if let accuracyPct, let avgTime, accuracyPct >= 0.80, avgTime > 1.10 {
            return "You're making good choices, but often too close to arrival."
        }
        if let accuracyPct, accuracyPct >= 0.80 {
            return "You're making strong decisions with good consistency."
        }
        if let avgTime, avgTime > 1.20 {
            return "Your decision window is late under pressure—commit earlier."
        }
        return "You're building your timing and decision quality."
    }

    private static func overallProgressionMessage(from grade: ReportCardGrade?) -> String {
        guard let grade else { return "Complete more sessions to unlock your next tier." }
        switch grade {
        case .aPlus, .a, .aMinus:
            return "You're performing at an Elite level—maintain this standard."
        case .bPlus, .b, .bMinus:
            return "You're close to Elite (early decisions before arrival)."
        case .cPlus, .c, .cMinus:
            return "You're close to Strong (On-Time Decisions)."
        case .dPlus, .d, .dMinus:
            return "You're close to Developing (On-Time Decisions)."
        case .f:
            return "You're close to Emerging (Slightly Late Decisions)."
        }
    }

    private static func overallStageContext(from grade: ReportCardGrade?) -> String {
        guard let grade else { return "Stage 1 — Building Decision Timing" }
        switch grade {
        case .aPlus, .a, .aMinus: return "Stage 4 — Sustaining Elite Decisions"
        case .bPlus, .b, .bMinus: return "Stage 3 — Strengthening Decision Timing"
        case .cPlus, .c, .cMinus: return "Stage 2 — Developing Decision Timing"
        case .dPlus, .d, .dMinus, .f: return "Stage 1 — Building Decision Timing"
        }
    }

    private static func overallNextTarget(chartSessions: [SessionResult]) -> String {
        let recent = Array(chartSessions.prefix(5))
        let withTime = recent.compactMap(\.avgDecisionWindowSeconds)
        guard !withTime.isEmpty else { return "Next Target: Complete 3 timed sessions" }
        let avgTime = withTime.reduce(0, +) / Double(withTime.count)
        if avgTime < -0.10 { return "Next Target: Decision window >= -0.10s" }
        if avgTime < 0.00 { return "Next Target: Decision window >= 0.00s" }
        if avgTime < 0.10 { return "Next Target: Decision window >= +0.10s" }
        return "Next Target: Keep decision window positive consistently"
    }

    private static func rollingAverageDecisionTime(chartSessions: [SessionResult]) -> Double? {
        let recent = Array(chartSessions.prefix(5)).compactMap(\.avgDecisionWindowSeconds)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    private static func decisionSpeedZone(from avg: Double?) -> String {
        guard let avg else { return "No timing data yet" }
        if avg >= 0.25 { return "Elite" }
        if avg >= 0.10 { return "Advanced" }
        if avg >= 0.00 { return "Competent" }
        if avg >= -0.10 { return "Late" }
        return "Too Late"
    }

    private static func decisionSpeedTier(from avg: Double?) -> String {
        guard let avg else { return "Emerging" }
        if avg >= 0.25 { return "Elite" }
        if avg >= 0.10 { return "Strong" }
        if avg >= 0.00 { return "Developing" }
        if avg >= -0.10 { return "Emerging" }
        return "Too Late"
    }

    private static func decisionSpeedMessage(from zone: String) -> String {
        switch zone {
        case "Elite": return "Excellent — consistently deciding well before arrival."
        case "Advanced": return "Strong timing — usually before arrival."
        case "Competent": return "Solid baseline — decisions land around arrival."
        case "Late": return "You're often a beat late — decide earlier."
        case "Too Late": return "Decision comes after arrival too often — build earlier pictures."
        default: return "Complete more sessions to unlock timing feedback."
        }
    }

    private static func rollingAccuracyPercent(chartSessions: [SessionResult]) -> Int? {
        let recent = Array(chartSessions.prefix(5)).filter { $0.totalReps > 0 }
        guard !recent.isEmpty else { return nil }
        let avg = recent.reduce(0.0) { $0 + (Double($1.correctCount) / Double($1.totalReps)) } / Double(recent.count)
        return Int(round(avg * 100.0))
    }

    private static func accuracyTier(from percent: Int?) -> String {
        guard let percent else { return "Developing" }
        if percent >= 90 { return "Elite" }
        if percent >= 75 { return "Strong" }
        if percent >= 60 { return "Developing" }
        return "Emerging"
    }

    private static func accuracyMessage(from percent: Int?, speedZone: String) -> String {
        guard let percent else { return "Complete more sessions to unlock accuracy coaching." }
        if percent >= 85 && (speedZone == "Late" || speedZone == "Too Late") {
            return "Excellent accuracy — now increase time left before arrival."
        }
        if percent >= 85 { return "Great decision quality — keep consistency high." }
        if percent >= 70 { return "Good base — sharpen consistency under pressure." }
        return "Slow down slightly to improve decision quality."
    }

    private static func rollingForwardThinkingPercent(chartSessions: [SessionResult]) -> Int? {
        let recent = Array(chartSessions.prefix(5))
        let values: [Double] = recent.compactMap { s in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            return Double(choice) / Double(opp)
        }
        guard !values.isEmpty else { return nil }
        return Int(round((values.reduce(0, +) / Double(values.count)) * 100.0))
    }

    private static func forwardThinkingTier(from percent: Int?) -> String {
        guard let percent else { return "Locked" }
        if percent >= 70 { return "Elite" }
        if percent >= 50 { return "Strong" }
        return "Developing"
    }

    private static func forwardThinkingMessage(from percent: Int?) -> String {
        guard let percent else { return "Complete more sessions to unlock." }
        if percent < 50 { return "Look forward more when space is available." }
        if percent < 70 { return "Good forward intent — keep scanning for forward options." }
        return "Excellent forward decision-making."
    }

    private static func focusNext(speedZone: String, accuracyPercent: Int?, forwardPercent: Int?) -> String {
        if speedZone == "Too Late" || speedZone == "Late" { return "Decision Window" }
        if let accuracyPercent, accuracyPercent < 75 { return "Decision Accuracy" }
        if let forwardPercent, forwardPercent < 50 { return "Forward Thinking" }
        return "Decision Speed"
    }

    /// Decision Timing: grade from rolling average decision window (most recent 3–5 sessions). Requires at least 3 sessions with timing data.
    private static func gradeDecisionSpeed(sessions: [SessionResult]) -> ReportCardGrade? {
        let withTime = sessions  // assume newest first
            .filter { $0.avgDecisionWindowSeconds != nil }
            .prefix(DecisionSpeedGrading.maxSessionsForAverage)
        guard withTime.count >= DecisionSpeedGrading.minSessionsForGrade else { return nil }
        let sum = withTime.reduce(0.0) { $0 + ($1.avgDecisionWindowSeconds ?? 0) }
        let avgWindow = sum / Double(withTime.count)
        return ReportCardGrade.from(decisionWindowSeconds: avgWindow)
    }

    /// Decision Speed display: letter grade when 3+ sessions; "Not enough data for grade" when 1–2; "—" when none.
    private static func decisionSpeedDisplayString(sessions: [SessionResult], grade: ReportCardGrade?) -> String {
        let withTimeCount = sessions.filter { $0.avgDecisionWindowSeconds != nil }.count
        if let g = grade { return g.display }
        if withTimeCount >= 1 { return "Not enough data for grade" }
        return "—"
    }

    /// Away-from-pressure first decisions: AFP only, % correct (first decision opposite the red).
    private static func gradePressureEscape(sessions: [SessionResult]) -> ReportCardGrade? {
        let afp = sessions.filter { $0.activityType == .awayFromPressure }
        guard !afp.isEmpty else { return nil }
        let sum = afp.reduce(0.0) { acc, s in
            acc + (s.totalReps > 0 ? Double(s.correctCount) / Double(s.totalReps) * 100.0 : 0)
        }
        let pct = sum / Double(afp.count)
        return ReportCardGrade.from(percentage: pct)
    }

    /// Overall: use Dashboard decision score (0–100) when available; else average of category grades (as numeric midpoints).
    private static func gradeOverall(last5: [SessionRecord], categoryGrades: [ReportCardGrade?]) -> ReportCardGrade? {
        if !last5.isEmpty {
            let score = DashboardDecisionScore.score(from: last5)
            return ReportCardGrade.from(percentage: Double(score))
        }
        let numeric: [Double] = categoryGrades.compactMap { g in
            guard let g = g else { return nil }
            switch g {
            case .aPlus: return 98
            case .a: return 94
            case .aMinus: return 91
            case .bPlus: return 88
            case .b: return 84
            case .bMinus: return 81
            case .cPlus: return 78
            case .c: return 75
            case .cMinus: return 71
            case .dPlus: return 68
            case .d: return 65
            case .dMinus: return 61
            case .f: return 50
            }
        }
        guard !numeric.isEmpty else { return nil }
        let avg = numeric.reduce(0, +) / Double(numeric.count)
        return ReportCardGrade.from(percentage: avg)
    }

    private static func coachingInsight(
        trainingRecommendation: TrainingRecommendationResult,
        decisionSpeed: ReportCardGrade?,
        pressureEscape: ReportCardGrade?
    ) -> String {
        let grades = [decisionSpeed, pressureEscape]
        let hasData = grades.contains { $0 != nil }
        guard hasData else {
            return "Complete a few training blocks to see your report card and personalized coaching insight."
        }
        let weakest: String
        if let sp = decisionSpeed, sp == .f || sp == .d || sp == .dMinus || sp == .dPlus {
            weakest = "Decision speed"
        } else if let pe = pressureEscape, pe == .f || pe == .d || pe == .dMinus || pe == .dPlus {
            weakest = "Away-from-pressure first decisions"
        } else {
            weakest = ""
        }
        let focus = trainingRecommendation.focusLine
        let activityName: String
        switch trainingRecommendation.activity {
        case .twoMinuteTest: activityName = "the 2-Minute Test"
        case .awayFromPressure: activityName = "Playing Away From Pressure"
        case .dribbleOrPass: activityName = "Dribble or Pass"
        case .oneTouchPassing: activityName = "One-Touch Passing"
        }
        if !weakest.isEmpty {
            return "Your development is on track. Focus on \(weakest.lowercased()). Recommended next: \(activityName)—\(focus)."
        }
        let tip = trainingRecommendation.coachTip.isEmpty ? "Keep building consistency." : trainingRecommendation.coachTip
        return "\(tip) Recommended focus: \(activityName)—\(focus)."
    }
}
