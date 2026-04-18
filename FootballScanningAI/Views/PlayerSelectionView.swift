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
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger

    @State private var showSignOutConfirmation = false
    @State private var remotePlayers: [SupabasePlayer] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showAddPlayer = false
    @State private var newPlayerName = ""

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
                ScrollView {
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
                    }
                    .padding(20)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign Out") {
                    showSignOutConfirmation = true
                }
                .foregroundColor(.white.opacity(0.9))
                .disabled(signOutUXPhase != .idle)
            }
        }
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
        .onAppear { loadPlayers() }
        .sheet(isPresented: $showAddPlayer) {
            addPlayerSheet
        }
    }

    private var addPlayerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Player name", text: $newPlayerName)
                    .textContentType(.name)
                    .padding(14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Add player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddPlayer = false
                        newPlayerName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        addNewPlayer()
                    }
                    .disabled(newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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

    private func addNewPlayer() {
        let name = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let playerId = UUID()
        Task {
            do {
                try await SupabasePlayerService.shared.insertPlayer(id: playerId, name: name)
                await MainActor.run {
                    profileManager.addProfileWithId(playerId, name: name)
                    playerStore.addPlayer(id: playerId, name: name)
                    AnalyticsManager.shared.track(.playerCreated, playerId: playerId)
                    newPlayerName = ""
                    showAddPlayer = false
                    remotePlayers.append(SupabasePlayer(id: playerId.uuidString.lowercased(), name: name, user_id: nil, created_at: ISO8601DateFormatter().string(from: Date()), age: nil, team: nil, position: nil))
                    selectPlayer(id: playerId, name: name)
                }
            } catch {
                await MainActor.run {
                    loadError = UserFacingErrorMessage.message(from: error)
                }
            }
        }
    }
}
