//
//  TwoMinuteTestBehaviorBadges.swift
//  FootballScanningAI
//
//  Behavior-based badges from per-rep decision windows (RepLog timing).
//  Maps each rep to EARLY / IDEAL / LATE using the same raw interval → window pipeline as
//  DecisionTimingModel + 2-Minute aggregate scoring (no change to scores).
//

import Foundation

/// Semantic buckets aligned with “when did you know?” — derived from decision window (s before expected arrival).
enum TwoMinutePerceptionTimingCategory: String {
    /// “As soon as the visual appeared” — strong early decision.
    case early
    /// “While the ball was traveling.”
    case ideal
    /// “Right before receiving”, “As I received the ball”, “After my first touch” — late / reactive.
    case late
}

/// Outcome of badge rules (counts + which flags fired).
struct TwoMinuteBehaviorBadgeEvaluation: Equatable {
    let earlyCount: Int
    let idealCount: Int
    let lateCount: Int
    let total: Int
    let forwardThinkerUnlocked: Bool
    let onTimeUnlocked: Bool
    let reactiveTriggered: Bool
}

enum TwoMinuteBehaviorBadgeEvaluator {
    /// EARLY: decision window ≥ this (seconds before expected arrival). Matches ~advanced+ band for 2-min test.
    private static let earlyBandMinWindow: Double = 0.51
    /// IDEAL band: [idealBandMinWindow, earlyBandMinWindow). Matches competent–advanced transition.
    private static let idealBandMinWindow: Double = 0.33
    /// Below idealBandMinWindow → LATE.

    /// Classify one rep using the same trigger→exit interval as ``TwoMinuteTestResult.from(logs:)``.
    static func timingCategory(for log: RepLog, difficulty: TestDifficulty) -> TwoMinutePerceptionTimingCategory {
        let raw = log.exitLoggedAt.timeIntervalSince(log.passTriggeredAt ?? log.infoShownAt)
        let w = DecisionTimingModel.decisionWindow(rawRepInterval: raw, activity: .twoMinuteTest, difficulty: difficulty)
        if w >= earlyBandMinWindow { return .early }
        if w >= idealBandMinWindow { return .ideal }
        return .late
    }

    static func evaluate(logs: [RepLog], difficulty: TestDifficulty) -> TwoMinuteBehaviorBadgeEvaluation {
        var earlyCount = 0
        var idealCount = 0
        var lateCount = 0
        for log in logs {
            switch timingCategory(for: log, difficulty: difficulty) {
            case .early: earlyCount += 1
            case .ideal: idealCount += 1
            case .late: lateCount += 1
            }
        }
        let total = logs.count
        let forwardThinkerUnlocked = total > 0 && Double(earlyCount + idealCount) / Double(total) >= 0.7
        /// “Largest category”: on-time count strictly greater than both early and late.
        let onTimeUnlocked = total > 0 && idealCount > earlyCount && idealCount > lateCount
        let reactiveTriggered = total > 0 && Double(lateCount) / Double(total) >= 0.5

        print("[BadgeLogic-Debug] earlyCount=\(earlyCount) idealCount=\(idealCount) lateCount=\(lateCount) total=\(total) forwardThinker=\(forwardThinkerUnlocked) onTime=\(onTimeUnlocked) reactive=\(reactiveTriggered)")

        return TwoMinuteBehaviorBadgeEvaluation(
            earlyCount: earlyCount,
            idealCount: idealCount,
            lateCount: lateCount,
            total: total,
            forwardThinkerUnlocked: forwardThinkerUnlocked,
            onTimeUnlocked: onTimeUnlocked,
            reactiveTriggered: reactiveTriggered
        )
    }

    // MARK: - Copy for results UI

    static func forwardThinkerTitle() -> String { "Forward Thinker" }
    static func forwardThinkerDescription() -> String { "Wins pocket moments early" }
    static func forwardThinkerWhy(evaluation: TwoMinuteBehaviorBadgeEvaluation) -> String {
        let n = evaluation.earlyCount + evaluation.idealCount
        let t = max(evaluation.total, 1)
        return "You’re deciding early in your pocket moments in \(n) of \(t) reps (early + on-time)."
    }

