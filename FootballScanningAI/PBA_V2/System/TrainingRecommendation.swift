//
//  TrainingRecommendation.swift
//  FootballScanningAI
//
//  PBA V2 — Automatic training recommendation by player level with overrides for timing, bias, consistency.
//

import Foundation

// MARK: - Player level (for default recommendation)

enum PlayerLevel: String {
    case starter = "Starter"
    case safePlayer = "Safe Player"
    case forwardThinker = "Forward Thinker"
    case playmaker = "Playmaker"
    case elite = "Elite Decision Maker"
}

// MARK: - Bias type (for override)

/// Bias detected from session data. Used to override recommendation (e.g. left/right → widen scan).
///
/// **Backward/safe bias:** We do not yet measure or store a "backward" or "safe" bias. When we do
/// (e.g. from Dribble or Pass: ratio of forward vs backward choices, or a dedicated metric),
/// add handling for `backwardSafe` in `recommendedActivity`, `focusLine`, and `recommend` to
/// recommend Dribble or Pass and focus "recognize forward options sooner". Until then, only
/// left/right bias is used in recommendation logic.
enum BiasType {
    case none
    case leftRight   // strong left/right → recommend Away From Pressure or One-Touch Passing
    case backwardSafe // Reserved: backward/safe → recommend Dribble or Pass (not yet measured; see doc above)
}

// MARK: - Decision speed (global; maps from SpeedBucket)

enum GlobalDecisionSpeed {
    case fast
    case medium
    case slow
}

// MARK: - Recommendation result

struct TrainingRecommendationResult {
    let activity: ActivityKind
    /// Focus line for the recommended activity (same logic as activity selection).
    let focusLine: String
    /// Coach tip generated from the same logic that selected the activity.
    let coachTip: String
    /// Optional short reason why this activity was chosen (e.g. "Timing was slow", "Building consistency at this level").
    let reason: String?
}

// MARK: - Training recommendation engine

enum TrainingRecommendation {
    /// Derive player level from progress and last 5 blocks.
    static func playerLevel(progressStore: ProgressStore, playerId: UUID?, last5: [SessionRecord], decisionScore: Int, consistency: ConsistencyLabel) -> PlayerLevel {
        let hasCompletedTest = progressStore.last(.twoMinuteTest, playerId: playerId) != nil
        guard hasCompletedTest else { return .starter }

        let readyAFP = progressStore.isReady(activity: .awayFromPressure, playerId: playerId)
        let readyDOP = progressStore.isReady(activity: .dribbleOrPass, playerId: playerId)
        let readyOTP = progressStore.isReady(activity: .oneTouchPassing, playerId: playerId)

        if readyOTP && decisionScore >= PBARecommendationConfig.eliteDecisionScore && consistency == .steady {
            return .elite
        }
        if readyOTP || (readyDOP && decisionScore >= PBARecommendationConfig.playmakerDecisionScore) {
            return .playmaker
        }
        if readyDOP || (readyAFP && last5.contains(where: { $0.activity == .dribbleOrPass })) {
            return .forwardThinker
        }
        if readyAFP || last5.contains(where: { $0.activity == .awayFromPressure }) {
            return .safePlayer
        }
        return .starter
    }

    /// Decision speed from last 5 (slow if any recent block is slow).
    static func decisionSpeed(from last5: [SessionRecord]) -> GlobalDecisionSpeed {
        guard let last = last5.first, let speed = last.speedBucket else { return .medium }
        if speed == .slow { return .slow }
        if speed == .fast { return .fast }
        return .medium
    }

    /// Bias type from last block's bias string. Only left/right is derived from current data; backward/safe is not yet measured.
    static func biasType(from last5: [SessionRecord]) -> BiasType? {
        guard let last = last5.first, let b = last.bias, !b.isEmpty, b != "None", b != "Balanced" else { return nil }
        let lower = b.lowercased()
        if lower == "left" || lower == "right" { return .leftRight }
        // Backward/safe not yet stored; when we have it, return .backwardSafe here and handle in recommendedActivity/focusLine/recommend.
        return .leftRight
    }

    /// Default activity for level (before overrides).
    static func defaultActivity(for level: PlayerLevel) -> ActivityKind {
        switch level {
        case .starter: return .awayFromPressure
        case .safePlayer, .forwardThinker: return .dribbleOrPass
        case .playmaker: return .oneTouchPassing
        case .elite: return .twoMinuteTest
        }
    }

