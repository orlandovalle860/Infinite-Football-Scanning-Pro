//
//  AccountPromptView.swift
//  FootballScanningAI
//
//  Shown after 2-Minute Test: Sign in with Apple or Sign in with Email to save score and track improvement.
//

import SwiftUI
import AuthenticationServices
import UIKit
import Combine

struct AccountPromptView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var playerStore: PlayerStore
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var auth = AuthManager.shared
    /// When set, the 2-min test result to save to Supabase after the user creates an account and a player.
    var twoMinuteTestResult: TwoMinuteTestResult? = nil
    /// Called when user chooses "Continue without account" → navigate to create profile (local only). Used when Supabase not configured.
    var onContinueWithoutAccount: () -> Void
    /// Called when user completes Create Account or Sign In and has created a player → dismiss / pop to root.
    var onAccountComplete: (() -> Void)? = nil

    @State private var showEmailAuth = false
    @State private var showCreatePlayerAfterAuth = false
    @State private var isAppleSignInLoading = false
    @State private var isCheckingPlayers = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Save your score and track your improvement.")
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                SignInWithAppleButtonOfficial(
                    isLoading: $isAppleSignInLoading,
                    onSuccess: { checkExistingPlayersAndRoute() }
                )

                if let error = auth.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    showEmailAuth = true
                } label: {
                    Text("Sign in with Email")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
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
        .fullScreenCover(isPresented: $showEmailAuth) {
            EmailAuthView(
                profileManager: profileManager,
                playerStore: playerStore,
                twoMinuteTestResult: twoMinuteTestResult,
                onComplete: {
                    showEmailAuth = false
                    onAccountComplete?()
                }
            )
            .environmentObject(progressStore)
        }
        .overlay {
            if isCheckingPlayers {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
        .fullScreenCover(isPresented: $showCreatePlayerAfterAuth) {
            CreatePlayerAfterAuthView(
                profileManager: profileManager,
                playerStore: playerStore,
                twoMinuteTestResult: twoMinuteTestResult,
                onComplete: {
                    showCreatePlayerAfterAuth = false
                    onAccountComplete?()
                }
            )
            .environmentObject(progressStore)
        }
    }

    /// After auth: fetch players for current user. If none → Create Player. If any → hydrate stores and go to Home.
    private func checkExistingPlayersAndRoute() {
        guard AuthManager.shared.currentSession != nil else { return }
        isCheckingPlayers = true
        Task {
            defer { Task { @MainActor in isCheckingPlayers = false } }
            do {
                let list = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
                await MainActor.run {
                    if list.isEmpty {
                        showCreatePlayerAfterAuth = true
                    } else {
                        hydrateStoresWithFetchedPlayers(list)
                        onAccountComplete?()
                    }
                }
            } catch {
                await MainActor.run {
                    showCreatePlayerAfterAuth = true
                }
            }
        }
    }

    private func hydrateStoresWithFetchedPlayers(_ list: [SupabasePlayer]) {
        let ids = list.compactMap(\.uuid)
        for p in list {
            guard let uuid = p.uuid else { continue }
            if !profileManager.profiles.contains(where: { $0.id == uuid }) {
                profileManager.addProfileById(uuid, name: p.name)
            }
            if !playerStore.players.contains(where: { $0.id == uuid }) {
                playerStore.addPlayer(id: uuid, name: p.name)
            }
        }
        SupabasePlayerService.shared.markPlayersAsSynced(ids)
        if let firstId = ids.first,
           let firstProfile = profileManager.profiles.first(where: { $0.id == firstId }) {
            profileManager.switchToProfile(firstProfile)
            playerStore.selectedPlayerId = firstId
            playerStore.persist()
        }
    }
}

/// Coordinator so Sign in with Apple has an explicit presentation context (fixes no-op on iPad).
private final class SignInWithAppleCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let window: UIWindow
    let onResult: (Result<ASAuthorization, Error>) -> Void

    init(window: UIWindow, onResult: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.window = window
        self.onResult = onResult
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onResult(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onResult(.failure(error))
    }
}

/// Official Sign in with Apple button (ASAuthorizationAppleIDButton) with explicit presentation context for iPad.
private struct SignInWithAppleButtonOfficial: View {
    @Binding var isLoading: Bool
    var onSuccess: () -> Void

    var body: some View {
        SignInWithAppleButtonRepresentable(isLoading: $isLoading, onSuccess: onSuccess)
            .frame(height: 50)
            .frame(maxWidth: 320)
            .disabled(isLoading)
    }
}

/// UIKit wrapper for ASAuthorizationAppleIDButton. On tap, performs request with coordinator so iPad gets a valid presentation anchor.
private struct SignInWithAppleButtonRepresentable: UIViewRepresentable {
    @Binding var isLoading: Bool
    var onSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, onSuccess: onSuccess)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleTap(_:)), for: .touchUpInside)
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.containerView = container
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.loadingBinding = $isLoading
        context.coordinator.onSuccess = onSuccess
    }

    final class Coordinator: NSObject {
        weak var containerView: UIView?
        var loadingBinding: Binding<Bool>?
        var onSuccess: (() -> Void)?
        var authCoordinator: SignInWithAppleCoordinator?

        init(isLoading: Binding<Bool>, onSuccess: @escaping () -> Void) {
            self.loadingBinding = isLoading
            self.onSuccess = onSuccess
        }

        @objc func handleTap(_ sender: Any) {
            guard let container = containerView, let window = container.window else {
                AuthManager.shared.lastError = "Could not find window. Try again."
                return
            }
            loadingBinding?.wrappedValue = true
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            AuthManager.shared.handleAppleRequest(request)
            authCoordinator = SignInWithAppleCoordinator(window: window) { [weak self] result in
                Task {
                    await AuthManager.shared.handleAppleCompletion(result)
                    await MainActor.run {
                        self?.authCoordinator = nil
                        self?.loadingBinding?.wrappedValue = false
                        if AuthManager.shared.currentSession != nil {
                            self?.onSuccess?()
                        }
                    }
                }
            }
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = authCoordinator
            controller.presentationContextProvider = authCoordinator
            controller.performRequests()
        }
    }
}

