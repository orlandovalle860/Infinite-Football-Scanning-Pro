import SwiftUI

struct AchievementsView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var router: AppRouter

    private let coreBadges: [PlayerBadge] = [
        .consistent,
        .earlyDecider,
        .forwardThinker
    ]

    private var selectedProfile: UserProfile? {
        if let selectedId = playerStore.selectedPlayerId {
            return profileManager.profile(id: selectedId)
        }
        return profileManager.currentProfile
    }

    private var earnedBadges: [PlayerBadge] {
        guard let profile = selectedProfile else { return [] }
        let unlocked = Set(profile.unlockedBadges)
        return coreBadges.filter { unlocked.contains($0) }
    }

    private var lockedBadges: [PlayerBadge] {
        let earnedSet = Set(earnedBadges)
        return coreBadges.filter { !earnedSet.contains($0) }
    }

    private var recentTrainingSessions: [SessionResult] {
        guard let profile = selectedProfile else { return [] }
        return profile.sessionResults.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                if !earnedBadges.isEmpty {
                    sectionTitle("Earned")
                    ForEach(earnedBadges, id: \.rawValue) { badge in
                        earnedBadgeRow(badge)
                    }
                }

                if !lockedBadges.isEmpty {
                    sectionTitle("Locked")
                    ForEach(lockedBadges, id: \.rawValue) { badge in
                        lockedBadgeRow(badge)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("Your Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Achievements")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Text("\(earnedBadges.count) of \(coreBadges.count) earned")
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

    private func earnedBadgeRow(_ badge: PlayerBadge) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: badge))
                .font(.title3.weight(.semibold))
                .foregroundColor(.yellow)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(badge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(badge.unlockDescription)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func lockedBadgeRow(_ badge: PlayerBadge) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.6))
                Text(badge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            Text(unlockConditionText(for: badge))
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            if let hint = progressHint(for: badge) {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    private func iconName(for badge: PlayerBadge) -> String {
        switch badge {
        case .consistent:
            return "checkmark.seal.fill"
        case .earlyDecider:
            return "bolt.fill"
        case .forwardThinker:
            return "arrow.up.right.circle.fill"
        default:
            return "star.fill"
        }
    }

    private func unlockConditionText(for badge: PlayerBadge) -> String {
        switch badge {
        case .consistent:
            return "Unlock: 3 sessions in a row with accuracy >= 80% and decision speed not Too Late."
        case .earlyDecider:
            return "Unlock: avg decision time under 0.90s in a session."
        case .forwardThinker:
            return "Unlock: Forward Thinking >= 60% when forward opportunities exist."
        default:
            return "Unlock condition unavailable."
        }
    }

    private func progressHint(for badge: PlayerBadge) -> String? {
        switch badge {
        case .earlyDecider:
            guard let latest = recentTrainingSessions.first?.avgDecisionTime else { return nil }
            return String(format: "You're close — current avg: %.2fs", latest)
        case .forwardThinker:
            guard let withForward = recentTrainingSessions.first(where: { ($0.forwardOpportunityCount ?? 0) > 0 }),
                  let opp = withForward.forwardOpportunityCount, opp > 0,
                  let choices = withForward.forwardChoiceCount else { return nil }
            let pct = Int(round(Double(choices) / Double(opp) * 100.0))
            return "You're close — current forward thinking: \(pct)%"
        case .consistent:
            let streak = consistencyStreak()
            return "You're close — current qualifying streak: \(streak)/3"
        default:
            return nil
        }
    }

    private func consistencyStreak() -> Int {
        var streak = 0
        for session in recentTrainingSessions {
            guard streak < 3 else { break }
            guard session.totalReps > 0 else { break }
            let accuracy = Double(session.correctCount) / Double(session.totalReps)
            let notTooLate = (session.avgDecisionTime ?? .greatestFiniteMagnitude) <= 1.20
            if accuracy >= 0.80 && notTooLate {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }
}

