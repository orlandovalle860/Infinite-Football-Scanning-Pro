//
//  FirstSessionLoginPromptView.swift
//  FootballScanningAI
//
//  Post-first-session overlay: optional Sign in with Apple to save progress.
//

import SwiftUI
import AuthenticationServices

struct FirstSessionLoginPromptView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var playerStore: PlayerStore
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var auth = AuthManager.shared
    var onAuthenticated: () -> Void
    var onNotNow: () -> Void

    @State private var isAppleSignInLoading = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Nice work.")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)

                Text("You just completed your first session.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.center)

                Text("Save your progress?")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 4)

                SignInWithAppleButton(
                    .continue,
                    onRequest: { request in
                        AuthManager.shared.handleAppleRequest(request)
                    },
                    onCompletion: { result in
                        isAppleSignInLoading = true
                        Task {
                            await AuthManager.shared.handleAppleCompletion(result)
                            await MainActor.run {
                                isAppleSignInLoading = false
                                if auth.currentSession != nil {
                                    onAuthenticated()
                                }
                            }
                        }
                    }
                )
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .cornerRadius(10)
                .signInWithAppleButtonStyle(.white)
                .disabled(isAppleSignInLoading)
                .padding(.top, 8)

                if let error = auth.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }

                Button(action: onNotNow) {
                    Text("Not now")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
        }
        .onAppear {
            auth.lastError = nil
            FirstSessionOnboardingStore.recordLoginPromptPresented()
        }
    }
}
