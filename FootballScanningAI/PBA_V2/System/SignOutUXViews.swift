//
//  SignOutUXViews.swift
//  FootballScanningAI
//
//  Loading + success feedback for account sign-out / delete (UX only; core logic stays in services).
//

import SwiftUI

enum SignOutUXPhase: Equatable {
    case idle
    case loading
    case deleting
    case success
}

/// Full-screen dimming overlay with signing-out / deleting spinner or brief success state.
struct SignOutUXBlockingOverlay: View {
    let phase: SignOutUXPhase

    var body: some View {
        if phase != .idle {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    switch phase {
                    case .loading:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.25)
                        Text("Signing out...")
                            .font(.headline)
                            .foregroundColor(.white)
                    case .deleting:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.25)
                        Text("Deleting account...")
                            .font(.headline)
                            .foregroundColor(.white)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(Color.green.opacity(0.92))
                        Text("Signed out successfully")
                            .font(.headline)
                            .foregroundColor(.white)
                    case .idle:
                        EmptyView()
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

    /// Runs account deletion with a blocking “Deleting account...” overlay so the button doesn’t look dead.
    static func runDeleteAccount(
        phase: Binding<SignOutUXPhase>,
        profileManager: UserProfileManager,
        playerStore: PlayerStore,
        progressStore: ProgressStore,
        router: AppRouter
    ) async -> Bool {
        guard phase.wrappedValue == .idle else {
            print("[AccountDeletion-UX] duplicate delete ignored; phase=\(phase.wrappedValue)")
            return false
        }
        phase.wrappedValue = .deleting
        print("[AccountDeletion-UX] deleting overlay shown")
        let deleted = await AccountDeletionService.performAccountDeletion(
            profileManager: profileManager,
            playerStore: playerStore,
            progressStore: progressStore,
            router: router
        )
        phase.wrappedValue = .idle
        print("[AccountDeletion-UX] delete finished authDeleted=\(deleted)")
        return deleted
    }
}
