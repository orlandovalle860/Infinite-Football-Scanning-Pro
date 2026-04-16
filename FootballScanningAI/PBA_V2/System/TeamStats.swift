//
//  TeamStats.swift
//  FootballScanningAI
//
//  PBA V2 — Team leaderboard + weekly challenge.
//

import Foundation
import SwiftUI

struct WeeklyChallengeEntry: Equatable, Identifiable {
    let id: UUID
    let playerName: String
    let level: ActivityAdaptiveLevel
    let score: Int
    let movement: String
    let sessionsCompleted: Int
    let sessionStreak: Int
    let hasBadge: Bool
}

struct TeamStats: Equatable {
    let leaderboard: [WeeklyChallengeEntry]
    let weeklyChallengeTitle: String
    let weeklyChallengeCompleted: Bool
    let teamBadgeName: String?
    let yourRank: Int?
    let yourLevel: ActivityAdaptiveLevel?
    let yourMovement: String?
}

private func weeklyChallengeSessions(_ sessions: [SessionResult], referenceNow: Date) -> [SessionResult] {
    let start = Calendar.current.date(byAdding: .day, value: -7, to: referenceNow) ?? referenceNow
    return sessions
        .filter { $0.date >= start && $0.date <= referenceNow }
        .sorted(by: { $0.date < $1.date })
}

private func sessionScore(_ session: SessionResult) -> Int {
    if let score = session.decisionTotalScore {
        if score <= 60 {
            return max(0, min(100, Int(((score / 60.0) * 100.0).rounded())))
        }
        return max(0, min(100, Int(score.rounded())))
    }
    if session.totalReps > 0 {
        return Int(round(Double(session.correctCount) / Double(session.totalReps) * 100.0))
    }
    return session.estimatedDecisionSpeedScore ?? 0
}

private func earlyPercentage(_ session: SessionResult) -> Double {
    let total = session.speedCounts.fast + session.speedCounts.medium + session.speedCounts.slow
    guard total > 0 else { return 0 }
    return Double(session.speedCounts.fast) / Double(total)
}

func makeTeamStats(profiles: [UserProfile], currentPlayerId: UUID? = nil, referenceNow: Date = Date()) -> TeamStats {
    let playersWithWeekly: [(UserProfile, [SessionResult])] = profiles.map { profile in
        (profile, weeklyChallengeSessions(profile.sessionResults, referenceNow: referenceNow))
    }

    let entries: [WeeklyChallengeEntry] = playersWithWeekly.compactMap { pair in
        let profile = pair.0
        let weekly = pair.1
        guard let latest = weekly.last else { return nil }
        let level = currentLevel(from: weekly)
        let movement = movementArrow(for: profile, currentWeekly: weekly, referenceNow: referenceNow)
        return WeeklyChallengeEntry(
            id: profile.id,
            playerName: profile.name,
            level: level,
            score: sessionScore(latest),
            movement: movement,
            sessionsCompleted: weekly.count,
            sessionStreak: profile.sessionStreakCount,
            hasBadge: !profile.unlockedBadges.isEmpty
        )
    }

    let sorted = entries.sorted {
        if $0.level.rank == $1.level.rank {
            return $0.score > $1.score
        }
        return $0.level.rank > $1.level.rank
    }

    let challenge = weeklyChallengeStatus(profiles: profiles, referenceNow: referenceNow)
    let yourRank = currentPlayerId.flatMap { id in
        sorted.firstIndex(where: { $0.id == id }).map { $0 + 1 }
    }
    let yourLevel = currentPlayerId.flatMap { id in
        sorted.first(where: { $0.id == id })?.level
    }
    let yourMovement = currentPlayerId.flatMap { id in
        sorted.first(where: { $0.id == id })?.movement
    }

    return TeamStats(
        leaderboard: sorted,
        weeklyChallengeTitle: challenge.title,
        weeklyChallengeCompleted: challenge.completed,
        teamBadgeName: challenge.completed ? "Locked In" : nil,
        yourRank: yourRank,
        yourLevel: yourLevel,
        yourMovement: yourMovement
    )
}

func makeTeamStats(players: [Player], profileManager: UserProfileManager, currentPlayerId: UUID? = nil, referenceNow: Date = Date()) -> TeamStats {
    let profiles = players.compactMap { profileManager.profile(id: $0.id) }
    return makeTeamStats(profiles: profiles, currentPlayerId: currentPlayerId, referenceNow: referenceNow)
}

