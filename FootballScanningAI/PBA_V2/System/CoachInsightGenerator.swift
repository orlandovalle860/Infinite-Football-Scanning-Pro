//
//  CoachInsightGenerator.swift
//  FootballScanningAI
//
//  PBA V2 — Rule-based coach insight for session summary (2 sentences max).
//

import Foundation

enum CoachInsightGenerator {
    enum PlayerState: String {
        case lateCorrect = "LATE_CORRECT"
        case fastIncorrect = "FAST_INCORRECT"
        case lateIncorrect = "LATE_INCORRECT"
        case sharp = "SHARP"
        case inconsistent = "INCONSISTENT"
    }

    enum StateModifier: String, Hashable {
        case improving = "IMPROVING"
        case declining = "DECLINING"
        case inconsistent = "INCONSISTENT"
    }

    private enum CoachingTheme {
        // Away From Pressure
        case afpEscapeEarly
        case afpCommitOpposite
        case afpCalmExecution
        // Dribble Or Pass
        case dopPickForwardCue
        case dopOwnSafeOption
        case dopCleanSelection
        // One Touch Passing
        case otpPreDecide
        case otpTempoAndQuality
        case otpBodyShape
        // Two-minute / generic
        case testScanEarly
        case testComposure
        case genericConsistency
    }

    struct InsightPackage {
        let playerState: PlayerState
        let modifiers: Set<StateModifier>
        let theme: String
        let headline: String
        let fieldMeaning: String
        let nextStep: String
        let supportingDetail: String
    }

    struct NextStepPackage {
        let playerState: PlayerState
        let modifiers: Set<StateModifier>
        let instruction: String
    }

    private struct ThemeLines {
        let anchor: String
        let supporting: [String]
    }

    static func coachInsight(for session: SessionResult, previous: SessionRecord? = nil) -> String {
        let package = insightPackage(for: session, previous: previous)
        return joinTwoCoachSentences(package.fieldMeaning, package.nextStep)
    }

    /// Joins two insight lines; drops empty second clause cleanly.
    private static func joinTwoCoachSentences(_ fieldMeaning: String, _ nextStep: String) -> String {
        let a = fieldMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return "\(a) \(b)"
    }

    /// Two coach lines from the same theme, **never the same sentence twice** when another line exists in the theme pool.
    private static func distinctFieldAndNext(for theme: CoachingTheme, session: SessionResult) -> (String, String) {
        let first = phrase(for: theme, session: session, salt: 0)
        let second = phrase(for: theme, session: session, salt: 1)
        let f = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if f.caseInsensitiveCompare(s) != .orderedSame {
            return (first, second)
        }
        let alt = alternateSecondPhrase(for: theme, session: session, excluding: f)
        return (first, alt)
    }

