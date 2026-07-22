//
//  AddPlayerView.swift
//  FootballScanningAI
//
//  Optional “Add a Player” for additional athletes (Players sheet / selection).
//  First player after Sign in with Apple is created automatically — do not present this as a required post-SIWA form.
//

import SwiftUI

/// Shared “Add a Player” form for adding more players later (cancelable). First player after auth uses FirstPlayerAfterAuthBootstrap.
struct AddPlayerView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var playerStore: PlayerStore
    /// When set (e.g. after 2‑Minute Test + auth), saves that session to the new player.
    var twoMinuteTestResult: TwoMinuteTestResult? = nil
    /// When true, shows Cancel in the toolbar. Prefer true for optional add-player flows.
    var allowsCancel: Bool = true
    var onCancel: (() -> Void)? = nil
    var onComplete: () -> Void
    @EnvironmentObject private var progressStore: ProgressStore

    @State private var playerName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Add a Player")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                Text("Add another athlete who will train on this account. This is separate from your Sign in with Apple account name.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Player name")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    TextField("Player name", text: $playerName)
                        .textContentType(.name)
                        .focused($nameFocused)
                        .padding(14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .accessibilityLabel("Player name")
                        .accessibilityHint("Required. Name of the athlete who will train.")
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button {
                    savePlayer()
                } label: {
                    HStack {
                        if isLoading { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)) }
                        Text("Save Profile")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSave ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!canSave || isLoading)

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Add a Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel?()
                        }
                    }
                }
            }
        }
        .onAppear { nameFocused = true }
    }

    private var canSave: Bool {
        !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func savePlayer() {
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        errorMessage = nil
        isLoading = true

        // Signed-in: persist to Supabase `players` then local stores (does not touch account-holder metadata).
        if AuthManager.shared.currentUserId != nil {
            Task { await saveSignedInPlayer(name: name) }
            return
        }

        // Guest / local-only: create locally (sync when authenticated later).
        let newProfile = profileManager.addProfile(name: name, email: nil, age: nil, team: nil, position: nil)
        playerStore.addPlayer(id: newProfile.id, name: name)
        profileManager.switchToProfile(newProfile)
        playerStore.selectPlayer(id: newProfile.id)
        AnalyticsManager.shared.track(.playerCreated, playerId: newProfile.id)
        isLoading = false
        onComplete()
    }

    private func saveSignedInPlayer(name: String) async {
        print("[AddPlayer] save signedIn name=\(name) accountHolderUnchanged=\(AuthManager.shared.accountHolderFullName ?? "nil")")
        do {
            let existing = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
            // First-player race: another device/session already created a row — hydrate, don’t invent a duplicate for empty-roster onboarding.
            if profileManager.profiles.isEmpty, playerStore.players.isEmpty,
               let first = existing.first, let existingId = first.uuid {
                await MainActor.run {
                    hydrateWithPlayer(id: existingId, name: first.name)
                    isLoading = false
                    onComplete()
                }
                await AuthFlowOnboardingSync.resolveAndApplyOnboardingStateAfterLogin(
                    email: AuthManager.shared.currentUserEmail,
                    playerList: existing,
                    context: "add_player_existing_row",
                    profileManager: profileManager
                )
                return
            }

            guard AuthManager.shared.currentUserId != nil else {
                await MainActor.run {
                    errorMessage = "You must be signed in to create a player."
                    isLoading = false
                }
                return
            }

            // New UUID for every player (first or additional) so account holder ≠ player id.
            let playerId = UUID()
            do {
                try await SupabasePlayerService.shared.insertPlayer(id: playerId, name: name)
            } catch {
                #if DEBUG
                print("[AddPlayer] insert failed: \(error)")
                #endif
                // Conflict / empty-roster race: adopt existing row if present.
                if profileManager.profiles.isEmpty, playerStore.players.isEmpty,
                   let listRetry = try? await SupabasePlayerService.shared.fetchPlayersForCurrentUser(),
                   let first = listRetry.first, let existingId = first.uuid {
                    await MainActor.run {
                        hydrateWithPlayer(id: existingId, name: first.name)
                        isLoading = false
                        onComplete()
                    }
                    await AuthFlowOnboardingSync.resolveAndApplyOnboardingStateAfterLogin(
                        email: AuthManager.shared.currentUserEmail,
                        playerList: listRetry,
                        context: "add_player_insert_conflict",
                        profileManager: profileManager
                    )
                    return
                }
                await MainActor.run {
                    errorMessage = UserFacingErrorMessage.message(from: error)
                    isLoading = false
                }
                return
            }

            await MainActor.run {
                profileManager.addProfileWithId(playerId, name: name)
                playerStore.addPlayer(id: playerId, name: name)
                playerStore.selectedPlayerId = playerId
                playerStore.persist()
                if let profile = profileManager.profile(id: playerId) {
                    profileManager.switchToProfile(profile)
                }
                AuthFlowOnboardingSync.markLocalAndSyncRemoteCompleted()
                saveTwoMinuteTestSessionIfNeeded(playerId: playerId)
                AnalyticsManager.shared.track(.playerCreated, playerId: playerId)
                isLoading = false
                onComplete()
            }
        } catch {
            await MainActor.run {
                errorMessage = UserFacingErrorMessage.message(from: error)
                isLoading = false
            }
        }
    }

    private func hydrateWithPlayer(id: UUID, name: String) {
        if !profileManager.profiles.contains(where: { $0.id == id }) {
            profileManager.addProfileWithId(id, name: name)
        }
        if !playerStore.players.contains(where: { $0.id == id }) {
            playerStore.addPlayer(id: id, name: name)
        }
        SupabasePlayerService.shared.markPlayersAsSynced([id])
        if let profile = profileManager.profiles.first(where: { $0.id == id }) {
            profileManager.switchToProfile(profile)
        }
        playerStore.selectedPlayerId = id
        playerStore.persist()
    }

    private func saveTwoMinuteTestSessionIfNeeded(playerId: UUID) {
        guard let result = twoMinuteTestResult else { return }
        let speedBucket = UniversalBlockSummaryHeadline.resolve(
            fast: result.fastCount,
            medium: result.mediumCount,
            slow: result.slowCount
        ).bucket
        let biasString = result.biasDirection?.userFacingName ?? "Balanced"
        let record = SessionRecord(
            id: UUID(),
            date: Date(),
            activity: .twoMinuteTest,
            gridSize: .fiveByFive,
            difficulty: result.difficulty,
            reps: result.totalReps,
            decisionsCompleted: result.totalReps,
            correct: result.correctCount,
            forwardCorrect: result.forwardChoiceCount,
            speedBucket: speedBucket,
            bias: biasString,
            avgLatency: result.avgDecisionTime,
            profile: nil,
            playerId: playerId
        )
        progressStore.add(record)
        SupabaseSessionService.shared.saveSession(record: record, decisions: []) {
            progressStore.markSynced(id: record.id)
        }
        let sessionResult = SessionResult(
            playerID: playerId,
            activityType: .twoMinuteTest,
            correctCount: result.correctCount,
            totalReps: result.totalReps,
            speedCounts: SessionSpeedCounts(fast: result.fastCount, medium: result.mediumCount, slow: result.slowCount),
            avgDecisionTime: result.avgDecisionTime,
            biasDirection: result.biasDirection,
            directionCounts: result.directionCounts,
            difficulty: result.difficulty,
            forwardChoiceCount: result.forwardChoiceCount,
            forwardOpportunityCount: result.forwardOpportunityCount
        )
        profileManager.addSessionResult(sessionResult)
    }
}
