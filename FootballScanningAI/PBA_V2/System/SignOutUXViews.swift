//
//  SignOutUXViews.swift
//  FootballScanningAI
//
//  Loading + success feedback for account sign-out (UX only; core logic stays in AccountSignOutService).
//

import SwiftUI

enum SignOutUXPhase: Equatable {
    case idle
    case loading
    case success
}

/// Full-screen dimming overlay with signing-out spinner or brief success state.
struct SignOutUXBlockingOverlay: View {
    let phase: SignOutUXPhase

    var body: some View {
        if phase != .idle {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    if phase == .loading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.25)
                        Text("Signing out...")
                            .font(.headline)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(Color.green.opacity(0.92))
                        Text("Signed out successfully")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .allowsHitTesting(true)
            .transition(.opacity)
            .zIndex(999)
        }
    }
}

@MainActor
enum SignOutUXRunner {
    /// Runs `AccountSignOutService.performSignOut` with loading/success overlays. Guards against re-entrancy.
    static func run(
        phase: Binding<SignOutUXPhase>,
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore,
        router: AppRouter
    ) async {
        guard phase.wrappedValue == .idle else {
            print("[SignOut-UX] duplicate sign-out ignored; phase=\(phase.wrappedValue)")
            return
        }
        phase.wrappedValue = .loading
        print("[SignOut-UX] loading state shown")
        print("[SignOut-UX] sign-out started")
        await AccountSignOutService.performSignOut(
            profileManager: profileManager,
            playerStore: playerStore,
            progressStore: progressStore,
            router: router
        )
        print("[SignOut-UX] sign-out completed")
        print("[SignOut-UX] routing triggered")
        phase.wrappedValue = .success
        print("[SignOut-UX] success message shown")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        phase.wrappedValue = .idle
        print("[SignOut-UX] sign-out UX overlay dismissed")
    }
}
