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

    /// Convert average decision time (seconds) to Decision Speed grade. Thresholds: A < 0.75, B 0.75–0.95, C 0.95–1.15, D 1.15–1.35, F > 1.35.
    static func from(averageDecisionTimeSeconds: Double) -> ReportCardGrade {
        switch averageDecisionTimeSeconds {
        case ..<0.75: return .a
        case 0.75..<0.95: return .b
        case 0.95..<1.15: return .c
        case 1.15..<1.35: return .d
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
        let dbc = gradeDecisionBeforeContact(sessions: chartSessions)
        let speed = gradeDecisionSpeed(sessions: chartSessions)
        let ftc = gradeFirstTouchCommitment(sessions: chartSessions)
        let pressure = gradePressureEscape(sessions: chartSessions)
        let overall = gradeOverall(last5: last5, categoryGrades: [dbc, speed, ftc, pressure])
        let insight = coachingInsight(
            trainingRecommendation: trainingRecommendation,
            decisionBeforeContact: dbc,
            decisionSpeed: speed,
            firstTouchCommitment: ftc,
            pressureEscape: pressure
        )
        let decisionSpeedDisplay = decisionSpeedDisplayString(sessions: chartSessions, grade: speed)
        return ReportCardData(
            decisionBeforeContact: dbc?.display ?? "—",
            decisionSpeed: decisionSpeedDisplay,
            firstTouchCommitment: ftc?.display ?? "—",
            pressureEscape: pressure?.display ?? "—",
            overallGrade: overall?.display ?? "—",
            coachingInsight: insight
        )
    }

    /// Decision Before Contact: % where decisionTime < threshold and firstTouch == correct. From sessions that have preReceiveDecisionCount.
    private static func gradeDecisionBeforeContact(sessions: [SessionResult]) -> ReportCardGrade? {
        let withData = sessions.filter { $0.preReceiveDecisionCount != nil && $0.totalReps > 0 }
        guard !withData.isEmpty else { return nil }
        let sum = withData.reduce(0.0) { acc, s in
            acc + Double(s.preReceiveDecisionCount!) / Double(s.totalReps) * 100.0
        }
        let pct = sum / Double(withData.count)
        return ReportCardGrade.from(percentage: pct)
    }

    /// Decision Speed: grade from rolling average decision time (most recent 3–5 sessions). Requires at least 3 sessions with avgDecisionTime; otherwise nil (caller shows "Not enough data for grade" or "—").
    private static func gradeDecisionSpeed(sessions: [SessionResult]) -> ReportCardGrade? {
        let withTime = sessions  // assume newest first
            .filter { $0.avgDecisionTime != nil }
            .prefix(DecisionSpeedGrading.maxSessionsForAverage)
        guard withTime.count >= DecisionSpeedGrading.minSessionsForGrade else { return nil }
        let sum = withTime.reduce(0.0) { $0 + ($1.avgDecisionTime ?? 0) }
        let avgSeconds = sum / Double(withTime.count)
        return ReportCardGrade.from(averageDecisionTimeSeconds: avgSeconds)
    }

    /// Decision Speed display: letter grade when 3+ sessions; "Not enough data for grade" when 1–2; "—" when none.
    private static func decisionSpeedDisplayString(sessions: [SessionResult], grade: ReportCardGrade?) -> String {
        let withTimeCount = sessions.filter { $0.avgDecisionTime != nil }.count
        if let g = grade { return g.display }
        if withTimeCount >= 1 { return "Not enough data for grade" }
        return "—"
    }

    /// First Touch Commitment: % where first touch matched correct direction.
    private static func gradeFirstTouchCommitment(sessions: [SessionResult]) -> ReportCardGrade? {
        let withData = sessions.filter { $0.firstTouchMatchCount != nil && $0.totalReps > 0 }
        guard !withData.isEmpty else { return nil }
        let sum = withData.reduce(0.0) { acc, s in
            acc + Double(s.firstTouchMatchCount!) / Double(s.totalReps) * 100.0
        }
        let pct = sum / Double(withData.count)
        return ReportCardGrade.from(percentage: pct)
    }

    /// Pressure Escape: AFP only, % correct (successful escapes).
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
        decisionBeforeContact: ReportCardGrade?,
        decisionSpeed: ReportCardGrade?,
        firstTouchCommitment: ReportCardGrade?,
        pressureEscape: ReportCardGrade?
    ) -> String {
        let grades = [decisionBeforeContact, decisionSpeed, firstTouchCommitment, pressureEscape]
        let hasData = grades.contains { $0 != nil }
        guard hasData else {
            return "Complete a few training blocks to see your report card and personalized coaching insight."
        }
        let weakest: String
        if let dbc = decisionBeforeContact, dbc == .f || dbc == .d || dbc == .dMinus || dbc == .dPlus {
            weakest = "Deciding before the ball arrives"
        } else if let sp = decisionSpeed, sp == .f || sp == .d || sp == .dMinus || sp == .dPlus {
            weakest = "Decision speed"
        } else if let ftc = firstTouchCommitment, ftc == .f || ftc == .d || ftc == .dMinus || ftc == .dPlus {
            weakest = "First touch commitment"
        } else if let pe = pressureEscape, pe == .f || pe == .d || pe == .dMinus || pe == .dPlus {
            weakest = "Escaping pressure"
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
