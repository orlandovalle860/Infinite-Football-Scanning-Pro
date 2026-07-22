//
//  PlayerSelectionView.swift
//  FootballScanningAI
//
//  When logged in: list players from Supabase (where user_id = auth.uid()), select or add.
//

import SwiftUI

struct PlayerSelectionView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var playerStore: PlayerStore
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var router: AppRouter
    @Binding var signOutUXPhase: SignOutUXPhase
    @ObservedObject private var authManager = AuthManager.shared
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger

    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteAccountFailureAlert = false
    @State private var remotePlayers: [SupabasePlayer] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showAddPlayer = false

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    Text("Loading players…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                VStack(spacing: 12) {
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                    Button("Retry") { loadPlayers() }
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResponsiveScrollScreen(horizontalPadding: 20, maxContentWidth: 520) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select a player")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Your players are synced to your account.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))

                        ForEach(remotePlayers) { p in
                            if let uuid = p.uuid {
                                Button {
                                    selectPlayer(id: uuid, name: p.name)
                                } label: {
                                    HStack {
                                        Text(p.name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(16)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        Button {
                            showAddPlayer = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add player")
                                    .font(.headline)
                            }
                            .foregroundColor(.yellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        signedInAccountActions
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Players")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                print("[SignOut-UX] sign-out confirm tapped")
                Task {
                    await SignOutUXRunner.run(
                        phase: $signOutUXPhase,
                        profileManager: profileManager,
                        playerStore: playerStore,
                        progressStore: progressStore,
                        router: router
                    )
                }
            }
        } message: {
            Text("You’ll return to the sign-in screen and can use a different account.")
        }
        .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                performDeleteAccount()
            }
        } message: {
            Text("This permanently deletes your VisionPlay account and signs you out. Apple may email you that Sign in with Apple was removed for this app. This cannot be undone.")
        }
        .alert("Delete Account", isPresented: $showDeleteAccountFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn't delete your account right now. You've been signed out. Try again or contact orlandovalle860@gmail.com.")
        }
        .onAppear { loadPlayers() }
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerView(
                profileManager: profileManager,
                playerStore: playerStore,
                allowsCancel: true,
                onCancel: { showAddPlayer = false },
                onComplete: {
                    showAddPlayer = false
                    loadPlayers()
                }
            )
            .environmentObject(progressStore)
        }
    }

    @ViewBuilder
    private var signedInAccountActions: some View {
        if authManager.currentSession != nil {
            VStack(spacing: 14) {
                Button("Sign Out") {
                    showSignOutConfirmation = true
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
                .disabled(signOutUXPhase != .idle)

                Button("Delete Account") {
                    showDeleteAccountConfirmation = true
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.red.opacity(0.92))
                .disabled(signOutUXPhase != .idle)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        }
    }

    private func performDeleteAccount() {
        guard signOutUXPhase == .idle else { return }
        Task {
            let deleted = await AccountDeletionService.performAccountDeletion(
                profileManager: profileManager,
                playerStore: playerStore,
                progressStore: progressStore,
                router: router
            )
            if !deleted {
                showDeleteAccountFailureAlert = true
            }
        }
    }

    private func loadPlayers() {
        isLoading = true
        loadError = nil
        Task {
            do {
                let list = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
                await MainActor.run {
                    remotePlayers = list
                    syncRemotePlayersToLocal(list)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = UserFacingErrorMessage.message(from: error)
                    isLoading = false
                }
            }
        }
    }

    /// Ensure each remote player exists in profileManager and playerStore.
    private func syncRemotePlayersToLocal(_ list: [SupabasePlayer]) {
        for p in list {
            guard let uuid = p.uuid else { continue }
            if !profileManager.profiles.contains(where: { $0.id == uuid }) {
                profileManager.addProfileWithId(uuid, name: p.name)
            }
            if !playerStore.players.contains(where: { $0.id == uuid }) {
                playerStore.addPlayer(id: uuid, name: p.name)
            }
        }
    }

    private func selectPlayer(id: UUID, name: String) {
        if let profile = profileManager.profiles.first(where: { $0.id == id }) {
            profileManager.switchToProfile(profile)
        }
        if playerStore.players.contains(where: { $0.id == id }) {
            playerStore.selectPlayer(id: id)
        }
        playerStore.persist()
        // Root will re-render and show Home when selectedPlayerId is set
    }
}
