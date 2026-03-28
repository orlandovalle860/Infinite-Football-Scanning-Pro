//
//  GuidedCurriculumEngine.swift
//  FootballScanningAI
//
//  Guided progression for training path:
//  Stage 1 (AFP) -> Stage 2 (DOP) -> Stage 3 (OTP) -> loop back to Stage 1.
//

import Foundation

struct GuidedCurriculumProgress {
    let stage: Int          // 1...3
    let loop: Int           // 1...
    let nextActivity: ActivityKind
    let focus: String
}

enum GuidedCurriculumEngine {
    private static let minLoop = 1
    private static let maxLoop = 3
    private static let stageKeyPrefix = "guided_stage"
    private static let loopKeyPrefix = "guided_loop"
    private static let lastProcessedDateKeyPrefix = "guided_last_processed_date"
    private static let baselineCompletedKeyPrefix = "guided_baseline_completed"
    private static let recommendedActivityKeyPrefix = "guided_recommended_activity"

    static func evaluateAndAdvance(playerId: UUID?, sessions: [SessionResult]) -> GuidedCurriculumProgress {
        let pid = playerId?.uuidString ?? "global"
        let stageKey = "\(stageKeyPrefix)_\(pid)"
        let loopKey = "\(loopKeyPrefix)_\(pid)"
        let dateKey = "\(lastProcessedDateKeyPrefix)_\(pid)"
        let recommendedKey = "\(recommendedActivityKeyPrefix)_\(pid)"

        let defaults = UserDefaults.standard
        var stage = max(1, min(3, defaults.integer(forKey: stageKey) == 0 ? 1 : defaults.integer(forKey: stageKey)))
        var loop = max(minLoop, min(maxLoop, defaults.integer(forKey: loopKey) == 0 ? minLoop : defaults.integer(forKey: loopKey)))
        let lastProcessed = defaults.object(forKey: dateKey) as? Date

        // UserProfile stores newest-first; only training path activities are relevant.
        let trainingSessions = sessions.filter {
            [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType)
        }
        let newest = trainingSessions.first?.date

        #if DEBUG
        let stageBefore = stage
        let loopBefore = loop
        #endif
        var advancementReason = "not evaluated (no new training session)"
        var didAdvance = false

        // Advance at most one stage per newly completed session.
        if let newest, lastProcessed == nil || newest > lastProcessed! {
            let evaluation = thresholdEvaluation(for: stage, sessions: trainingSessions)
            advancementReason = evaluation.reason
            if evaluation.met {
                if stage == 3 {
                    // Stage 3 completion: move to next loop and pick next focus by weakest area.
                    loop = min(maxLoop, loop + 1)
                    stage = nextFocusStage(from: trainingSessions)
                } else {
                    stage += 1
                }
                didAdvance = true
            }
            defaults.set(newest, forKey: dateKey)
        }

        defaults.set(stage, forKey: stageKey)
        defaults.set(loop, forKey: loopKey)
        let recommended = activity(for: stage)
        defaults.set(recommended.rawValue, forKey: recommendedKey)

        #if DEBUG
        print("[PBA-Debug] Guided evaluate: selectedPlayerId=\(pid), stageBefore=\(stageBefore), stageAfter=\(stage), loopBefore=\(loopBefore), loopAfter=\(loop), didAdvance=\(didAdvance), reason=\(advancementReason)")
        #endif

        return GuidedCurriculumProgress(
            stage: stage,
            loop: loop,
            nextActivity: recommended,
            focus: focus(for: stage)
        )
    }

