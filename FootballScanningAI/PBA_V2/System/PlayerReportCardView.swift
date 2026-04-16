//
//  PlayerReportCardView.swift
//  FootballScanningAI
//
//  PBA V2 — Report card: four category grades, overall score, and coaching insight.
//

import SwiftUI

struct PlayerReportCardView: View {
    let data: ReportCardData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                titleSection
                overallSection
                nextLevelSection
                progressionBarSection
                strengthsLimitersSection
                coreSections
                insightSection
                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var titleSection: some View {
        Text("PLAYER DEVELOPMENT")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.yellow)
    }

    private var overallSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where You Are")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.75))
            HStack {
                Text("Current Tier")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(data.overallTierDisplay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            Text(data.overallStageContext)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Text(data.overallSupportMessage)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Text(data.overallProgressionMessage)
                .font(.caption)
                .foregroundColor(.yellow.opacity(0.95))
            Text(data.overallNextTarget)
                .font(.caption.weight(.semibold))
                .foregroundColor(.yellow.opacity(0.95))
            if data.overallGrade != "—" {
                Text("(Grade: \(data.overallGrade))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }

    private var nextLevelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Level")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.75))
            Text(data.nextLevelName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow.opacity(0.95))
            Text("To get there:")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            ForEach(data.nextLevelRequirements, id: \.self) { requirement in
                Text("• \(requirement)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private var progressionBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progression Path")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            HStack(spacing: 8) {
                progressPill("Emerging", active: data.overallTier == "Emerging" || data.overallTier == "Needs Work")
                progressPill("Developing", active: data.overallTier == "Developing")
                progressPill("Strong", active: data.overallTier == "Strong")
                progressPill("Elite", active: data.overallTier == "Elite")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Focus Next: \(data.focusNext)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.yellow.opacity(0.95))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private func progressPill(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundColor(active ? .black : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(active ? Color.yellow : Color.white.opacity(0.10))
            .cornerRadius(999)
    }

    private var coreSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            metricCard(
                title: "Decision Speed",
                primary: "\(data.decisionSpeedTier) • \(data.decisionSpeedAvgTime.map { String(format: "%.2fs", $0) } ?? "—") • \(data.decisionSpeedZone)",
                message: data.decisionSpeedMessage,
                target: data.overallNextTarget
            )
            metricCard(
                title: "Decision Accuracy",
                primary: "\(data.accuracyPercent.map { "\($0)%" } ?? "—") • \(data.accuracyTier)",
                message: data.accuracyMessage,
                target: nil
            )
            metricCard(
                title: "Forward Thinking",
                primary: "\(data.forwardThinkingPercent.map { "\($0)%" } ?? "—") • \(data.forwardThinkingTier)",
                message: data.forwardThinkingMessage,
                target: nil
            )
        }
    }

    private var strengthsLimitersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Strength: \(data.strength)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
            Text("Limiter: \(data.limiter)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Text("Focus Next: \(data.focusNext)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.yellow.opacity(0.95))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private func metricCard(title: String, primary: String, message: String, target: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
            Text(primary)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.78))
            if let target {
                Text(target)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.yellow.opacity(0.95))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coaching Insight")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow)
            Text(data.coachingInsight)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }
}

#Preview {
    NavigationStack {
        PlayerReportCardView(data: ReportCardData(
            decisionBeforeContact: "B+",
            decisionSpeed: "B",
            firstTouchCommitment: "A-",
            pressureEscape: "B",
            overallGrade: "B+",
            overallTier: "Strong",
            overallTierDisplay: "🔵 Strong Player",
            overallStageContext: "Stage 3 — Strengthening Decision Timing",
            overallSupportMessage: "You're making the right decisions, but slightly late.",
            overallProgressionMessage: "You're close to Elite (Early Decisions).",
            overallNextTarget: "Next Target: < 1.10s",
            focusNext: "Decision Speed",
            nextLevelName: "Elite",
            nextLevelRequirements: ["Avg decision time < 0.90s", "Accuracy >= 90%"],
            strength: "Decision Accuracy (88%)",
            limiter: "Decision Speed timing is slightly late",
            decisionSpeedTier: "Strong",
            decisionSpeedAvgTime: 1.02,
            decisionSpeedZone: "On Time",
            decisionSpeedMessage: "Good timing — push toward earlier decisions.",
            accuracyPercent: 88,
            accuracyTier: "Strong",
            accuracyMessage: "Great decision quality — keep consistency high.",
            forwardThinkingPercent: 56,
            forwardThinkingTier: "Strong",
            forwardThinkingMessage: "Good forward intent — keep scanning for forward options.",
            coachingInsight: "Your development is on track. Focus on deciding before expected arrival. Recommended next: Playing Away From Pressure—build consistent early decisions."
        ))
    }
}
