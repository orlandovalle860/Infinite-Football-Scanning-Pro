//
//  PostSessionFeedbackView.swift
//  FootballScanningAI
//
//  Minimal post-session overlay — reps, streak, and longest session from tracked data only.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PostSessionFeedbackView: View {
    let repCount: Int
    let durationSeconds: TimeInterval
    var repTarget: Int? = nil
    let onDone: () -> Void

    @State private var content: PostSessionFeedbackContent?
    @State private var contentVisible = false
    @State private var streakPopScale: CGFloat = 1
    @State private var didRecordSession = false
    @State private var isDismissing = false

    private var subtitle: String {
        let reps = content?.repCount ?? repCount
        return reps == 1 ? "You completed 1 rep." : "You completed \(reps) reps."
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ResponsiveScrollScreen {
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Text("Nice work.")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(subtitle)
                            .font(.body.weight(.medium))
                            .foregroundColor(.white.opacity(0.78))
                            .multilineTextAlignment(.center)

                        if let repTarget {
                            Text("Target was \(repTarget)+ reps")
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }

                        if let content {
                            if content.isLongestSessionYet {
                                Text("Your longest session yet")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.72))
                                    .multilineTextAlignment(.center)
                            }

                            if let streakDays = content.streakDays {
                                Text("🔥 \(streakDays)-day streak")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.88))
                                    .multilineTextAlignment(.center)
                                    .scaleEffect(streakPopScale)
                            }

                            if content.showComeBackTomorrow {
                                Text("Come back tomorrow.")
                                    .font(.footnote.weight(.medium))
                                    .foregroundColor(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)
                            }

                            if content.showExtraWorkToday {
                                Text("You're putting in extra work today.")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.72))
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .scaleEffect(contentVisible ? 1 : 0.97)

                    Button(action: doneTapped) {
                        Text("Done")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.yellow)
                            .cornerRadius(16)
                    }
                    .buttonStyle(PostSessionFeedbackDoneButtonStyle())
                    .opacity(contentVisible ? 1 : 0)
                    .disabled(isDismissing)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .onAppear(perform: presentFeedback)
    }

    private func presentFeedback() {
        guard !didRecordSession else { return }
        didRecordSession = true
        content = PostSessionFeedbackStore.recordSession(
            repCount: repCount,
            durationSeconds: durationSeconds
        )
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.easeOut(duration: 0.32)) {
            contentVisible = true
        }
        if content?.streakDays != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                    streakPopScale = 1.08
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        streakPopScale = 1
                    }
                }
            }
        }
    }

    private func doneTapped() {
        guard !isDismissing else { return }
        isDismissing = true
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.easeIn(duration: 0.22)) {
            contentVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onDone()
        }
    }
}

private struct PostSessionFeedbackDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