struct TeamLeadersThisWeekView: View {
    let stats: TeamStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Team Leaderboard")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Text(stats.weeklyChallengeTitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            if let badge = stats.teamBadgeName {
                Text("🏅 Team Badge: \(badge)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow.opacity(0.95))
            }

            if stats.leaderboard.isEmpty {
                Text("No team sessions yet this week.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(stats.leaderboard.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text("\(index + 1). \(entry.playerName)")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white.opacity(0.95))
                            Spacer()
                            Text(entry.level.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.yellow.opacity(0.95))
                            Text("\(entry.score)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.92))
                            movementView(entry.movement)
                            if entry.sessionStreak > 0 { Text("🔥").font(.caption) }
                            if entry.hasBadge { Text("⚡").font(.caption) }
                        }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 6) {
                Text("Your Rank: \(stats.yourRank.map(String.init) ?? "Not ranked")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text("Your Level: \(stats.yourLevel?.rawValue ?? "—")")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.82))
                if let movement = stats.yourMovement {
                    HStack(spacing: 6) {
                        Text("Movement:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.78))
                        movementView(movement)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
    }

    @ViewBuilder
    private func movementView(_ movement: String) -> some View {
        let color: Color = movement == "↑" ? .green : (movement == "↓" ? .red : .white.opacity(0.7))
        Text(movement)
            .font(.caption.weight(.bold))
            .foregroundColor(color)
    }
}

struct CoachChallengeNeedsAttention: Equatable, Identifiable {
    let id = UUID()
    let playerName: String
    let issue: String
}

struct CoachChallengePlayerDetail: Equatable, Identifiable {
    let id: UUID
    let playerName: String
    let score: Int
    let improvement: Int
    let earlyCount: Int
    let onTimeCount: Int
    let lateCount: Int
    let recentScores: [Int]
    let recommendedFocus: String
}

struct CoachChallengeDashboardData: Equatable {
    let activePlayers: Int
    let averageScore: Int
    let weeklyChallengeTitle: String
    let weeklyChallengeCompleted: Bool
    let teamBadgeName: String?
    let leaderboard: [WeeklyChallengeEntry]
    let needsAttention: [CoachChallengeNeedsAttention]
    let earlyTrendStartPercent: Int
    let earlyTrendEndPercent: Int
    let timingTrendStart: Double
    let timingTrendEnd: Double
    let coachingCue: String
    let playerDetails: [CoachChallengePlayerDetail]
}

func makeCoachChallengeDashboardData(profiles: [UserProfile], referenceNow: Date = Date()) -> CoachChallengeDashboardData {
    let activeProfiles = profiles.filter { !weeklyChallengeSessions($0.sessionResults, referenceNow: referenceNow).isEmpty }
    let teamStats = makeTeamStats(profiles: profiles, referenceNow: referenceNow)
    let detailRows: [CoachChallengePlayerDetail] = activeProfiles.compactMap { profile in
        let weekly = weeklyChallengeSessions(profile.sessionResults, referenceNow: referenceNow)
        guard let last = weekly.last else { return nil }
        let first = weekly.first
        let improvement = (first != nil) ? (sessionScore(last) - sessionScore(first!)) : 0
        let weeklyScores = weekly.map(sessionScore)
        let early = weekly.reduce(0) { $0 + $1.speedCounts.fast }
        let onTime = weekly.reduce(0) { $0 + $1.speedCounts.medium }
        let late = weekly.reduce(0) { $0 + $1.speedCounts.slow }
        let latePct = weekly.isEmpty ? 0 : Double(late) / Double(max(1, early + onTime + late))
        let focus: String
        if improvement <= 0 || latePct >= 0.4 {
            focus = "Decide earlier before expected arrival."
        } else {
            focus = "Keep committing early under pressure."
        }
        return CoachChallengePlayerDetail(
            id: profile.id,
            playerName: profile.name,
            score: sessionScore(last),
            improvement: improvement,
            earlyCount: early,
            onTimeCount: onTime,
            lateCount: late,
            recentScores: Array(weeklyScores.suffix(5)),
            recommendedFocus: focus
        )
    }

    let avgScore = detailRows.isEmpty ? 0 : Int(round(Double(detailRows.map(\.score).reduce(0, +)) / Double(detailRows.count)))

    let attentionRows: [CoachChallengeNeedsAttention] = detailRows.compactMap { row in
        let total = row.earlyCount + row.onTimeCount + row.lateCount
        let latePct = total > 0 ? Double(row.lateCount) / Double(total) : 0
        if row.improvement <= 0 || row.score < 70 {
            return CoachChallengeNeedsAttention(playerName: row.playerName, issue: "No improvement this week")
        }
        if latePct >= 0.4 {
            return CoachChallengeNeedsAttention(playerName: row.playerName, issue: "Late dominant")
        }
        return nil
    }

    let teamTrendPairs: [(earlyStart: Double, earlyEnd: Double, timingStart: Double, timingEnd: Double)] = activeProfiles.compactMap { profile -> (earlyStart: Double, earlyEnd: Double, timingStart: Double, timingEnd: Double)? in
        let weekly = weeklyChallengeSessions(profile.sessionResults, referenceNow: referenceNow)
        guard let first = weekly.first, let last = weekly.last else { return nil }
        return (
            earlyStart: earlyPercentage(first),
            earlyEnd: earlyPercentage(last),
            timingStart: first.avgDecisionWindowSeconds ?? 0,
            timingEnd: last.avgDecisionWindowSeconds ?? 0
        )
    }
    let earlyStartAvg = teamTrendPairs.isEmpty ? 0 : teamTrendPairs.map(\.earlyStart).reduce(0, +) / Double(teamTrendPairs.count)
    let earlyEndAvg = teamTrendPairs.isEmpty ? 0 : teamTrendPairs.map(\.earlyEnd).reduce(0, +) / Double(teamTrendPairs.count)
    let timingStartAvg = teamTrendPairs.isEmpty ? 0 : teamTrendPairs.map(\.timingStart).reduce(0, +) / Double(teamTrendPairs.count)
    let timingEndAvg = teamTrendPairs.isEmpty ? 0 : teamTrendPairs.map(\.timingEnd).reduce(0, +) / Double(teamTrendPairs.count)

    let coachingCue: String
    if earlyEndAvg > earlyStartAvg && timingEndAvg >= timingStartAvg {
        coachingCue = "Reinforce early scanning and quick commitment under pressure."
    } else {
        coachingCue = "Push players to decide earlier before the ball arrives"
    }

    return CoachChallengeDashboardData(
        activePlayers: activeProfiles.count,
        averageScore: avgScore,
        weeklyChallengeTitle: teamStats.weeklyChallengeTitle,
        weeklyChallengeCompleted: teamStats.weeklyChallengeCompleted,
        teamBadgeName: teamStats.teamBadgeName,
        leaderboard: teamStats.leaderboard,
        needsAttention: attentionRows,
        earlyTrendStartPercent: Int((earlyStartAvg * 100).rounded()),
        earlyTrendEndPercent: Int((earlyEndAvg * 100).rounded()),
        timingTrendStart: timingStartAvg,
        timingTrendEnd: timingEndAvg,
        coachingCue: coachingCue,
        playerDetails: detailRows.sorted(by: { $0.playerName < $1.playerName })
    )
}

struct TeamChallengeCoachDashboardView: View {
    let data: CoachChallengeDashboardData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weekly Challenge")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Text(data.weeklyChallengeTitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.82))
            if let badge = data.teamBadgeName {
                Text("🏅 Team Badge: \(badge)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow.opacity(0.95))
            }

            sectionTitle("Team Overview")
            Text("Active Players: \(data.activePlayers)")
                .foregroundColor(.white.opacity(0.9))
            Text("Average Score: \(data.averageScore)")
                .foregroundColor(.white.opacity(0.9))

            Divider().background(Color.white.opacity(0.2))

            sectionTitle("Leaderboard")
            if data.leaderboard.isEmpty {
                Text("No ranked players yet.")
                    .foregroundColor(.white.opacity(0.72))
            } else {
                ForEach(Array(data.leaderboard.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Text("\(index + 1). \(entry.playerName)")
                            .foregroundColor(.white.opacity(0.94))
                        Spacer()
                        Text(entry.level.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.yellow.opacity(0.95))
                        Text("\(entry.score)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                        movementText(entry.movement)
                    }
                }
            }

            Divider().background(Color.white.opacity(0.2))

            sectionTitle("Needs Attention")
            if data.needsAttention.isEmpty {
                Text("No priority issues this week.")
                    .foregroundColor(.white.opacity(0.72))
            } else {
                ForEach(data.needsAttention) { row in
                    Text("\(row.playerName) — \(row.issue)")
                        .foregroundColor(.white.opacity(0.9))
                }
            }

            Divider().background(Color.white.opacity(0.2))

            sectionTitle("Team Trends")
            Text("Early Decisions: \(data.earlyTrendStartPercent)% → \(data.earlyTrendEndPercent)%")
                .foregroundColor(.white.opacity(0.9))
            Text(String(format: "Avg Timing: %@ → %@", timingLabel(data.timingTrendStart), timingLabel(data.timingTrendEnd)))
                .foregroundColor(.white.opacity(0.9))

            Divider().background(Color.white.opacity(0.2))

            sectionTitle("Coaching Focus")
            Text(data.coachingCue)
                .foregroundColor(.yellow.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.yellow.opacity(0.95))
    }

    private func formatImprovement(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    @ViewBuilder
    private func movementText(_ movement: String) -> some View {
        let color: Color = movement == "↑" ? .green : (movement == "↓" ? .red : .white.opacity(0.7))
        Text(movement)
            .font(.caption.weight(.bold))
            .foregroundColor(color)
    }

    private func timingLabel(_ value: Double) -> String {
        if value > 0.05 { return String(format: "Early %.2fs", value) }
        if value < -0.05 { return String(format: "Late %.2fs", abs(value)) }
        return "On Time"
    }
}

private func currentLevel(from weeklySessions: [SessionResult]) -> ActivityAdaptiveLevel {
    let sorted = weeklySessions.sorted(by: { $0.date > $1.date })
    return makeActivityAdaptiveSnapshot(from: sorted).plan.level
}

private func weeklyChallengeStatus(profiles: [UserProfile], referenceNow: Date) -> (title: String, completed: Bool) {
    let active = profiles
        .map { weeklyChallengeSessions($0.sessionResults, referenceNow: referenceNow) }
        .filter { !$0.isEmpty }
    guard !active.isEmpty else { return ("Complete 3 sessions", false) }

    let allHaveThreeSessions = active.allSatisfy { $0.count >= 3 }
    if !allHaveThreeSessions {
        return ("Complete 3 sessions", false)
    }

    let allStrongOrAbove = active.allSatisfy { currentLevel(from: $0).rank >= ActivityAdaptiveLevel.strong.rank }
    return ("Reach Level Strong", allStrongOrAbove)
}

private func movementArrow(for profile: UserProfile, currentWeekly: [SessionResult], referenceNow: Date) -> String {
    let currentScore = currentWeekly.last.map(sessionScore) ?? 0
    let previousWindowStart = Calendar.current.date(byAdding: .day, value: -14, to: referenceNow) ?? referenceNow
    let previousWindowEnd = Calendar.current.date(byAdding: .day, value: -7, to: referenceNow) ?? referenceNow
    let previousSessions = profile.sessionResults
        .filter { $0.date >= previousWindowStart && $0.date < previousWindowEnd }
        .sorted(by: { $0.date < $1.date })
    let previousScore = previousSessions.last.map(sessionScore) ?? currentScore

    if currentScore > previousScore { return "↑" }
    if currentScore < previousScore { return "↓" }
    return "→"
}

#Preview("Weekly challenge") {
    ZStack {
        Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()
        TeamLeadersThisWeekView(
            stats: TeamStats(
                leaderboard: [
                    WeeklyChallengeEntry(id: UUID(), playerName: "Sam", level: .elite, score: 92, movement: "↑", sessionsCompleted: 4, sessionStreak: 5, hasBadge: true),
                    WeeklyChallengeEntry(id: UUID(), playerName: "Jordan", level: .strong, score: 84, movement: "→", sessionsCompleted: 3, sessionStreak: 2, hasBadge: false),
                    WeeklyChallengeEntry(id: UUID(), playerName: "Alex", level: .developing, score: 73, movement: "↓", sessionsCompleted: 5, sessionStreak: 1, hasBadge: true)
                ],
                weeklyChallengeTitle: "Complete 3 sessions",
                weeklyChallengeCompleted: false,
                teamBadgeName: nil,
                yourRank: 2,
                yourLevel: .strong,
                yourMovement: "↑"
            )
        )
        .padding()
    }
}
