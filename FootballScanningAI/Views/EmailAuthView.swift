//
//  EmailAuthView.swift
//  FootballScanningAI
//
//  Email/password sign in and sign up. On success, checks for existing player; if none, presents CreatePlayerAfterAuthView; else navigates to Home.
//

import SwiftUI

struct EmailAuthView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var playerStore: PlayerStore
    @EnvironmentObject private var progressStore: ProgressStore
    /// When set, the 2-min test result to save after the user creates a player.
    var twoMinuteTestResult: TwoMinuteTestResult? = nil
    /// Called when user is authenticated and has at least one player (or after creating one) → dismiss / pop to root (Home).
    var onComplete: () -> Void

    @ObservedObject private var auth = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showCreatePlayerAfterAuth = false
    @State private var isCheckingPlayers = false
    /// Only set after a login/signup attempt fails; cleared when user edits email or password.
    @State private var attemptError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Sign in or create an account")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.top, 24)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .padding(14)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .padding(14)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
            .onChange(of: email) { _, _ in
                attemptError = nil
                auth.lastError = nil
            }
            .onChange(of: password) { _, _ in
                attemptError = nil
                auth.lastError = nil
            }

            if let error = attemptError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await createAccount() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)) }
                        Text("Create Account")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(14)
                }
                .disabled(!canSubmit || isLoading)
                .buttonStyle(PlainButtonStyle())

                Button {
                    Task { await signIn() }
                } label: {
                    Text("Sign In")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .disabled(!canSubmit || isLoading)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)

            Spacer()
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
        )
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            // Don't show stale or session-missing errors when opening the login screen.
            auth.lastError = nil
            attemptError = nil
        }
        .fullScreenCover(isPresented: $showCreatePlayerAfterAuth) {
            CreatePlayerAfterAuthView(
                profileManager: profileManager,
                playerStore: playerStore,
                twoMinuteTestResult: twoMinuteTestResult,
                onComplete: {
                    showCreatePlayerAfterAuth = false
                    onComplete()
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
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func createAccount() async {
        guard canSubmit else { return }
        focusedField = nil
        attemptError = nil
        isLoading = true
        await auth.signUp(email: email, password: password)
        await MainActor.run {
            isLoading = false
            if auth.currentSession == nil, let msg = auth.lastError {
                attemptError = msg
            }
        }
        if auth.currentSession != nil {
            await checkExistingPlayersAndRoute()
        }
    }

    private func signIn() async {
        guard canSubmit else { return }
        focusedField = nil
        attemptError = nil
        isLoading = true
        await auth.signIn(email: email, password: password)
        await MainActor.run {
            isLoading = false
            if auth.currentSession == nil, let msg = auth.lastError {
                attemptError = msg
            }
        }
        if auth.currentSession != nil {
            await checkExistingPlayersAndRoute()
        }
    }

    /// After auth: fetch players for current user. If none → Create Player. If any → hydrate stores and go to Home.
    private func checkExistingPlayersAndRoute() async {
        guard auth.currentSession != nil else { return }
        await MainActor.run { isCheckingPlayers = true }
        defer { Task { @MainActor in isCheckingPlayers = false } }
        do {
            let list = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
            await MainActor.run {
                profileManager.reconcileWithSupabasePlayerList(list, playerStore: playerStore)
                showCreatePlayerAfterAuth = profileManager.profiles.isEmpty
                if !showCreatePlayerAfterAuth {
                    onComplete()
                }
            }
        } catch {
            await MainActor.run {
                showCreatePlayerAfterAuth = true
            }
        }
    }

}