    /// Current stored progress without attempting advancement.
    static func currentProgress(playerId: UUID?) -> GuidedCurriculumProgress {
        let pid = playerId?.uuidString ?? "global"
        let stageKey = "\(stageKeyPrefix)_\(pid)"
        let loopKey = "\(loopKeyPrefix)_\(pid)"
        let recommendedKey = "\(recommendedActivityKeyPrefix)_\(pid)"
        let defaults = UserDefaults.standard
        let stage = max(1, min(3, defaults.integer(forKey: stageKey) == 0 ? 1 : defaults.integer(forKey: stageKey)))
        let loop = max(minLoop, min(maxLoop, defaults.integer(forKey: loopKey) == 0 ? minLoop : defaults.integer(forKey: loopKey)))
        let mapped = activity(for: stage)
        let stored = defaults.string(forKey: recommendedKey).flatMap { ActivityKind(rawValue: $0) }
        let recommended: ActivityKind
        if let stored, stored == mapped {
            recommended = stored
        } else {
            // Hard guard: recommendation must always mirror current stage.
            recommended = mapped
            defaults.set(mapped.rawValue, forKey: recommendedKey)
        }
        return GuidedCurriculumProgress(
            stage: stage,
            loop: loop,
            nextActivity: recommended,
            focus: focus(for: stage)
        )
    }

