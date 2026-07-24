//
//  VisionPlayGuideWelcomeSheet.swift
//  FootballScanningAI
//
//  Soft first-launch introduction to the Guide — optional, never forces training delay.
//

import SwiftUI

struct VisionPlayGuideWelcomeSheet: View {
    let onViewGuide: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 20) {
                Text("Welcome to VisionPlay")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Take two minutes to learn how VisionPlay works and get the most out of your first training session.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            Spacer(minLength: 36)

            VStack(spacing: 14) {
                Button(action: onViewGuide) {
                    Text("Open Guide")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Guide")

                Button(action: onSkip) {
                    Text("Skip for Now")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.70))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip for Now")
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
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
        .interactiveDismissDisabled(true)
    }
}