    /// Recommended activity with overrides: 1) default by level, 2) slow override, 3) bias override, 4) consistency override.
    static func recommendedActivity(
        level: PlayerLevel,
        decisionSpeed: GlobalDecisionSpeed,
        bias: BiasType?,
        consistency: ConsistencyLabel
    ) -> ActivityKind {
        var activity = defaultActivity(for: level)

        if decisionSpeed == .slow {
            activity = .awayFromPressure
        }

        if let b = bias {
            switch b {
            case .none:
                break
            case .leftRight:
                if activity == .dribbleOrPass { activity = .awayFromPressure }
            case .backwardSafe:
                break // Not yet measured; no override until we have backward/safe data (e.g. from Dribble or Pass).
            }
        }

        if consistency == .streaky {
            activity = defaultActivity(for: level)
        }

        return activity
    }

    /// Short coaching focus line for the recommended activity.
    static func focusLine(activity: ActivityKind, decisionSpeed: GlobalDecisionSpeed, bias: BiasType?) -> String {
        if decisionSpeed == .slow {
            return "decide earlier before the ball arrives"
        }
        if bias == .leftRight {
            return "scan the whole field"
        }
        // backwardSafe not yet measured; when we have it, return "recognize forward options sooner" here.
        switch activity {
        case .awayFromPressure:
            return "read danger and decide away early"
        case .dribbleOrPass:
            return "decide pass or dribble before the ball arrives"
        case .oneTouchPassing:
            return "decide before the ball arrives"
        case .twoMinuteTest:
            return "establish your baseline decision speed"
        }
    }

    /// Whether the last AFP session shows first-touch decision issues (toward pressure, hesitant, or correcting).
    static func hasFirstTouchIssues(_ session: SessionResult?) -> Bool {
        guard let s = session else { return false }
        if (s.firstTouchTowardPressureCount ?? 0) >= 3 { return true }
        if (s.firstTouchHesitantCount ?? 0) >= 3 { return true }
        if let match = s.firstTouchMatchCount, match <= 6 { return true }
        if (s.lateAdjustments ?? 0) >= 3 { return true }
        return false
    }

    /// First-touch issue subtype for AFP (used to pick focus + coach tip).
    private static func firstTouchSubtype(_ session: SessionResult?) -> FirstTouchSubtype? {
        guard let s = session else { return nil }
        if (s.firstTouchTowardPressureCount ?? 0) >= 3 { return .towardPressure }
        if (s.firstTouchHesitantCount ?? 0) >= 3 { return .hesitant }
        if (s.firstTouchMatchCount != nil && s.firstTouchMatchCount! <= 6) || (s.lateAdjustments ?? 0) >= 3 { return .correcting }
        return nil
    }

    private enum FirstTouchSubtype {
        case towardPressure
        case hesitant
        case correcting
    }

    /// Focus and coach tip from the same logic that selected the activity.
    private static func focusAndCoachTip(
        activity: ActivityKind,
        reason: RecommendReason,
        lastAFPSessionResult: SessionResult?,
        speed: GlobalDecisionSpeed,
        bias: BiasType?
    ) -> (focus: String, coachTip: String) {
        switch activity {
        case .twoMinuteTest:
            return ("Establish your baseline decision speed.", "Take the 2-Minute Test before starting training.")
        case .awayFromPressure:
            if case .firstTouchIssues = reason, let subtype = firstTouchSubtype(lastAFPSessionResult) {
                switch subtype {
                case .towardPressure:
                    return ("Decide away from pressure earlier.", "You're turning into pressure too often.")
                case .hesitant:
                    return ("Commit to your decision.", "You're hesitating between options.")
                case .correcting:
                    return ("Decide earlier before the ball arrives.", "You're correcting after receiving—commit to the picture earlier.")
                }
            }
            if bias == .leftRight { return ("Scan the whole field.", "You're favoring one side.") }
            if speed == .slow { return ("Decide earlier before the ball arrives.", "Your decisions are arriving late.") }
            return ("Decide away from pressure earlier.", "Keep scanning and deciding away from pressure.")
        case .dribbleOrPass:
            return ("Decide pass or dribble before the ball arrives.", "You're hesitating between options.")
        case .oneTouchPassing:
            if speed == .slow { return ("Decide before the ball arrives.", "Your decisions are arriving late.") }
            return ("Decide before the ball arrives.", "Train deciding before the ball arrives.")
        }
    }

    private enum RecommendReason {
        case takeTest
        case slowTiming
        case noHistory
        case afpBuildAccuracy
        case afpDecideEarlier
        case afpNotReady
        case firstTouchIssues
        case progressToDOP
        case progressToOTP
        case benchmarkFromProgress
    }

