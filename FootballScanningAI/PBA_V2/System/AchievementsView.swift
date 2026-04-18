import SwiftUI

struct AchievementsView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var router: AppRouter

    private let tracks: [BadgeTrack] = BadgeTrack.allCases

    private var selectedProfile: UserProfile? {
        if let selectedId = playerStore.selectedPlayerId {
            return profileManager.profile(id: selectedId)
        }
        return profileManager.currentProfile
    }

    private var earnedTracks: [BadgeTrack] {
        tracks.filter { currentLevel(for: $0) > 0 }
    }

    private var lockedTracks: [BadgeTrack] {
        tracks.filter { currentLevel(for: $0) == 0 }
    }

    private var recentTrainingSessions: [SessionResult] {
        guard let profile = selectedProfile else { return [] }
        return profile.sessionResults.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                if !earnedTracks.isEmpty {
                    sectionTitle("Earned")
                    ForEach(earnedTracks, id: \.rawValue) { track in
                        badgeTierRow(track)
                    }
                }

                if !lockedTracks.isEmpty {
                    sectionTitle("Locked")
                    ForEach(lockedTracks, id: \.rawValue) { track in
                        badgeTierRow(track)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("Your Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Achievements")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Text("\(earnedTracks.count) of \(tracks.count) tracks started")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.yellow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white.opacity(0.9))
    }

    private func badgeTierRow(_ track: BadgeTrack) -> some View {
        let level = currentLevel(for: track)
        let nextLevel = min(4, level + 1)
        let progress = progressToNextTier(for: track)
        let unlocked = level > 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: track.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(unlocked ? .yellow : .white.opacity(0.7))
                    .frame(width: 28, height: 28)
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(level == 0 ? "Level 0" : "Level \(romanNumeral(level))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(unlocked ? .yellow : .white.opacity(0.65))
            }

            if level < 4 {
                Text("Progress to Level \(romanNumeral(nextLevel))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                ProgressView(value: progress, total: 1)
                    .tint(.yellow)
                if progress >= 0.8 {
                    Text("You’re close to Level \(romanNumeral(nextLevel))")
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.95))
                }
            } else {
                Text("Level IV reached")
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.95))
            }
            Text(unlockConditionText(for: track))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(unlocked ? Color.yellow.opacity(0.14) : Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(unlocked ? Color.yellow.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func currentLevel(for track: BadgeTrack) -> Int {
        selectedProfile?.badgeTierLevels[track] ?? 0
    }

    private func unlockConditionText(for track: BadgeTrack) -> String {
        switch track {
        case .earlyThinker:
            return "Tier thresholds: 30% / 40% / 50% / 60% early decisions."
        case .levelUp:
            return "Tier thresholds: +10 / +15 / +20 / +25 score jump."
        case .lockedIn:
            return "Tier thresholds: late count ≤4 / ≤3 / ≤2 / ≤1."
        case .onFire:
            return "Tier thresholds: 3 / 5 / 10 / 20 session streak."
        case .aheadOfPlay:
            return "Tier thresholds: score 90 / 92 / 95 / 98."
        }
    }

    private func progressToNextTier(for track: BadgeTrack) -> Double {
        let level = currentLevel(for: track)
        guard level < 4 else { return 1.0 }
        let nextThreshold = threshold(for: track, level: level + 1)
        let metric = metricValue(for: track)
        switch track {
        case .lockedIn:
            // Lower is better for late count.
            let late = max(0, metric)
            if late <= nextThreshold { return 1.0 }
            let denom = max(1.0, nextThreshold + 4.0)
            return max(0, min(1, 1 - ((late - nextThreshold) / denom)))
        default:
            guard nextThreshold > 0 else { return 0 }
            return max(0, min(1, metric / nextThreshold))
        }
    }

    private func metricValue(for track: BadgeTrack) -> Double {
        switch track {
        case .earlyThinker:
            guard let latest = recentTrainingSessions.first else { return 0 }
            let total = latest.speedCounts.fast + latest.speedCounts.medium + latest.speedCounts.slow
            guard total > 0 else { return 0 }
            return Double(latest.speedCounts.fast) / Double(total)
        case .levelUp:
            guard recentTrainingSessions.count >= 2 else { return 0 }
            return Double(sessionScore(recentTrainingSessions[0]) - sessionScore(recentTrainingSessions[1]))
        case .lockedIn:
            return Double(recentTrainingSessions.first?.speedCounts.slow ?? 999)
        case .onFire:
            return Double(selectedProfile?.sessionStreakCount ?? 0)
        case .aheadOfPlay:
            guard let latest = recentTrainingSessions.first else { return 0 }
            return Double(sessionScore(latest))
        }
    }

    private func threshold(for track: BadgeTrack, level: Int) -> Double {
        let thresholds: [Double]
        switch track {
        case .earlyThinker: thresholds = [0.30, 0.40, 0.50, 0.60]
        case .levelUp: thresholds = [10, 15, 20, 25]
        case .lockedIn: thresholds = [4, 3, 2, 1]
        case .onFire: thresholds = [3, 5, 10, 20]
        case .aheadOfPlay: thresholds = [90, 92, 95, 98]
        }
        let idx = max(1, min(4, level)) - 1
        return thresholds[idx]
    }

    private func romanNumeral(_ level: Int) -> String {
        switch level {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        default: return "I"
        }
    }

    private func sessionScore(_ session: SessionResult) -> Int {
        if let s = session.decisionTotalScore {
            return max(0, min(100, Int(s.rounded())))
        }
        guard session.totalReps > 0 else { return session.estimatedDecisionSpeedScore ?? 0 }
        return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100.0))
    }
}

