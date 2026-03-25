//
//  ActivityInstructionView.swift
//  FootballScanningAI
//
//  PBA V2 — Standardized instruction screen before each activity (goal, cues, rule, scoring, Start Block).
//

import SwiftUI

struct ActivityInstructionView: View {
    let activity: ActivityKind
    /// When `.partner`, shows how Display setup precedes the block countdown.
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

    @State private var dontShowAgain = false
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(data.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                sectionHeader("Goal")
                Text(data.goal)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                sectionHeader("What to look for")
                Text(data.whatToLookFor)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                sectionHeader("What to do")
                Text(data.whatToDo)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                sectionHeader("Scoring")
                Text(data.scoring)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if trainingMode == .partner {
                    Text("Partner: After Start Block, the Display opens partner setup (join code or Local Network). The 3–2–1 block countdown runs after the coach connects.")
                        .font(.footnote)
                        .foregroundColor(.cyan.opacity(0.92))
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
        )
        .ignoresSafeArea()
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

    private func startBlock() {
        if dontShowAgain {
            ActivityInstructionContent.setDontShowAgain(true, for: activity)
        }
        onStartBlock()
    }
}