    static func hasCompletedBaseline(playerId: UUID?) -> Bool {
        let pid = playerId?.uuidString ?? "global"
        let key = "\(baselineCompletedKeyPrefix)_\(pid)"
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Assign an initial curriculum stage from baseline assessment metrics.
    /// This is used after a player's first 2-minute assessment.
    static func assignBaselineStage(playerId: UUID?, baseline: SessionResult) -> GuidedCurriculumProgress {
        let pid = playerId?.uuidString ?? "global"
        let stageKey = "\(stageKeyPrefix)_\(pid)"
        let loopKey = "\(loopKeyPrefix)_\(pid)"
        let dateKey = "\(lastProcessedDateKeyPrefix)_\(pid)"
        let baselineKey = "\(baselineCompletedKeyPrefix)_\(pid)"
        let recommendedKey = "\(recommendedActivityKeyPrefix)_\(pid)"

        // Curriculum is sequential for new players: always start at Stage 1 after baseline.
        let stage: Int = 1

        let defaults = UserDefaults.standard
        defaults.set(stage, forKey: stageKey)
        defaults.set(minLoop, forKey: loopKey)
        defaults.set(baseline.date, forKey: dateKey)
        defaults.set(true, forKey: baselineKey)
        defaults.set(activity(for: stage).rawValue, forKey: recommendedKey)

        return GuidedCurriculumProgress(
            stage: stage,
            loop: minLoop,
            nextActivity: activity(for: stage),
            focus: focus(for: stage)
        )
    }

    static func resetCurriculumForPlayer(playerId: UUID?, baselineCompleted: Bool = false) -> GuidedCurriculumProgress {
        let pid = playerId?.uuidString ?? "global"
        let stageKey = "\(stageKeyPrefix)_\(pid)"
        let loopKey = "\(loopKeyPrefix)_\(pid)"
        let dateKey = "\(lastProcessedDateKeyPrefix)_\(pid)"
        let baselineKey = "\(baselineCompletedKeyPrefix)_\(pid)"
        let recommendedKey = "\(recommendedActivityKeyPrefix)_\(pid)"
        let defaults = UserDefaults.standard

        #if DEBUG
        let stageBefore = defaults.integer(forKey: stageKey)
        print("[PBA-Debug] Curriculum reset start: selectedPlayerId=\(pid), storedStageBefore=\(stageBefore)")
        #endif

        defaults.removeObject(forKey: stageKey)
        defaults.removeObject(forKey: loopKey)
        defaults.removeObject(forKey: dateKey)
        defaults.removeObject(forKey: recommendedKey)
        defaults.removeObject(forKey: baselineKey)

        let stage = 1
        let loop = minLoop
        let recommended = activity(for: stage)
        defaults.set(stage, forKey: stageKey)
        defaults.set(loop, forKey: loopKey)
        defaults.set(recommended.rawValue, forKey: recommendedKey)
        defaults.set(baselineCompleted, forKey: baselineKey)

        #if DEBUG
        let stageAfter = defaults.integer(forKey: stageKey)
        print("[PBA-Debug] Curriculum reset end: selectedPlayerId=\(pid), storedStageAfter=\(stageAfter), baselineCompleted=\(baselineCompleted), recommended=\(recommended.rawValue)")
        #endif

        return GuidedCurriculumProgress(
            stage: stage,
            loop: loop,
            nextActivity: recommended,
            focus: focus(for: stage)
        )
    }

#if DEBUG
    static func debugState(playerId: UUID?) -> String {
        let pid = playerId?.uuidString ?? "global"
        let defaults = UserDefaults.standard

        let stageKey = "\(stageKeyPrefix)_\(pid)"
        let loopKey = "\(loopKeyPrefix)_\(pid)"
        let baselineKey = "\(baselineCompletedKeyPrefix)_\(pid)"
        let recommendedKey = "\(recommendedActivityKeyPrefix)_\(pid)"
        let dateKey = "\(lastProcessedDateKeyPrefix)_\(pid)"

        let stage = defaults.integer(forKey: stageKey)
        let loop = defaults.integer(forKey: loopKey)
        let baseline = defaults.bool(forKey: baselineKey)
        let recommended = defaults.string(forKey: recommendedKey) ?? "nil"
        let lastDate = (defaults.object(forKey: dateKey) as? Date)?.description ?? "nil"

        let globalStage = defaults.integer(forKey: "\(stageKeyPrefix)_global")
        let globalRecommended = defaults.string(forKey: "\(recommendedActivityKeyPrefix)_global") ?? "nil"

        return "pid=\(pid), stage=\(stage), loop=\(loop), baseline=\(baseline), recommended=\(recommended), lastProcessed=\(lastDate), globalStage=\(globalStage), globalRecommended=\(globalRecommended)"
    }
#endif

    private static func activity(for stage: Int) -> ActivityKind {
        switch stage {
        case 1: return .awayFromPressure
        case 2: return .dribbleOrPass
        default: return .oneTouchPassing
        }
    }

    private static func focus(for stage: Int) -> String {
        switch stage {
        case 1: return "Decide away from pressure quickly — first decision counts."
        case 2: return "Choose the right action early and play forward when available."
        default: return "Decide before the ball arrives and execute one-touch choices."
        }
    }

    private static func meetsThresholds(for stage: Int, sessions: [SessionResult]) -> Bool {
        thresholdEvaluation(for: stage, sessions: sessions).met
    }

    private static func thresholdEvaluation(for stage: Int, sessions: [SessionResult]) -> (met: Bool, reason: String) {
        let activity = activity(for: stage)
        let recent = sessions.filter { $0.activityType == activity }.prefix(3)
        let recentArray = Array(recent)
        let recentPlayerIds = recentArray.map { $0.playerID.uuidString }.joined(separator: ",")

        guard recentArray.count >= 2 else {
            return (false, "insufficient sessions for \(activity.rawValue): count=\(recentArray.count), need>=2, playerIds=[\(recentPlayerIds)]")
        } // evaluate last 2–3 sessions

        let accuracyAvg = recentArray.reduce(0.0) { partial, s in
            guard s.totalReps > 0 else { return partial }
            return partial + (Double(s.correctCount) / Double(s.totalReps))
        } / Double(recentArray.count)

        let timeValues = recentArray.compactMap(\.avgDecisionTime)
        guard !timeValues.isEmpty else {
            return (false, "missing avgDecisionTime for \(activity.rawValue) recent sessions, playerIds=[\(recentPlayerIds)]")
        }
        let avgTime = timeValues.reduce(0, +) / Double(timeValues.count)

        switch stage {
        case 1:
            // Stage 1 -> Stage 2
            let met = accuracyAvg >= 0.70 && avgTime <= 1.25
            return (met, "stage1 gate: activity=\(activity.rawValue), afpCount=\(recentArray.count), playerIds=[\(recentPlayerIds)], accuracyAvg=\(String(format: "%.3f", accuracyAvg)), avgTime=\(String(format: "%.3f", avgTime)), met=\(met)")
        case 2:
            // Stage 2 -> Stage 3 (+ forward intent gate)
            let forwardValues: [Double] = recentArray.compactMap { s in
                guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
                return Double(choice) / Double(opp)
            }
            guard !forwardValues.isEmpty else {
                return (false, "stage2 gate: no forward intent opportunities in recent sessions, playerIds=[\(recentPlayerIds)]")
            }
            let avgForwardIntent = forwardValues.reduce(0, +) / Double(forwardValues.count)
            let met = accuracyAvg >= 0.70 && avgTime <= 1.10 && avgForwardIntent >= 0.40
            return (met, "stage2 gate: activity=\(activity.rawValue), count=\(recentArray.count), playerIds=[\(recentPlayerIds)], accuracyAvg=\(String(format: "%.3f", accuracyAvg)), avgTime=\(String(format: "%.3f", avgTime)), avgForward=\(String(format: "%.3f", avgForwardIntent)), met=\(met)")
        default:
            // Stage 3 -> next loop Stage 1
            let met = accuracyAvg >= 0.75 && avgTime <= 0.95
            return (met, "stage3 gate: activity=\(activity.rawValue), count=\(recentArray.count), playerIds=[\(recentPlayerIds)], accuracyAvg=\(String(format: "%.3f", accuracyAvg)), avgTime=\(String(format: "%.3f", avgTime)), met=\(met)")
        }
    }

    /// After completing Stage 3, set the next focus to the weakest current area.
    /// Mapping:
    /// - Decision speed weakness -> Stage 1 (AFP)
    /// - Forward thinking weakness -> Stage 2 (DOP)
    /// - Advanced speed/execution weakness -> Stage 3 (OTP)
    private static func nextFocusStage(from sessions: [SessionResult]) -> Int {
        let training = sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        let recent = Array(training.prefix(5))
        guard !recent.isEmpty else { return 1 }

        let decisionTimes = recent.compactMap(\.avgDecisionTime)
        let avgDecisionTime = decisionTimes.isEmpty ? 1.15 : (decisionTimes.reduce(0, +) / Double(decisionTimes.count))

        let forwardValues: [Double] = recent.compactMap { s in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            return Double(choice) / Double(opp)
        }
        let avgForward = forwardValues.isEmpty ? 0.60 : (forwardValues.reduce(0, +) / Double(forwardValues.count))

        let otpRecent = Array(recent.filter { $0.activityType == .oneTouchPassing }.prefix(3))
        let otpAccuracyValues: [Double] = otpRecent.compactMap { s in
            guard s.totalReps > 0 else { return nil }
            return Double(s.correctCount) / Double(s.totalReps)
        }
        let otpDecisionValues = otpRecent.compactMap(\.avgDecisionTime)
        let otpAccuracy = otpAccuracyValues.isEmpty ? 1.0 : (otpAccuracyValues.reduce(0, +) / Double(otpAccuracyValues.count))
        let otpAvgTime = otpDecisionValues.isEmpty ? 0.95 : (otpDecisionValues.reduce(0, +) / Double(otpDecisionValues.count))

        // Higher = weaker. Tuned to keep recommendations understandable and stable.
        let decisionWeakness = max(0.0, (avgDecisionTime - 0.95) / 0.55)
        let forwardWeakness = max(0.0, (0.60 - avgForward) / 0.60)
        let advancedWeakness = max(0.0, ((otpAvgTime - 0.95) / 0.45)) + max(0.0, ((0.80 - otpAccuracy) / 0.80))

        if forwardWeakness >= decisionWeakness && forwardWeakness >= advancedWeakness {
            return 2
        }
        if advancedWeakness >= decisionWeakness && advancedWeakness >= forwardWeakness {
            return 3
        }
        return 1
    }
}

