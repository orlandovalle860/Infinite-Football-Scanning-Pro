//
//  AuthManager.swift
//  FootballScanningAI
//
//  Supabase auth: email, Sign in with Apple, sign out, session restore.
//  Session persists between launches (Supabase Swift stores it in the keychain).
//

import Foundation
import Supabase
import Combine
import AuthenticationServices

/// Manages Supabase auth state. Use shared instance; observe for UI updates.
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    /// Current Supabase session if logged in. Nil otherwise.
    @Published private(set) var currentSession: Session?

    /// Current authenticated user. Nil when not logged in.
    var currentUser: User? {
        currentSession?.user
    }

    /// Current user id (UUID) for linking players/sessions. Nil when not logged in.
    var currentUserId: UUID? {
        currentSession?.user.id
    }

    /// User-facing email of the current user, if available.
    var currentUserEmail: String? {
        currentSession?.user.email
    }

    /// Error message from last auth operation (e.g. sign in failed). Clear when starting a new operation.
    @Published var lastError: String?

    /// True until initial restoreSession() has completed. Use to avoid flashing login while restoring.
    @Published private(set) var isRestoring = true

    private var authStateTask: Task<Void, Never>?

    init() {
        // Restore session from keychain on launch.
        authStateTask = Task { @MainActor in
            await restoreSession()
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    /// Restore session from storage (keychain). Call on app launch. No-op on coach remote (non-host).
    func restoreSession() async {
        guard ConnectionManager.shared.isHost else {
            await MainActor.run { currentSession = nil; isRestoring = false }
            return
        }
        let client = SupabaseClientManager.client
        do {
            let session = try await client.auth.session
            await MainActor.run {
                currentSession = session
                lastError = nil
            }
        } catch {
            await MainActor.run {
                currentSession = nil
                // Do not set lastError: no session on restore is normal (user not logged in).
                lastError = nil
            }
        }
        await MainActor.run { isRestoring = false }
    }

    /// Sign up with email and password. No-op on coach remote (non-host).
    func signUp(email: String, password: String) async {
        guard ConnectionManager.shared.isHost else { return }
        lastError = nil
        let client = SupabaseClientManager.client
        do {
            let response = try await client.auth.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            if let session = response.session {
                await MainActor.run {
                    currentSession = session
                    lastError = nil
                    AnalyticsManager.shared.track(.accountCreated, userId: session.user.id)
                }
            } else {
                // Email confirmation required
                await MainActor.run {
                    currentSession = nil
                    lastError = "Check your email to confirm your account, then sign in."
                }
            }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
    }

    /// Sign in with email and password. No-op on coach remote (non-host).
    func signIn(email: String, password: String) async {
        guard ConnectionManager.shared.isHost else { return }
        lastError = nil
        let client = SupabaseClientManager.client
        do {
            let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            await MainActor.run {
                currentSession = session
                lastError = nil
            }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
    }

    /// Configure the Sign in with Apple request (e.g. scopes). Call from SignInWithAppleButton onRequest.
    func handleAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email, .fullName]
    }

    /// Handle Sign in with Apple completion. Call from SignInWithAppleButton onCompletion (e.g. from a Task).
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.canceled.rawValue {
                await MainActor.run { lastError = nil }
                return
            }
            await MainActor.run { lastError = error.localizedDescription }
            return
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                await MainActor.run { lastError = "Sign in with Apple did not return an identity token. Try again." }
                return
            }
            await signInWithApple(idToken: idToken)
        }
    }

    /// Sign in with Apple: pass the identity token from ASAuthorizationAppleIDCredential.
    /// Call from the view after receiving the credential from SignInWithAppleButton. No-op on coach remote (non-host).
    func signInWithApple(idToken: String, nonce: String? = nil) async {
        guard ConnectionManager.shared.isHost else { return }
        lastError = nil
        let client = SupabaseClientManager.client
        do {
            let credentials = OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce ?? ""
            )
            let session = try await client.auth.signInWithIdToken(credentials: credentials)
            await MainActor.run {
                currentSession = session
                lastError = nil
                AnalyticsManager.shared.track(.accountCreated, userId: session.user.id)
            }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
    }

    /// Sign out. Clears session; UI should switch to login. No-op on coach remote (non-host).
    func signOut() async {
        guard ConnectionManager.shared.isHost else {
            await MainActor.run { currentSession = nil; lastError = nil }
            return
        }
        let client = SupabaseClientManager.client
        do {
            try await client.auth.signOut()
        } catch {
            // Still clear local session so user can reach login again
        }
        await MainActor.run {
            currentSession = nil
            lastError = nil
        }
    }
}
