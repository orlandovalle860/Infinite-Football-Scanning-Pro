//
//  SoloSessionCompleteOverlay.swift
//  FootballScanningAI
//
//  Solo session end: minimal full-screen overlay with time, reps, and Done.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SoloSessionCompleteOverlay: View {
    let elapsedSeconds: TimeInterval
    let repCount: Int
    let onDone: () -> Void

    @State private var contentVisible = false
    @State private var highlight: SoloSessionCompletionHighlight?
    @State private var didRecordAchievement = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Text("Session complete")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)

                    VStack(spacing: 8) {
                        Text("Time: \(SoloSessionTimeFormat.mmss(elapsedSeconds))")
                        Text("Reps: \(repCount)")
                        if let highlight {
                            Text(highlight.displayText)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.55))
                                .padding(.top, 4)
                        }
                    }
                    .font(.body.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)
                .opacity(contentVisible ? 1 : 0)
                .scaleEffect(contentVisible ? 1 : 0.97)

                Spacer()

                Button(action: doneTapped) {
                    Text("Done")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(Color.yellow)
                        .cornerRadius(16)
                }
                .buttonStyle(SoloSessionCompleteDoneButtonStyle())
                .opacity(contentVisible ? 1 : 0)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .onAppear(perform: presentWithFeedback)
    }

    private func presentWithFeedback() {
        if !didRecordAchievement {
            didRecordAchievement = true
            highlight = SoloSessionAchievementStore.recordCompletion(
                elapsedSeconds: elapsedSeconds,
                repCount: repCount
            )
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.easeOut(duration: 0.32)) {
            contentVisible = true
        }
    }

    private func doneTapped() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        onDone()
    }
}

private struct SoloSessionCompleteDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Full-screen solo session complete overlay (not navigation).
    @ViewBuilder
    func soloSessionCompleteOverlay(
        isPresented: Bool,
        elapsedSeconds: TimeInterval,
        repCount: Int,
        onDone: @escaping () -> Void
    ) -> some View {
        ZStack {
            self
            if isPresented {
                SoloSessionCompleteOverlay(
                    elapsedSeconds: elapsedSeconds,
                    repCount: repCount,
                    onDone: onDone
                )
                .transition(.opacity)
                .zIndex(300)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
}

/// Backward-compatible name for any remaining references.
typealias SoloTimeBasedSessionCompleteView = SoloSessionCompleteOverlay
