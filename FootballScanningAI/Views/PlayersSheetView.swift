import SwiftUI

struct PlayersSheetView: View {
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var progressStore: ProgressStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAddPlayerSheet = false
    @State private var pendingDeleteProfile: UserProfile?
    @State private var showDeleteConfirm = false
    @State private var showCannotDeleteLastPlayerAlert = false
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage = ""
    @State private var isDeletingPlayer = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Switch Player")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                Text("Choose who is training right now.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(profileManager.profiles) { profile in
                            playerRow(profile: profile)
                        }
                    }
                }

                Button {
                    showAddPlayerSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add New Player")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow.opacity(0.8), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddPlayerSheet) {
            AddPlayerView(
                profileManager: profileManager,
                playerStore: playerStore,
                allowsCancel: true,
                onCancel: { showAddPlayerSheet = false },
                onComplete: {
                    showAddPlayerSheet = false
                    dismiss()
                }
            )
            .environmentObject(progressStore)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete Player?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let profile = pendingDeleteProfile {
                    Task { await deletePlayer(profile) }
                }
                pendingDeleteProfile = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteProfile = nil
            }
        } message: {
            Text("This removes the player profile and local session history on this device.")
        }
        .alert("Can't Delete Last Player", isPresented: $showCannotDeleteLastPlayerAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add another player before deleting this one.")
        }
        .alert("Delete Failed", isPresented: $showDeleteErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
    }

    private func playerRow(profile: UserProfile) -> some View {
        let isCurrent = profileManager.currentProfile?.id == profile.id
        return HStack(spacing: 10) {
            Button {
                profileManager.switchToProfile(profile)
                playerStore.selectPlayer(id: profile.id)
                dismiss()
            } label: {
                HStack {
                    Text(profile.name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isCurrent ? .yellow : .white.opacity(0.5))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(isCurrent ? 0.14 : 0.06))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                guard !isDeletingPlayer else { return }
                guard profileManager.profiles.count > 1 else {
                    showCannotDeleteLastPlayerAlert = true
                    return
                }
                pendingDeleteProfile = profile
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.9))
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Delete \(profile.name)")
        }
    }

    private func deletePlayer(_ profile: UserProfile) async {
        guard !isDeletingPlayer else { return }
        isDeletingPlayer = true
        defer { isDeletingPlayer = false }

        #if DEBUG
        print("[PBA-Debug] Delete player requested: id=\(profile.id.uuidString), name=\(profile.name)")
        #endif

        // Remote-first delete so relaunch hydration cannot restore this player.
        if Config.isSupabaseConfigured, AuthManager.shared.currentUserId != nil {
            do {
                try await SupabasePlayerService.shared.deletePlayer(id: profile.id)
                #if DEBUG
                print("[PBA-Debug] Supabase delete success: id=\(profile.id.uuidString)")
                #endif
            } catch {
                SupabasePlayerService.shared.markPendingDelete(id: profile.id)
                #if DEBUG
                print("[PBA-Debug] Supabase delete failed: id=\(profile.id.uuidString), error=\(error.localizedDescription)")
                #endif
                deleteErrorMessage = "Cloud delete is pending retry. This player is removed on this device and will sync when your connection is back."
                showDeleteErrorAlert = true
            }
        }

        let wasSelected = playerStore.selectedPlayerId == profile.id
        progressStore.removeSessions(forPlayerId: profile.id)
        profileManager.deleteProfile(profile)
        playerStore.removePlayer(id: profile.id)
        #if DEBUG
        print("[PBA-Debug] Local delete success: id=\(profile.id.uuidString), remainingPlayers=\(playerStore.players.count)")
        #endif

        if let selectedId = playerStore.selectedPlayerId,
           let selectedProfile = profileManager.profile(id: selectedId) {
            profileManager.switchToProfile(selectedProfile)
            #if DEBUG
            print("[PBA-Debug] Selected player reassigned: newSelectedId=\(selectedId.uuidString)")
            #endif
        } else if wasSelected {
            #if DEBUG
            print("[PBA-Debug] Deleted selected player; selection cleared (no valid remaining profile).")
            #endif
        }
        if playerStore.players.isEmpty {
            dismiss()
        }
    }
}

#Preview("Players sheet") {
    PlayersSheetView(profileManager: UserProfileManager())
        .environmentObject(PlayerStore())
        .environmentObject(ProgressStore.shared)
}
