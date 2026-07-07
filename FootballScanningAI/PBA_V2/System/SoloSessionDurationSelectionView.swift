//
//  SoloSessionDurationSelectionView.swift
//  FootballScanningAI
//
//  Solo: pick training style and session duration before starting an activity.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct SoloSessionDurationSelectionView: View {
    let activity: ActivityKind
    @EnvironmentObject private var router: AppRouter
    @State private var selectedStyle: SoloTrainingStyle = SoloTrainingStyle.loadLastSelected()
    @State private var selectedDuration: SoloSessionDurationChoice = SoloSessionDurationChoice.loadLastSelected()

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                VStack(spacing: 24) {
                    Text("Training style")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 20) {
                        ForEach(SoloTrainingStyle.allCases) { option in
                            selectionRow(title: option.title, isSelected: selectedStyle == option) {
                                guard selectedStyle != option else { return }
                                selectedStyle = option
                                SoloTrainingStyle.saveLastSelected(option)
                                soloSelectionHaptic()
                            }
                        }
                    }
                }

                VStack(spacing: 24) {
                    Text("How long do you want to train?")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 20) {
                        ForEach(SoloSessionDurationChoice.allCases) { option in
                            selectionRow(title: option.title, isSelected: selectedDuration == option) {
                                guard selectedDuration != option else { return }
                                selectedDuration = option
                                SoloSessionDurationChoice.saveLastSelected(option)
                                soloSelectionHaptic()
                            }
                        }
                    }
                }

                Button {
                    soloSelectionHaptic()
                    SoloTrainingStyle.saveLastSelected(selectedStyle)
                    SoloSessionDurationChoice.saveLastSelected(selectedDuration)
                    SoloTimeBasedSession.begin(duration: selectedDuration, style: selectedStyle)
                    PBASessionFlowPolicy.persistTrainingMode(.solo)
                    router.push(PBASessionFlowPolicy.routeForActivityLaunch(activity))
                } label: {
                    Text("Start")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(Color.yellow)
                        .cornerRadius(16)
                }
                .buttonStyle(SoloStartButtonStyle())

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedStyle = SoloTrainingStyle.loadLastSelected()
            selectedDuration = SoloSessionDurationChoice.loadLastSelected()
        }
    }

    private func selectionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                .foregroundColor(.white.opacity(isSelected ? 1 : 0.65))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func soloSelectionHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

private struct SoloStartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoloSessionTimerCornerBadge: View {
    let text: String
    var onLongPressEnd: (() -> Void)?

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(text)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.32))
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 1.2) {
                        onLongPressEnd?()
                    }
                    .accessibilityHint(onLongPressEnd == nil ? "" : "Long press to end session")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(onLongPressEnd != nil)
    }
}

struct SoloTimeBasedSessionCompleteView: View {
    let elapsedSeconds: TimeInterval
    let repCount: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Session complete")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                Text("Time: \(SoloSessionTimeFormat.mmss(elapsedSeconds))")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text("Reps: \(repCount)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer()

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundColor(.black)
            .padding(.bottom, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationBarBackButtonHidden(true)
    }
}
