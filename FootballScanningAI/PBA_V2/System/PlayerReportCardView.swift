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
                gradesCard
                overallSection
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
        Text("PLAYER REPORT CARD")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.yellow)
    }

    private var gradesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            gradeRow("Decision Speed", grade: data.decisionSpeed)
            Divider().background(Color.white.opacity(0.2))
            gradeRow("Pressure Escape", grade: data.pressureEscape)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func gradeRow(_ label: String, grade: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(grade)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(grade == "—" ? .white.opacity(0.5) : .yellow)
        }
    }

    private var overallSection: some View {
        HStack {
            Text("Overall Decision Score")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(data.overallGrade)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(data.overallGrade == "—" ? .white.opacity(0.5) : .yellow)
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
            coachingInsight: "Your development is on track. Focus on deciding before the ball arrives. Recommended next: Playing Away From Pressure—build consistent early decisions."
        ))
    }
}