    /// Full recommendation for Home: activity + focus + coachTip from the same logic.
    /// Pass lastAFPSessionResult to keep recommending Playing Away From Pressure when first-touch issues are present.
    /// Pass decisionConsistency; when speed is good but consistency is low, recommend repeating the same activity before advancing.
    static func recommend(
        progressStore: ProgressStore,
        playerId: UUID?,
        last5: [SessionRecord],
        hasCompletedInitialTest: Bool,
        lastAFPSessionResult: SessionResult? = nil,
        decisionConsistency: DecisionConsistencyLabel? = nil
    ) -> TrainingRecommendationResult {
        // Guest / merged account: baseline may be complete locally while no two_minute row exists for this playerId yet.
        if progressStore.last(.twoMinuteTest, playerId: playerId) == nil {
            if !hasCompletedInitialTest {
                return TrainingRecommendationResult(
                    activity: .twoMinuteTest,
                    focusLine: "Establish your baseline decision speed.",
                    coachTip: "Take the 2-Minute Test before starting training.",
                    reason: "Take the 2-Minute Test first."
                )
            }
        }

        let speed = decisionSpeed(from: last5)
        let bias = biasType(from: last5)
        let readyAFP = progressStore.isReady(activity: .awayFromPressure, playerId: playerId)
        let readyDOP = progressStore.isReady(activity: .dribbleOrPass, playerId: playerId)
        let lastAFP = progressStore.last(.awayFromPressure, playerId: playerId)
        let hasAnyTrainingHistory = !last5.isEmpty

        var activity: ActivityKind
        var reason: String?
        var recommendReason: RecommendReason = .progressToOTP

        // 1) If decision timing is slow across activities, prioritize One-Touch Passing to train faster decisions.
        if speed == .slow && hasAnyTrainingHistory {
            activity = .oneTouchPassing
            recommendReason = .slowTiming
            reason = "Timing was slow; train faster decisions."
        }
        // 2) No training history → recommend Playing Away From Pressure.
        else if !hasAnyTrainingHistory {
            activity = .awayFromPressure
            recommendReason = .noHistory
            reason = "Start with the first activity."
        }
        // 3) Weak in Playing Away From Pressure (low accuracy or slow) → keep recommending AFP.
        else if let last = lastAFP, (!readyAFP && (last.correct <= 8 || last.speedBucket == .slow)) {
            activity = .awayFromPressure
            recommendReason = last.correct <= 8 ? .afpBuildAccuracy : .afpDecideEarlier
            reason = last.correct <= 8 ? "Build accuracy." : "Decide earlier."
        }
        // 4) Not yet ready in AFP → stay on AFP.
        else if !readyAFP {
            activity = .awayFromPressure
            recommendReason = .afpNotReady
            reason = "Build consistent success in this activity."
        }
        // 5) Consistent success in AFP (~80% and strong blocks) → recommend Dribble or Pass.
        else if readyAFP && !readyDOP {
            activity = .dribbleOrPass
            recommendReason = .progressToDOP
            reason = "Progress to the next activity."
        }
        // 6) Performing well in Dribble or Pass → recommend One-Touch Passing.
        else {
            activity = .oneTouchPassing
            recommendReason = .progressToOTP
            reason = "Train decision speed under pressure."
        }

        if hasCompletedInitialTest && activity == .twoMinuteTest {
            activity = .awayFromPressure
            recommendReason = .benchmarkFromProgress
            reason = "Benchmark again from the Progress screen."
        }

        // If we would move on but last AFP had first-touch issues, keep recommending AFP.
        if (activity == .dribbleOrPass || activity == .oneTouchPassing) && hasFirstTouchIssues(lastAFPSessionResult) {
            activity = .awayFromPressure
            recommendReason = .firstTouchIssues
            reason = "Decision–action alignment needs work—keep training this activity."
        }

        // If decision speed is good (fast or medium) but within-session consistency is low, recommend repeating the same activity before advancing.
        let speedIsGood = (speed == .fast || speed == .medium)
        if speedIsGood, decisionConsistency == .low {
            if activity == .oneTouchPassing {
                activity = .dribbleOrPass
                reason = "Build more consistent decision speed before advancing."
            } else if activity == .dribbleOrPass {
                activity = .awayFromPressure
                reason = "Build more consistent decision speed before advancing."
            }
        }

        let (focus, coachTip) = focusAndCoachTip(activity: activity, reason: recommendReason, lastAFPSessionResult: lastAFPSessionResult, speed: speed, bias: bias)
        return TrainingRecommendationResult(activity: activity, focusLine: focus, coachTip: coachTip, reason: reason)
    }
}
