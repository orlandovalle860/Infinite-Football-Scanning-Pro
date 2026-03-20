//
//  PremiumPaywallView.swift
//  FootballScanningAI
//
//  Simple v1 paywall (no StoreKit integration yet).
//

import SwiftUI

struct PremiumPaywallView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Unlock Full Curriculum")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Stage 2 and Stage 3 are part of Premium. Upgrade to access advanced decision-making activities and guided progression.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Premium includes:")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)
                Text("• Dribble or Pass (Stage 2)")
                    .foregroundColor(.white.opacity(0.9))
                Text("• One-Touch Passing (Stage 3)")
                    .foregroundColor(.white.opacity(0.9))
                Text("• Full guided curriculum progression")
                    .foregroundColor(.white.opacity(0.9))
            }
            .font(.subheadline)

            Button {
                // Placeholder for StoreKit integration; for now mark premium enabled.
                profileManager.upgradeToPremium(playerId: playerStore.selectedPlayerId)
                router.popToRoot()
            } label: {
                Text("Upgrade")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                router.popToRoot()
            } label: {
                Text("Not now")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
