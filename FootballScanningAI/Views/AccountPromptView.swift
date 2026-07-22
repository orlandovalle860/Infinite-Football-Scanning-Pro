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
    }

    /// After auth: fetch players; if none, auto-create first player from Apple/account identity (no name/email form).
    private func checkExistingPlayersAndRoute() {
        guard AuthManager.shared.currentSession != nil else { return }
        // Guest may have completed baseline locally; sync flag + metadata even when twoMinuteTestResult isn't passed through.
        if twoMinuteTestResult != nil || UserDefaults.standard.bool(forKey: hasCompletedInitialTestKey) {
            AuthFlowOnboardingSync.markLocalAndSyncRemoteCompleted()
        }
        isCheckingPlayers = true
        Task {
            defer { Task { @MainActor in isCheckingPlayers = false } }
            do {
                let list = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
                let ok = await FirstPlayerAfterAuthBootstrap.ensureFirstPlayerIfNeeded(
                    remoteList: list,
                    profileManager: profileManager,
                    playerStore: playerStore,
                    progressStore: progressStore,
                    twoMinuteTestResult: twoMinuteTestResult,
                    context: "apple_auth"
                )
                await MainActor.run {
                    if ok {
                        onAccountComplete?()
                    } else {
                        auth.lastError = "Could not finish setting up your profile. Check your connection and try again."
                    }
                }
                let refreshed = (try? await SupabasePlayerService.shared.fetchPlayersForCurrentUser()) ?? list
                await AuthFlowOnboardingSync.resolveAndApplyOnboardingStateAfterLogin(
                    email: AuthManager.shared.currentUserEmail,
                    playerList: refreshed,
                    context: "apple_auth",
                    profileManager: profileManager
                )
            } catch {
                await MainActor.run {
                    auth.lastError = "Could not load your players. Check your connection and try again."
                }
                print("[AuthFlow-Debug] context=apple_auth fetchPlayers failed error=\(error.localizedDescription) routing=show_error (not treating as empty roster)")
            }
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

