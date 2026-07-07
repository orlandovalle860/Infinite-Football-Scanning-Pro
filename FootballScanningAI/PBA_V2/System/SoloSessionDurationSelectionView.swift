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
        HStack(spacing: 12) {
            timerLabel
            if let onEnd = onLongPressEnd {
                Button(action: onEnd) {
                    Text("End")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End session")
            }
        }
        .frame(maxWidth: .infinity)
        .safeAreaPadding(.top, 8)
    }

    private var timerLabel: some View {
        Text(text)
            .font(.subheadline.monospacedDigit().weight(.medium))
            .foregroundColor(.white.opacity(0.62))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 1.2) {
                onLongPressEnd?()
            }
            .accessibilityLabel("Session time \(text)")
            .accessibilityHint(onLongPressEnd == nil ? "" : "Long press to end session")
    }
}

extension View {
    /// Top-center solo session timer; layered above drill tap targets so Free Play End is tappable.
    @ViewBuilder
    func soloSessionTimerOverlay(
        isVisible: Bool,
        text: String,
        onFreePlayEnd: (() -> Void)?
    ) -> some View {
        overlay(alignment: .top) {
            if isVisible {
                SoloSessionTimerCornerBadge(text: text, onLongPressEnd: onFreePlayEnd)
            }
        }
    }
}
