//
//  PremiumPaywallView.swift
//  FootballScanningAI
//
//  V1 placeholder — monetization disabled for App Store launch. Restore StoreKit UI here later.
//

import SwiftUI

struct PremiumPaywallView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Train now. Track your progress with cloud sync coming soon.")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
