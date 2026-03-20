import Foundation

enum PlayerIdentity: String, Codable, CaseIterable {
    case anticipator
    case reader
    case attacker
    case playmaker

    var title: String {
        switch self {
        case .anticipator: return "Anticipator"
        case .reader: return "Reader"
        case .attacker: return "Attacker"
        case .playmaker: return "Playmaker"
        }
    }

    var emojiTitle: String {
        switch self {
        case .anticipator: return "🧠 Anticipator"
        case .reader: return "📖 Reader"
        case .attacker: return "⚡ Attacker"
        case .playmaker: return "🎯 Playmaker"
        }
    }

    var shortDescription: String {
        switch self {
        case .anticipator:
            return "You read pressure early and decide quickly."
        case .reader:
            return "You make strong choices and keep decision quality high."
        case .attacker:
            return "You look forward often and attack space with intent."
        case .playmaker:
            return "You balance speed, accuracy, and forward choices."
        }
    }

    var changeMessage: String {
        switch self {
        case .anticipator:
            return "You're now making faster decisions under pressure."
        case .reader:
            return "You're now showing strong reading and decision accuracy."
        case .attacker:
            return "You're now choosing forward options more consistently."
        case .playmaker:
            return "You're now balancing speed, accuracy, and forward play."
        }
    }
}

enum PlayerIdentityEngine {
    private static let lastIdentityKey = "pba_player_identity"

    static func confirmedIdentity(from sessions: [SessionResult], previousIdentity: PlayerIdentity?) -> PlayerIdentity? {
        let training = sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        guard training.count >= 2 else { return nil }
        let recent = Array(training.prefix(3))
        let sampleCount = recent.count

        let gainCandidate = gainIdentity(from: recent, sampleCount: sampleCount)
        if let gainCandidate {
            if let previousIdentity, previousIdentity != gainCandidate, shouldKeepIdentity(previousIdentity, sessions: recent, sampleCount: sampleCount) {
                return previousIdentity
            }
            return gainCandidate
        }

        // No new strong identity signal — keep current one unless strong loss pattern appears.
        if let previousIdentity {
            if shouldKeepIdentity(previousIdentity, sessions: recent, sampleCount: sampleCount) {
                return previousIdentity
            }
            return .playmaker
        }

        return .playmaker
    }

    static func trendingTowardIdentity(from sessions: [SessionResult], currentIdentity: PlayerIdentity?) -> PlayerIdentity? {
        let training = sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        guard training.count >= 2 else { return nil }
        let recent = Array(training.prefix(3))

        let avgTime = averageDecisionTime(from: recent)
        let avgAccuracy = averageAccuracyPercent(from: recent)
        let avgForward = averageForwardPercent(from: recent)

        if let t = avgTime, let a = avgAccuracy, t < 1.02, a >= 78, currentIdentity != .anticipator {
            return .anticipator
        }
        if let f = avgForward, f >= 55, currentIdentity != .attacker {
            return .attacker
        }
        if let a = avgAccuracy, let t = avgTime, a >= 83, t > 1.00, currentIdentity != .reader {
            return .reader
        }
        return nil
    }

    private static func gainIdentity(from sessions: [SessionResult], sampleCount: Int) -> PlayerIdentity? {
        guard sampleCount >= 2 else { return nil }
        let requiredHits = min(2, sampleCount)

        let anticipatorHits = sessions.filter { meetsAnticipatorGain($0) }.count
        let attackerHits = sessions.filter { meetsAttackerGain($0) }.count
        let readerHits = sessions.filter { meetsReaderGain($0) }.count

        // Priority when multiple match: Anticipator > Attacker > Reader > Playmaker
        if anticipatorHits >= requiredHits { return .anticipator }
        if attackerHits >= requiredHits { return .attacker }
        if readerHits >= requiredHits { return .reader }
        return nil
    }

    private static func shouldKeepIdentity(_ identity: PlayerIdentity, sessions: [SessionResult], sampleCount: Int) -> Bool {
        guard sampleCount >= 2 else { return true }
        let requiredLossHits = min(2, sampleCount)
        let lossHits: Int
        switch identity {
        case .anticipator:
            // Hysteresis: harder to lose than gain (gain < 0.95s, lose > 1.05s).
            lossHits = sessions.filter { losesAnticipator($0) }.count
        case .reader:
            // Harder to lose Reader than gain.
            lossHits = sessions.filter { losesReader($0) }.count
        case .attacker:
            // Harder to lose Attacker than gain.
            lossHits = sessions.filter { losesAttacker($0) }.count
        case .playmaker:
            return true
        }
        return lossHits < requiredLossHits
    }

    private static func averageDecisionTime(from sessions: [SessionResult]) -> Double? {
        let times = sessions.compactMap(\.avgDecisionTime)
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    private static func averageAccuracyPercent(from sessions: [SessionResult]) -> Double? {
        let valid = sessions.filter { $0.totalReps > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0.0) { $0 + (Double($1.correctCount) / Double($1.totalReps) * 100.0) } / Double(valid.count)
    }

    private static func averageForwardPercent(from sessions: [SessionResult]) -> Double? {
        let values = sessions.compactMap { s -> Double? in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choice = s.forwardChoiceCount else { return nil }
            return Double(choice) / Double(opp) * 100.0
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func meetsAnticipatorGain(_ session: SessionResult) -> Bool {
        guard let t = session.avgDecisionTime, session.totalReps > 0 else { return false }
        let accuracy = Double(session.correctCount) / Double(session.totalReps) * 100.0
        return t < 0.95 && accuracy >= 80
    }

    private static func meetsReaderGain(_ session: SessionResult) -> Bool {
        guard let t = session.avgDecisionTime, session.totalReps > 0 else { return false }
        let accuracy = Double(session.correctCount) / Double(session.totalReps) * 100.0
        return accuracy >= 85 && t > 1.05
    }

    private static func meetsAttackerGain(_ session: SessionResult) -> Bool {
        guard let opp = session.forwardOpportunityCount, opp > 0, let choice = session.forwardChoiceCount else { return false }
        let forward = Double(choice) / Double(opp) * 100.0
        return forward >= 60
    }

    private static func losesAnticipator(_ session: SessionResult) -> Bool {
        guard let t = session.avgDecisionTime else { return false }
        return t > 1.05
    }

    private static func losesReader(_ session: SessionResult) -> Bool {
        guard session.totalReps > 0, let t = session.avgDecisionTime else { return false }
        let accuracy = Double(session.correctCount) / Double(session.totalReps) * 100.0
        return accuracy < 80 || t < 0.95
    }

    private static func losesAttacker(_ session: SessionResult) -> Bool {
        guard let opp = session.forwardOpportunityCount, opp > 0, let choice = session.forwardChoiceCount else { return false }
        let forward = Double(choice) / Double(opp) * 100.0
        return forward < 50
    }

    static func loadLastIdentity(playerId: UUID?) -> PlayerIdentity? {
        let key = playerId.map { "\(lastIdentityKey)_\($0.uuidString)" } ?? lastIdentityKey
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return PlayerIdentity(rawValue: raw)
    }

    static func saveIdentity(_ identity: PlayerIdentity, playerId: UUID?) {
        let key = playerId.map { "\(lastIdentityKey)_\($0.uuidString)" } ?? lastIdentityKey
        UserDefaults.standard.set(identity.rawValue, forKey: key)
    }
}