    /// First phrase in theme (anchor + supporting) that is not the same as `excluding` (case-insensitive).
    private static func alternateSecondPhrase(for theme: CoachingTheme, session: SessionResult, excluding: String) -> String {
        let lines = themeLines(for: theme, session: session)
        let ex = excluding.trimmingCharacters(in: .whitespacesAndNewlines)
        for raw in [lines.anchor] + lines.supporting {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.caseInsensitiveCompare(ex) != .orderedSame { return t }
        }
        // Rotate through supporting lines if anchor-only or all matched excluding
        guard !lines.supporting.isEmpty else { return "" }
        let n = lines.supporting.count
        let start = variationIndex(session: session, salt: 2, count: n)
        for offset in 0..<n {
            let idx = (start + offset) % n
            let t = lines.supporting[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if t.caseInsensitiveCompare(ex) != .orderedSame { return lines.supporting[idx] }
        }
        return ""
    }

    static func insightPackage(for session: SessionResult, previous: SessionRecord? = nil) -> InsightPackage {
        let state = playerState(for: session)
        let modifiers = modifiers(for: session, previous: previous)
        let theme = primaryTheme(for: session, state: state, modifiers: modifiers)
        let (fieldMeaning, nextStep) = distinctFieldAndNext(for: theme, session: session)
        let detail = supportingDetail(for: session, previous: previous)
        return InsightPackage(
            playerState: state,
            modifiers: modifiers,
            theme: String(describing: theme),
            headline: headline(for: state, modifiers: modifiers),
            fieldMeaning: fieldMeaning,
            nextStep: nextStep,
            supportingDetail: detail
        )
    }

    static func nextStepPackage(for session: SessionResult, previous: SessionRecord? = nil) -> NextStepPackage {
        let state = playerState(for: session)
        let modifiers = modifiers(for: session, previous: previous)
        return NextStepPackage(
            playerState: state,
            modifiers: modifiers,
            instruction: nextStepLine(for: session, state: state, modifiers: modifiers)
        )
    }

    static func nextStepPackage(forTwoMinute result: TwoMinuteTestResult, previous: SessionRecord?) -> NextStepPackage {
        let synthetic = SessionResult(
            playerID: previous?.playerId ?? UUID(),
            activityType: .twoMinuteTest,
            correctCount: result.correctCount,
            totalReps: result.totalReps,
            speedCounts: SessionSpeedCounts(fast: result.fastCount, medium: result.mediumCount, slow: result.slowCount),
            avgDecisionTime: result.avgDecisionTime,
            biasDirection: result.biasDirection,
            directionCounts: result.directionCounts,
            difficulty: result.difficulty
        )
        let state = playerState(for: synthetic)
        let modifiers = modifiers(for: synthetic, previous: previous)
        return NextStepPackage(
            playerState: state,
            modifiers: modifiers,
            instruction: nextStepLine(for: synthetic, state: state, modifiers: modifiers)
        )
    }

    static func insightPackage(
        forTwoMinute result: TwoMinuteTestResult,
        previous: SessionRecord?
    ) -> InsightPackage {
        let total = max(result.totalReps, 1)
        let accuracy = Double(result.correctCount) / Double(total)
        let window = result.avgDecisionWindowSeconds ?? -0.9
        let state: PlayerState = {
            if accuracy >= 0.80 && window >= 0.51 { return .sharp }
            if accuracy >= 0.75 && window < 0.51 { return .lateCorrect }
            if accuracy < 0.70 && window >= 0.48 { return .fastIncorrect }
            return .lateIncorrect
        }()

        var modifiers = Set<StateModifier>()
        if result.totalReps > 0 {
            let maxBucket = max(result.fastCount, max(result.mediumCount, result.slowCount))
            let minBucket = min(result.fastCount, min(result.mediumCount, result.slowCount))
            if maxBucket - minBucket >= max(3, Int(Double(result.totalReps) * 0.25)) {
                modifiers.insert(.inconsistent)
            }
        }
        if let prev = previous {
            let prevTotal = max(prev.decisionsCompleted, 1)
            let prevAcc = Double(prev.correct) / Double(prevTotal)
            if accuracy - prevAcc >= 0.08 { modifiers.insert(.improving) }
            if prevAcc - accuracy >= 0.08 { modifiers.insert(.declining) }
            if let prevWindow = prev.avgDecisionWindowSeconds {
                if window - prevWindow >= 0.08 { modifiers.insert(.improving) }
                if prevWindow - window >= 0.08 { modifiers.insert(.declining) }
            }
        }

        let synthetic = SessionResult(
            playerID: previous?.playerId ?? UUID(),
            activityType: .twoMinuteTest,
            correctCount: result.correctCount,
            totalReps: result.totalReps,
            speedCounts: SessionSpeedCounts(fast: result.fastCount, medium: result.mediumCount, slow: result.slowCount),
            avgDecisionTime: result.avgDecisionTime,
            biasDirection: result.biasDirection,
            directionCounts: result.directionCounts,
            difficulty: result.difficulty
        )
        let theme: CoachingTheme = modifiers.contains(.inconsistent) ? .testComposure : .testScanEarly
        let (fieldMeaning, nextStep) = distinctFieldAndNext(for: theme, session: synthetic)
        return InsightPackage(
            playerState: state,
            modifiers: modifiers,
            theme: String(describing: theme),
            headline: headline(for: state, modifiers: modifiers),
            fieldMeaning: fieldMeaning,
            nextStep: nextStep,
            supportingDetail: supportingDetail(for: synthetic, previous: previous)
        )
    }

    private static func playerState(for session: SessionResult) -> PlayerState {
        let total = max(session.totalReps, 1)
        let accuracy = Double(session.correctCount) / Double(total)
        let slowRate = Double(session.speedCounts.slow) / Double(total)
        let window = session.avgDecisionWindowSeconds ?? -0.9
        if isInconsistent(session: session, previous: nil) { return .inconsistent }
        if accuracy >= 0.80 && window >= 0.51 { return .sharp }
        if accuracy >= 0.75 && (window < 0.51 || slowRate >= 0.35) { return .lateCorrect }
        if accuracy < 0.70 && window >= 0.48 { return .fastIncorrect }
        return .lateIncorrect
    }

    private static func modifiers(for session: SessionResult, previous: SessionRecord?) -> Set<StateModifier> {
        var result = Set<StateModifier>()
        if isInconsistent(session: session, previous: previous) {
            result.insert(.inconsistent)
        }
        let total = max(session.totalReps, 1)
        let fastRate = Double(session.speedCounts.fast) / Double(total)
        let slowRate = Double(session.speedCounts.slow) / Double(total)
        if abs(fastRate - slowRate) <= 0.10 {
            result.insert(.inconsistent)
        }
        guard let previous else { return result }

        let prevTotal = max(previous.decisionsCompleted, 1)
        let currAcc = Double(session.correctCount) / Double(total)
        let prevAcc = Double(previous.correct) / Double(prevTotal)
        if currAcc - prevAcc >= 0.08 { result.insert(.improving) }
        if prevAcc - currAcc >= 0.08 { result.insert(.declining) }

        if let currWindow = session.avgDecisionWindowSeconds, let prevWindow = previous.avgDecisionWindowSeconds {
            if currWindow - prevWindow >= 0.08 { result.insert(.improving) }
            if prevWindow - currWindow >= 0.08 { result.insert(.declining) }
        }
        return result
    }

    private static func isInconsistent(session: SessionResult, previous: SessionRecord?) -> Bool {
        if (session.decisionTimeStdDev ?? 0) >= 0.45 { return true }
        let total = max(session.totalReps, 1)
        let maxBucket = max(session.speedCounts.fast, max(session.speedCounts.medium, session.speedCounts.slow))
        let minBucket = min(session.speedCounts.fast, min(session.speedCounts.medium, session.speedCounts.slow))
        if maxBucket - minBucket >= max(3, Int(Double(total) * 0.25)) { return true }
        let fastRate = Double(session.speedCounts.fast) / Double(total)
        let slowRate = Double(session.speedCounts.slow) / Double(total)
        if abs(fastRate - slowRate) <= 0.10 { return true }
        if let previous, let currWindow = session.avgDecisionWindowSeconds, let prevWindow = previous.avgDecisionWindowSeconds {
            if abs(currWindow - prevWindow) >= 0.16 { return true }
        }
        return false
    }

    private static func nextStepLine(for session: SessionResult, state: PlayerState, modifiers: Set<StateModifier>) -> String {
        let activity = session.activityType
        let whatWhenHowPool: [String] = {
            switch (activity, state) {
            case (.awayFromPressure, .lateCorrect):
                return [
                    "Open your hips away from pressure when the red cue appears, then show your first decision opposite the red on your first touch.",
                    "Show away-from-pressure body shape before the pass arrives, then commit opposite without a recovery touch.",
                    "Set your away-from-pressure direction early when pressure is shown, then drive opposite as the ball travels."
                ]
            case (.awayFromPressure, .fastIncorrect):
                return [
                    "Read the pressure side first when the cue flashes, then explode only toward the opposite direction.",
                    "Lock the opposite direction before contact when pressure appears, then accelerate in that lane.",
                    "Pick the away-from-pressure direction during your scan, then use your first action to protect the ball into space."
                ]
            case (.awayFromPressure, .lateIncorrect):
                return [
                    "Scan for pressure as the pass is released, then choose the opposite lane before your first touch.",
                    "Find the pressure shoulder early when the cue appears, then turn out away from it immediately.",
                    "Identify the safe direction before expected arrival, then play away from pressure on first contact."
                ]
            case (.awayFromPressure, .sharp):
                return [
                    "Keep scanning pressure before each pass, then explode opposite on touch one every rep.",
                    "Maintain early away-from-pressure pictures as the ball travels, then execute the opposite first decision cleanly.",
                    "Repeat your early pressure read each rep, then finish with a decisive opposite first action."
                ]
            case (.awayFromPressure, .inconsistent):
                return [
                    "Use one consistent away-from-pressure scan before each pass, then commit opposite on first action.",
                    "Reset to the same pressure-read routine every rep, then decide opposite without hesitation.",
                    "Stabilize your process when cues appear, then make one clean opposite first decision on touch one."
                ]
            case (.dribbleOrPass, .lateCorrect):
                return [
                    "Spot the defender and support line before expected arrival, then choose dribble or pass on first contact.",
                    "Read the pressure picture during ball travel, then commit to the clear option without extra touches.",
                    "Identify the best option early when the cue appears, then execute it immediately on reception."
                ]
            case (.dribbleOrPass, .fastIncorrect):
                return [
                    "Read the situation first when pressure sets, then use your speed only after the right option is clear.",
                    "Confirm defender distance before contact, then choose the correct dribble-or-pass action at tempo.",
                    "Take one early picture as the pass travels, then commit to the right action instead of the fastest action."
                ]
            case (.dribbleOrPass, .lateIncorrect):
                return [
                    "Scan support and pressure before reception, then lock your dribble-or-pass choice before touch one.",
                    "Set your decision during ball travel, then execute immediately instead of deciding after control.",
                    "Find the best lane early when cues appear, then commit to that option on first contact."
                ]
            case (.dribbleOrPass, .sharp):
                return [
                    "Keep reading the situation before expected arrival, then execute the right option instantly under pressure.",
                    "Maintain your early cue recognition every rep, then commit to the correct action with one touch.",
                    "Repeat your pre-receive scan pattern, then pick the right dribble-or-pass choice at match tempo."
                ]
            case (.dribbleOrPass, .inconsistent):
                return [
                    "Use the same situation scan each rep before contact, then commit to one clear option immediately.",
                    "Stabilize your read of pressure and support when the cue appears, then execute one decisive action.",
                    "Repeat one pre-arrival check every rep, then choose dribble or pass with no late switch."
                ]
            case (.oneTouchPassing, .lateCorrect):
                return [
                    "Picture your next pass before expected arrival, then play one-touch to the chosen target immediately.",
                    "Set your body and target during ball travel, then release one-touch without a decision delay.",
                    "Read the next action early before contact, then let your first touch be the pass."
                ]
            case (.oneTouchPassing, .fastIncorrect):
                return [
                    "Choose the target before expected arrival, then keep one-touch tempo only on the correct option.",
                    "Confirm the right one-touch lane during your scan, then pass first-time with quality.",
                    "Set your passing picture before contact, then play one-touch only to the best target."
                ]
            case (.oneTouchPassing, .lateIncorrect):
                return [
                    "Decide your one-touch target as the pass travels, then release before a second thought appears.",
                    "Pre-shape to the right lane before reception, then play the first-time pass on touch one.",
                    "Take your final scan before expected arrival, then execute one-touch to the planned target."
                ]
            case (.oneTouchPassing, .sharp):
                return [
                    "Keep pre-arrival scanning every rep, then maintain one-touch quality at the same tempo.",
                    "Hold your early decision habit before reception, then deliver the one-touch pass cleanly.",
                    "Repeat early target selection each rep, then execute one-touch without breaking rhythm."
                ]
            case (.oneTouchPassing, .inconsistent):
                return [
                    "Use one pre-arrival scan routine before every pass, then commit to one-touch without hesitation.",
                    "Stabilize your pre-receive timing each rep, then release one-touch to the chosen target.",
                    "Keep the same early target check each ball, then execute one-touch with consistent rhythm."
                ]
            case (.twoMinuteTest, .lateCorrect):
                return [
                    "Scan both shoulders before each trigger, then lock your decision before ball arrival.",
                    "Build the picture early when each rep starts, then commit before the ball reaches you.",
                    "Read the cue in the scan phase each rep, then execute the decision on first contact."
                ]
            case (.twoMinuteTest, .fastIncorrect):
                return [
                    "Confirm the correct cue before each rep, then attack at speed only after that picture is clear.",
                    "Take one extra pre-arrival check each trigger, then commit fast to the right option.",
                    "Prioritize selection in your early scan, then let tempo follow the correct choice."
                ]
            case (.twoMinuteTest, .lateIncorrect):
                return [
                    "Set your decision while the ball is traveling each rep, then execute before expected arrival.",
                    "Scan earlier when each trigger starts, then commit before pressure closes your window.",
                    "Lock the action in your last pre-arrival look, then execute immediately on contact."
                ]
            case (.twoMinuteTest, .sharp):
                return [
                    "Keep your early scan routine on every rep, then execute before expected arrival with the same quality.",
                    "Repeat your pre-arrival decision habit each trigger, then maintain clean execution at speed.",
                    "Hold your balanced process each rep, then finish with early, correct decisions."
                ]
            case (.twoMinuteTest, .inconsistent):
                return [
                    "Use the same pre-arrival scan checklist every rep, then commit to one clear decision.",
                    "Stabilize your decision routine when each trigger appears, then execute before expected arrival.",
                    "Keep one repeatable early-read process each rep, then finish with a single committed action."
                ]
            }
        }()

        let idx = variationIndex(session: session, salt: 1401 + stateSalt(state), count: whatWhenHowPool.count)
        let base = whatWhenHowPool[idx]
        if shouldUseNextStepAnchor(session: session, state: state, modifiers: modifiers) {
            let anchors = [
                "Speed of play is speed of thought.",
                "The window closes before expected arrival.",
                "Your last look should confirm, not decide."
            ]
            let aidx = variationIndex(session: session, salt: 1459 + stateSalt(state), count: anchors.count)
            return "\(anchors[aidx]) \(base)"
        }
        return base
    }

    private static func shouldUseNextStepAnchor(session: SessionResult, state: PlayerState, modifiers: Set<StateModifier>) -> Bool {
        let threshold = modifiers.contains(.inconsistent) ? 40 : 35
        let roll = variationIndex(session: session, salt: 1511 + stateSalt(state), count: 100)
        return roll < threshold
    }

    private static func stateSalt(_ state: PlayerState) -> Int {
        switch state {
        case .lateCorrect: return 7
        case .fastIncorrect: return 13
        case .lateIncorrect: return 19
        case .sharp: return 29
        case .inconsistent: return 37
        }
    }

    private static func primaryTheme(for session: SessionResult, state: PlayerState, modifiers: Set<StateModifier>) -> CoachingTheme {
        if modifiers.contains(.inconsistent) {
            return session.activityType == .twoMinuteTest ? .testComposure : .genericConsistency
        }

        switch session.activityType {
        case .awayFromPressure:
            if let toward = session.firstTouchTowardPressureCount, toward >= 3 { return .afpEscapeEarly }
            if let hesitant = session.firstTouchHesitantCount, hesitant >= 3 { return .afpCommitOpposite }
            return state == .sharp ? .afpCalmExecution : .afpEscapeEarly
        case .dribbleOrPass:
            if let forward = session.forwardChoiceCount, let opp = session.forwardOpportunityCount, opp >= 4 {
                let rate = Double(forward) / Double(max(opp, 1))
                if rate < 0.35 { return .dopPickForwardCue }
                if rate > 0.85 { return .dopOwnSafeOption }
            }
            return state == .fastIncorrect ? .dopCleanSelection : .dopPickForwardCue
        case .oneTouchPassing:
            if (session.firstTouchMatchCount ?? 12) <= 7 || (session.lateAdjustments ?? 0) >= 3 { return .otpBodyShape }
            return state == .sharp ? .otpTempoAndQuality : .otpPreDecide
        case .twoMinuteTest:
            return state == .sharp ? .testScanEarly : .testComposure
        }
    }

    private static func phrase(for theme: CoachingTheme, session: SessionResult, salt: Int) -> String {
        let lines = themeLines(for: theme, session: session)
        let useAnchor = shouldUseAnchor(theme: theme, session: session, salt: salt)
        if useAnchor {
            return lines.anchor
        }
        guard !lines.supporting.isEmpty else { return lines.anchor }
        let idx = variationIndex(session: session, salt: salt, count: lines.supporting.count)
        return lines.supporting[idx]
    }

    /// Deterministic per-session rotation: different sessions naturally pick different variants,
    /// while the same session stays stable across re-renders.
    private static func variationIndex(session: SessionResult, salt: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var hasher = Hasher()
        hasher.combine(session.id)
        hasher.combine(session.activityType.rawValue)
        hasher.combine(session.correctCount)
        hasher.combine(session.totalReps)
        hasher.combine(session.speedCounts.fast)
        hasher.combine(session.speedCounts.medium)
        hasher.combine(session.speedCounts.slow)
        hasher.combine(Int((session.avgDecisionTime ?? 0) * 1000))
        hasher.combine(Int((session.date.timeIntervalSince1970).rounded()))
        hasher.combine(salt)
        return abs(hasher.finalize()) % count
    }

    /// Anchor lines appear around 35% of the time to keep a consistent coach voice without repetition.
    private static func shouldUseAnchor(theme: CoachingTheme, session: SessionResult, salt: Int) -> Bool {
        let roll = variationIndex(session: session, salt: 900 + salt + themeSalt(theme), count: 100)
        return roll < 35
    }

    private static func themeSalt(_ theme: CoachingTheme) -> Int {
        switch theme {
        case .afpEscapeEarly: return 11
        case .afpCommitOpposite: return 23
        case .afpCalmExecution: return 31
        case .dopPickForwardCue: return 37
        case .dopOwnSafeOption: return 41
        case .dopCleanSelection: return 47
        case .otpPreDecide: return 53
        case .otpTempoAndQuality: return 59
        case .otpBodyShape: return 67
        case .testScanEarly: return 73
        case .testComposure: return 79
        case .genericConsistency: return 83
        }
    }

    private static func themeLines(for theme: CoachingTheme, session: SessionResult) -> ThemeLines {
        switch theme {
        case .afpEscapeEarly:
            return ThemeLines(
                anchor: "The window of opportunity closes before expected arrival.",
                supporting: [
                    "In AFP, read pressure early and decide opposite before the lane closes.",
                    "Turn away from pressure sooner so your first action creates space.",
                    "See the red cue early and commit opposite without a second touch.",
                    "Scan early, then commit to the opposite direction with conviction."
                ]
            )
        case .afpCommitOpposite:
            return ThemeLines(
                anchor: "Decide before expected arrival.",
                supporting: [
                    "Your first look should confirm, not decide.",
                    "Commit to the opposite direction on first action, not after contact.",
                    "Lose the hesitation and own the opposite direction immediately.",
                    "One clear picture, one committed first move."
                ]
            )
        case .afpCalmExecution:
            return ThemeLines(
                anchor: "Speed of play is speed of thought.",
                supporting: [
                    "You are reading pressure well; keep that calm first touch opposite.",
                    "Stay composed and let your first action match the early picture.",
                    "Good away-from-pressure habits — repeat the same calm execution each rep."
                ]
            )
        case .dopPickForwardCue:
            return ThemeLines(
                anchor: "Your last look should confirm, not decide.",
                supporting: [
                    "In DOP, identify the forward cue earlier and commit if it is on.",
                    "Scan before contact so the dribble/pass choice is clear already.",
                    "When forward is open, take it early; when not, own the safe option quickly.",
                    "Beat pressure by choosing one action early, not late."
                ]
            )
        case .dopOwnSafeOption:
            return ThemeLines(
                anchor: "The window closes before the ball gets to you.",
                supporting: [
                    "Do not force forward if it is not on - safe early is still smart football.",
                    "Select the safe option quicker when the forward lane is closed.",
                    "Protect the ball with earlier safe decisions, then play again.",
                    "Stay efficient: safe choice early beats forced choice late."
                ]
            )
        case .dopCleanSelection:
            return ThemeLines(
                anchor: "Speed of play is speed of thought.",
                supporting: [
                    "You are quick; now clean up selection so speed creates outcomes.",
                    "Fast decisions only count when the option is correct.",
                    "Keep the tempo, improve the choice quality under pressure.",
                    "Read one cue early, then commit to the right action."
                ]
            )
        case .otpPreDecide:
            return ThemeLines(
                anchor: "Decide before expected arrival.",
                supporting: [
                    "In one-touch, pre-decide the next action before contact.",
                    "One-touch speed comes from earlier pictures, not faster feet.",
                    "Make your decision in the scan phase so the touch stays clean.",
                    "If you decide late, execution breaks down in one-touch."
                ]
            )
        case .otpTempoAndQuality:
            return ThemeLines(
                anchor: "One-touch only works if your decision is made before expected arrival.",
                supporting: [
                    "Excellent one-touch rhythm - keep the same speed with clean choices.",
                    "Your tempo is good; keep confirming early so execution stays sharp.",
                    "Stay ahead of the ball and keep your one-touch quality high."
                ]
            )
        case .otpBodyShape:
            return ThemeLines(
                anchor: "Your last look should confirm, not decide.",
                supporting: [
                    "Body shape early so your touch can match the decision.",
                    "Reduce late corrections by preparing the receiving angle sooner.",
                    "Decision and touch must be one action, not two separate moments.",
                    "Pre-open and commit early to clean up one-touch execution."
                ]
            )
        case .testScanEarly:
            let biasText = session.biasDirection.map { " and avoid defaulting \($0.userFacingName.lowercased())" } ?? ""
            return ThemeLines(
                anchor: "Speed of play is speed of thought.",
                supporting: [
                    "In the 2-Minute Test, scan before the pass so you can decide early\(biasText).",
                    "Treat each rep like game pressure: picture the action before contact.",
                    "Use early shoulders checks so your first decision is ready on arrival.",
                    "Build repeatable early scans across all reps."
                ]
            )
        case .testComposure:
            return ThemeLines(
                anchor: "The window of opportunity closes before expected arrival.",
                supporting: [
                    "Your timing swings between reps - settle rhythm and keep your scans early.",
                    "Calm feet and clear eyes will make your test results more reliable.",
                    "Consistency is the target: same early process every rep.",
                    "Do not chase speed; build stable early decisions first."
                ]
            )
        case .genericConsistency:
            return ThemeLines(
                anchor: "Decide before expected arrival.",
                supporting: [
                    "Keep your process stable rep to rep: early scan, clear cue, committed action.",
                    "Good moments are there - now make them repeatable.",
                    "Reduce variance by using the same early routine each rep.",
                    "Consistency under pressure builds trust in your decisions."
                ]
            )
        }
    }

    private static func headline(for state: PlayerState, modifiers: Set<StateModifier>) -> String {
        if modifiers.contains(.improving) {
            switch state {
            case .sharp: return "Sharp session and trending up"
            case .lateCorrect: return "Good decisions, and timing is improving"
            case .fastIncorrect: return "Speed is there, and quality is climbing"
            case .lateIncorrect: return "Found better control this session - keep building"
            case .inconsistent: return "Progress is there - now make your process repeatable"
            }
        }
        if modifiers.contains(.declining) {
            switch state {
            case .sharp: return "Still strong - reset details to hold your standard"
            case .lateCorrect: return "Quality stayed fair, but timing dipped"
            case .fastIncorrect: return "Tempo stayed high, but selection slipped"
            case .lateIncorrect: return "Tough session - reset process and respond next block"
            case .inconsistent: return "Your level swung this session - reset a stable routine"
            }
        }
        switch state {
        case .sharp: return "You were ahead of pressure today"
        case .lateCorrect: return "You chose well, but too late at times"
        case .fastIncorrect: return "Your speed outpaced your selection this session"
        case .lateIncorrect: return "Pressure arrived before your decision was set"
        case .inconsistent: return "Good moments were there, but your process was inconsistent"
        }
    }

    private static func supportingDetail(for session: SessionResult, previous: SessionRecord?) -> String {
        let total = max(session.totalReps, 1)
        let accuracy = Int(round(Double(session.correctCount) / Double(total) * 100))
        var detail = "Accuracy \(accuracy)%"
        if let window = session.avgDecisionWindowSeconds {
            detail += ", decision window \(DecisionTimingModel.summaryText(windowSeconds: window))"
        }
        if let previous, let prevWindow = previous.avgDecisionWindowSeconds, let currWindow = session.avgDecisionWindowSeconds {
            let delta = currWindow - prevWindow
            if abs(delta) >= 0.02 {
                detail += delta > 0
                    ? ", \(String(format: "+%.2fs", delta)) more time before expected arrival vs prior same-activity session"
                    : ", \(String(format: "%.2fs", delta)) less time before expected arrival vs prior same-activity session"
            }
        }
        return detail
    }
}
