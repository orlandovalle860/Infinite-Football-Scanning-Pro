//
//  TwoMinuteOnboardingView.swift
//  FootballScanningAI
//
//  PBA V2 — One-time onboarding for 2-minute test setup.
//

import SwiftUI

struct TwoMinuteOnboardingView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Decision-making before the ball arrives.")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                bullet("You'll hear a beep, then the ball is played.")
                bullet("A cue appears briefly—catch it on your last shoulder check.")
                bullet("Your first touch must match what you saw.")
            }
            .padding(.horizontal)

            Spacer(minLength: 20)

            Button {
                onDismiss()
            } label: {
                Text("Got it")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.yellow)
            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}
