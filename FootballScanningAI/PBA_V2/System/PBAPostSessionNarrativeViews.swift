//
//  PBAPostSessionNarrativeViews.swift
//  FootballScanningAI
//
//  Coaching debrief: A Headline → B Trend → C Coach insight → D Next step → (E Your numbers in caller).
//

import SwiftUI

struct PBAPostSessionNarrativeStack: View {
    let narrative: PBAPostSessionNarrative

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headlineCard
            trendCard
            coachInsightCard
            nextStepCard
        }
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Headline")
                .font(.caption.weight(.bold))
                .foregroundColor(.cyan.opacity(0.95))
                .textCase(.uppercase)
            Text(narrative.headlineInsight)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .cornerRadius(18)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(narrative.progressSectionTitle)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            ForEach(Array(narrative.progressLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 10) {
                    Text("•")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.green.opacity(0.9))
                    Text(line)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if narrative.usesProgressPlaceholder {
                Text("More sessions unlock clearer before/after comparisons.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    private var coachInsightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach insight")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Text(narrative.coachInsight)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.blue.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private var nextStepCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(narrative.nextStepTitle)
                .font(.caption.weight(.bold))
                .foregroundColor(.yellow.opacity(0.95))
                .textCase(.uppercase)
            Text(narrative.nextStepBody)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.yellow.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}
