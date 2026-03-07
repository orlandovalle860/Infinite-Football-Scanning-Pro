//
//  ActivityInstructionView.swift
//  FootballScanningAI
//
//  PBA V2 — Standardized instruction screen before each activity (goal, cues, rule, scoring, Start Block).
//

import SwiftUI

struct ActivityInstructionView: View {
    let activity: ActivityKind
    let onStartBlock: () -> Void

    private var data: ActivityInstructionData {
        ActivityInstructionContent.content(for: activity)
    }

    @State private var dontShowAgain = false

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