/// Login as sheet: email, password, Create Account or Sign In.
private struct LoginViewSheet: View {
    @Binding var createAccount: Bool
    let onSuccess: () -> Void
    let onDismiss: () -> Void

    @ObservedObject private var auth = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .padding(14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding(14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                if let error = auth.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    isLoading = true
                    if createAccount {
                        Task {
                            await auth.signUp(email: email, password: password)
                            await MainActor.run {
                                isLoading = false
                                if auth.currentSession != nil { onSuccess() }
                            }
                        }
                    } else {
                        Task {
                            await auth.signIn(email: email, password: password)
                            await MainActor.run {
                                isLoading = false
                                if auth.currentSession != nil { onSuccess() }
                            }
                        }
                    }
                } label: {
                    HStack {
                        if isLoading { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)) }
                        Text(createAccount ? "Create Account" : "Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || isLoading)

                Button {
                    createAccount.toggle()
                } label: {
                    Text(createAccount ? "Already have an account? Sign in" : "Need an account? Create one")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .navigationTitle(createAccount ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }
}

/// Create Player Profile: shown only after authentication. Inserts into Supabase players (user_id, name, age, team, position) then navigates to Home.
/// If twoMinuteTestResult is set, saves that test session to Supabase and local progress after creating the player.
struct CreatePlayerAfterAuthView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var playerStore: PlayerStore
    var twoMinuteTestResult: TwoMinuteTestResult? = nil
    var onComplete: () -> Void
    @EnvironmentObject private var progressStore: ProgressStore
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false

    @State private var playerName = ""
    @State private var ageText = ""
    @State private var team = ""
    @State private var position = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, age, team, position
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Create Player Profile")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                Text("Enter the player's details. Name is required.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 12) {
                    TextField("Name", text: $playerName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .padding(14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .age)
                        .padding(14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    TextField("Team", text: $team)
                        .focused($focusedField, equals: .team)
                        .padding(14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    TextField("Position", text: $position)
                        .focused($focusedField, equals: .position)
                        .padding(14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button {
                    saveProfile()
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
            }
            .padding(24)
            .navigationTitle("Player profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { focusedField = .name }
    }

    private var canSave: Bool {
        !playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveProfile() {
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard AuthManager.shared.currentUserId != nil else {
            errorMessage = "You must be signed in to create a player."
            return
        }
        errorMessage = nil
        isLoading = true
        let enteredAge = Int(ageText.trimmingCharacters(in: .whitespacesAndNewlines))
        let enteredTeam = team.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredPosition = position.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let existing = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
                if let first = existing.first, let existingId = first.uuid {
                    await MainActor.run {
                        hydrateWithPlayer(id: existingId, name: first.name)
                        isLoading = false
                        onComplete()
                    }
                    return
                }
                let playerId = UUID()
                try await SupabasePlayerService.shared.insertPlayer(
                    id: playerId,
                    name: name,
                    age: enteredAge,
                    team: enteredTeam.isEmpty ? nil : enteredTeam,
                    position: enteredPosition.isEmpty ? nil : enteredPosition
                )
                await MainActor.run {
                    profileManager.addProfileWithId(playerId, name: name)
                    playerStore.addPlayer(id: playerId, name: name)
                    playerStore.selectedPlayerId = playerId
                    playerStore.persist()
                    hasCompletedInitialTest = true
                    saveTwoMinuteTestSessionIfNeeded(playerId: playerId)
                    AnalyticsManager.shared.track(.playerCreated, playerId: playerId)
                    isLoading = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
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
        let speedBucket: SpeedBucket = {
            let (f, m, s) = (result.fastCount, result.mediumCount, result.slowCount)
            if f >= m && f >= s { return .fast }
            if s >= f && s >= m { return .slow }
            return .medium
        }()
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
