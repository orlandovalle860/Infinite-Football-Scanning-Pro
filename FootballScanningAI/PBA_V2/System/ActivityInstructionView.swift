//
//  ActivityInstructionView.swift
//  FootballScanningAI
//
//  PBA V2 — Instruction screen before each activity (structured copy, Start Block).
//

import SwiftUI

struct ActivityInstructionView: View {
    let activity: ActivityKind
    /// When `.partner`, shows post-copy note about join / countdown.
    let trainingMode: TrainingMode?
    let onStartBlock: () -> Void

    init(activity: ActivityKind, trainingMode: TrainingMode? = nil, onStartBlock: @escaping () -> Void) {
        self.activity = activity
        self.trainingMode = trainingMode
        self.onStartBlock = onStartBlock
    }

    private var data: ActivityInstructionData {
        ActivityInstructionContent.content(for: activity)
    }

    /// Section 3: activity rules + shared timing line.
    private var yourDecisionLines: [String] {
        data.yourDecisionLines + [ActivityInstructionData.timingLine]
    }

    @State private var dontShowAgain = false
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(data.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // 1 — SETUP
                sectionHeader("1 — SETUP")
                bulletList(ActivityInstructionData.instructionSetupLines)

                // 2 — AT THE BEEP
                sectionHeader("2 — AT THE BEEP")
                bulletList(ActivityInstructionData.instructionAtTheBeepLines)

                // 3 — YOUR DECISION
                sectionHeader("3 — YOUR DECISION")
                bulletList(yourDecisionLines)

                // 4 — COACH
                sectionHeader("4 — COACH")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(ActivityInstructionData.instructionCoachLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.cyan.opacity(0.75))
                            Text(line)
                                .font(.subheadline)
                                .foregroundColor(.cyan.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                sectionHeader("Scoring")
                Text(data.scoringShort.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let details = data.scoringDetails, !details.isEmpty {
                    DisclosureGroup {
                        Text(details.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    } label: {
                        Text("Details")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.cyan.opacity(0.95))
                    }
                    .tint(.cyan.opacity(0.9))
                }

                if trainingMode == .partner {
                    Text("After Start Block, the Display opens partner setup (join code or Local Network). Countdown starts after the coach connects.")
                        .font(.footnote)
                        .foregroundColor(.cyan.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: $dontShowAgain) {
                    Text("Don't show again")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .tint(.yellow)
                .padding(.top, 8)

                Button(action: startBlock) {
                    Text("Start Block")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.yellow)
                        .cornerRadius(18)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .navigationTitle("Instructions")
        .navigationBarTitleDisplayMode(.inline)
        .pbaHomeToolbar(router: router)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.yellow.opacity(0.95))
    }

    private func bulletList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(.white.opacity(0.65))
                    Text(line)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func startBlock() {
        if dontShowAgain {
            ActivityInstructionContent.setDontShowAgain(true, for: activity)
        }
        onStartBlock()
    }
}