    static func onTimeTitle() -> String { "On Time" }
    static func onTimeDescription() -> String { "Meets the pocket, not ahead yet" }
    static func onTimeWhy(evaluation: TwoMinuteBehaviorBadgeEvaluation) -> String {
        let i = evaluation.idealCount
        let e = evaluation.earlyCount
        let l = evaluation.lateCount
        let t = max(evaluation.total, 1)
        return "On-time led: \(i) of \(t) reps (early \(e), late \(l)) — you’re meeting the pocket, not ahead of it yet."
    }

    static func reactiveTitle() -> String { "Reactive" }
    static func reactiveDescription() -> String { "Arrives after the pocket moment" }
    static func reactiveWhy(evaluation: TwoMinuteBehaviorBadgeEvaluation) -> String {
        let l = evaluation.lateCount
        let t = max(evaluation.total, 1)
        return "\(l) of \(t) reps — you’re arriving after the pocket moment."
    }

    static func mappingFootnote() -> String {
        "Timing groups use your decision window. Early ≈ picture clear early; on-time ≈ while the ball travels; late ≈ at or after the receive."
    }

    // MARK: - Coaching results screen (primary title + insights + next focus)

    /// Headline identity for the results header (timing-first).
    static func primaryProfileTitle(evaluation: TwoMinuteBehaviorBadgeEvaluation) -> String {
        if evaluation.forwardThinkerUnlocked { return forwardThinkerTitle() }
        if evaluation.onTimeUnlocked { return onTimeTitle() }
        if evaluation.reactiveTriggered { return reactiveTitle() }
        return "Mixed timing"
    }

    /// Subtitle under the primary title (includes counts).
    static func resultsHeaderSubtext(evaluation: TwoMinuteBehaviorBadgeEvaluation) -> String {
        let t = evaluation.total
        guard t > 0 else { return "No reps recorded for timing breakdown." }
        if evaluation.forwardThinkerUnlocked {
            return "You’re deciding early in your pocket moments — \(evaluation.earlyCount)/\(t) early reps."
        }
        if evaluation.onTimeUnlocked {
            return "You’re meeting the pocket: \(evaluation.idealCount)/\(t) reps on time."
        }
        if evaluation.reactiveTriggered {
            return "Late in the pocket: \(evaluation.lateCount)/\(t) reps."
        }
        return "Early \(evaluation.earlyCount), on-time \(evaluation.idealCount), late \(evaluation.lateCount) (of \(t))."
    }

    static func nextFocusBody(evaluation: TwoMinuteBehaviorBadgeEvaluation) -> String {
        if evaluation.reactiveTriggered {
            return "Train winning your pocket moment earlier — own the picture before the ball moves."
        }
        if evaluation.forwardThinkerUnlocked {
            return "Keep attacking your pocket moments early — add chaos next."
        }
        if evaluation.onTimeUnlocked {
            return "Train deciding before the pocket closes — get one beat ahead."
        }
        return "Train deciding before the pocket closes — commit one beat earlier."
    }

    /// At most two insight blocks for the coaching results screen.
    static func resultsInsightBlocks(evaluation: TwoMinuteBehaviorBadgeEvaluation) -> [(title: String, body: String)] {
        var blocks: [(String, String)] = []
        if evaluation.forwardThinkerUnlocked {
            blocks.append(("Forward Thinker", "You’re deciding early in your pocket moments."))
        } else if evaluation.onTimeUnlocked {
            blocks.append(("On Time", "You’re meeting the pocket, but not ahead of it yet."))
        } else if evaluation.reactiveTriggered {
            blocks.append(("Reactive tendency", "You’re arriving after the pocket moment on \(evaluation.lateCount) reps."))
        } else if evaluation.total > 0 {
            blocks.append(("Timing mix", "Your pocket moments are inconsistent — commit one beat earlier."))
        }
        let hasReactiveTitle = blocks.contains { $0.0 == "Reactive tendency" }
        if blocks.count < 2, evaluation.lateCount > 0, !hasReactiveTitle {
            blocks.append(("Reactive tendency", "You’re arriving after the pocket moment on \(evaluation.lateCount) reps."))
        }
        return Array(blocks.prefix(2))
    }
}
