//
//  EmailAuthView.swift
//  FootballScanningAI
//
//  Email/password sign in and sign up. On success, ensures a first player exists (auto from account identity) then Home.
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
    @State private var isCheckingPlayers = false
    /// Only set after a login/signup attempt fails; cleared when user edits email or password.
    @State private var attemptError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("VisionPlay")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)
                Text("See the Game")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                Text("Sign in or create an account")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
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

    /// After auth: fetch players; if none, auto-create first player from account identity (no name form).
    private func checkExistingPlayersAndRoute() async {
        guard auth.currentSession != nil else { return }
        // Guest may have finished baseline locally without this sheet carrying twoMinuteTestResult (e.g. email login from Home).
        if twoMinuteTestResult != nil || UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey) {
            AuthFlowOnboardingSync.markLocalAndSyncRemoteCompleted()
        }
        await MainActor.run { isCheckingPlayers = true }
        defer { Task { @MainActor in isCheckingPlayers = false } }
        do {
            let list = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
            let ok = await FirstPlayerAfterAuthBootstrap.ensureFirstPlayerIfNeeded(
                remoteList: list,
                profileManager: profileManager,
                playerStore: playerStore,
                progressStore: progressStore,
                twoMinuteTestResult: twoMinuteTestResult,
                context: "email_auth"
            )
            await MainActor.run {
                if ok {
                    onComplete()
                } else {
                    attemptError = "Could not finish setting up your profile. Check your connection and try again."
                }
            }
            let refreshed = (try? await SupabasePlayerService.shared.fetchPlayersForCurrentUser()) ?? list
            await AuthFlowOnboardingSync.resolveAndApplyOnboardingStateAfterLogin(
                email: auth.currentUserEmail,
                playerList: refreshed,
                context: "email_auth",
                profileManager: profileManager
            )
        } catch {
            await MainActor.run {
                attemptError = "Could not load your players. Check your connection and try again."
            }
            print("[AuthFlow-Debug] context=email_auth fetchPlayers failed error=\(error.localizedDescription) routing=show_error (not treating as empty roster)")
        }
    }

}
