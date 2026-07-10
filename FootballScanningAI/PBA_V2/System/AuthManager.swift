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
import CryptoKit

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
    /// Raw nonce for the current Sign in with Apple request. Set in handleAppleRequest, consumed in handleAppleCompletion, then cleared.
    private var currentAppleSignInNonce: String?

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
        enum RestoreOutcome {
            case finished
            case timedOut
        }
        let outcome = await withTaskGroup(of: RestoreOutcome.self) { group in
            group.addTask { @MainActor in
                do {
                    let session = try await client.auth.session
                    self.currentSession = session
                    self.lastError = nil
                } catch {
                    self.currentSession = nil
                    self.lastError = nil
                }
                return .finished
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
        if outcome == .timedOut {
            await MainActor.run { currentSession = nil }
        }
        await MainActor.run { isRestoring = false }
    }

    /// Reloads the current session from the Supabase client (e.g. after `auth.update` or to refresh JWT user_metadata).
    /// Not gated on Multipeer role — account state must load on every device.
    func refreshSessionFromSupabase() async {
        let client = SupabaseClientManager.client
        do {
            let session = try await client.auth.refreshSession()
            await MainActor.run { currentSession = session }
            return
        } catch {
            // e.g. missing refresh token — fall back to reading stored session
        }
        do {
            let session = try await client.auth.session
            await MainActor.run { currentSession = session }
        } catch {
            // Keep existing session; caller may log.
        }
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
                print("[AuthFlow-Debug] auth operation=signUp email=\(email.trimmingCharacters(in: .whitespacesAndNewlines)) auth.uid=\(session.user.id.uuidString.lowercased())")
            } else {
                // Email confirmation required
                await MainActor.run {
                    currentSession = nil
                    lastError = "Check your email to confirm your account, then sign in."
                }
            }
        } catch {
            await MainActor.run { lastError = UserFacingErrorMessage.message(from: error) }
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
            print("[AuthFlow-Debug] auth operation=signInWithPassword email=\(email.trimmingCharacters(in: .whitespacesAndNewlines)) auth.uid=\(session.user.id.uuidString.lowercased())")
        } catch {
            await MainActor.run { lastError = UserFacingErrorMessage.message(from: error) }
        }
    }

    /// Configure the Sign in with Apple request: generate and set nonce, set scopes. Call from SignInWithAppleButton onRequest or before ASAuthorizationController.performRequests().
    func handleAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let rawNonce = Self.randomNonceString()
        currentAppleSignInNonce = rawNonce
        request.nonce = Self.sha256Nonce(rawNonce)
        request.requestedScopes = [.email, .fullName]
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func sha256Nonce(_ rawNonce: String) -> String {
        let data = Data(rawNonce.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
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
            await MainActor.run { lastError = UserFacingErrorMessage.message(from: error) }
            return
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                await MainActor.run { lastError = "Sign in with Apple did not return an identity token. Try again." }
                return
            }
            let nonceToUse = currentAppleSignInNonce
            await MainActor.run { currentAppleSignInNonce = nil }
            await signInWithApple(idToken: idToken, nonce: nonceToUse)
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
            print("[AuthFlow-Debug] auth operation=signInWithApple auth.uid=\(session.user.id.uuidString.lowercased()) email=\(session.user.email ?? "nil")")
        } catch {
            await MainActor.run { lastError = UserFacingErrorMessage.message(from: error) }
        }
    }

    /// Sign out. Clears Supabase session from keychain and local state so another account can sign in.
    func signOut() async {
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

    /// Permanently deletes the authenticated Supabase user via `delete_user` RPC, then clears local session.
    /// Requires `SupabaseDeleteUserRpc.sql` deployed in the Supabase project (see that file).
    func deleteAccount() async -> Bool {
        guard ConnectionManager.shared.isHost else { return false }
        guard let session = currentSession else { return false }
        let client = SupabaseClientManager.client
        do {
            try await client.rpc("delete_user").execute()
            await MainActor.run {
                currentSession = nil
                lastError = nil
            }
            print("[AuthFlow-Debug] auth operation=deleteAccount rpc=delete_user success userId=\(session.user.id.uuidString.lowercased())")
            return true
        } catch {
            await MainActor.run { lastError = UserFacingErrorMessage.message(from: error) }
            print("[AuthFlow-Debug] auth operation=deleteAccount rpc=delete_user failed error=\(error.localizedDescription)")
            return false
        }
    }
}
