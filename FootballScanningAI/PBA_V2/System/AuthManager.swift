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
import UIKit
import ObjectiveC

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

    /// Account-holder display name from Sign in with Apple (auth `user_metadata.full_name`), not a player profile name.
    /// One account may own many `public.players` rows; this value must not be auto-copied into `players.name`.
    var accountHolderFullName: String? {
        if let meta = Self.fullNameFromUserMetadata(currentSession?.user) {
            return meta
        }
        if let cached = lastAppleProvidedFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !cached.isEmpty {
            return cached
        }
        return nil
    }

    /// Matches `auth.users.raw_user_meta_data` key for the authenticated Apple account holder’s name.
    static let fullNameMetadataKey = "full_name"

    /// Error message from last auth operation (e.g. sign in failed). Clear when starting a new operation.
    @Published var lastError: String?

    /// True until initial restoreSession() has completed. Use to avoid flashing login while restoring.
    @Published private(set) var isRestoring = true

    private var authStateTask: Task<Void, Never>?
    /// Raw nonce for the current Sign in with Apple request. Set in handleAppleRequest, consumed in handleAppleCompletion, then cleared.
    private var currentAppleSignInNonce: String?
    /// Full name from the most recent Apple credential (first authorization only). Account-holder cache only — never auto-applied to player profiles.
    private var lastAppleProvidedFullName: String?

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
    /// Captures `fullName` on first authorization (Apple only returns it once) and persists it to Supabase `user_metadata`.
    /// Never clears an existing saved name when Apple returns nil/empty on a later sign-in.
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
            // Apple provides fullName only on the first authorization — capture immediately.
            let appleFullName = Self.displayName(from: credential.fullName)
            let appleEmail = credential.email
            let authorizationCode: String? = {
                guard let data = credential.authorizationCode else { return nil }
                return String(data: data, encoding: .utf8)
            }()
            print("[SIWA-Name] appleReturnedFullName=\(appleFullName != nil) value=\(appleFullName ?? "nil") appleReturnedEmail=\(appleEmail != nil) email=\(appleEmail ?? "nil") authorizationCode=\(authorizationCode != nil)")
            let nonceToUse = currentAppleSignInNonce
            await MainActor.run { currentAppleSignInNonce = nil }
            await signInWithApple(
                idToken: idToken,
                nonce: nonceToUse,
                fullName: appleFullName,
                authorizationCode: authorizationCode
            )
        }
    }

    /// Sign in with Apple: pass the identity token from ASAuthorizationAppleIDCredential.
    /// When `fullName` is present (first auth), saves it to auth `user_metadata.full_name` as the **account holder** name only.
    /// Does not create or update `public.players` rows. If Apple omitted the name, existing metadata is left untouched.
    /// When `authorizationCode` is present, best-effort stores an Apple refresh token via Edge Function for later revocation on account delete.
    /// Call from the view after receiving the credential from SignInWithAppleButton. No-op on coach remote (non-host).
    func signInWithApple(
        idToken: String,
        nonce: String? = nil,
        fullName: String? = nil,
        authorizationCode: String? = nil
    ) async {
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
            let existingSaved = Self.fullNameFromUserMetadata(session.user)
            print("[SIWA-Name] signInOK auth.uid=\(session.user.id.uuidString.lowercased()) email=\(session.user.email ?? "nil") appleFullName=\(fullName ?? "nil") existingSavedFullName=\(existingSaved ?? "nil")")
            if let fullName, !fullName.isEmpty {
                await MainActor.run { lastAppleProvidedFullName = fullName }
                let saved = await persistFullNameToUserMetadata(fullName)
                print("[SIWA-Name] persistAfterAppleName success=\(saved) name=\(fullName)")
            } else {
                // Do not overwrite — Apple omitted the name on this authorization.
                print("[SIWA-Name] skipPersist appleNameEmptyOrNil=true keptExisting=\(existingSaved ?? "nil")")
            }
            if let authorizationCode, !authorizationCode.isEmpty {
                await storeAppleRefreshToken(authorizationCode: authorizationCode)
            }
        } catch {
            print("[SIWA-Name] signInFailed error=\(error.localizedDescription)")
            await MainActor.run { lastError = UserFacingErrorMessage.message(from: error) }
        }
    }

    /// Best-effort: exchange Apple authorization code for refresh token and store on user_metadata (Edge Function `store-apple-token`).
    private func storeAppleRefreshToken(authorizationCode: String) async {
        let client = SupabaseClientManager.client
        do {
            // Encode as Data (not a Decodable/Encodable type) to avoid MainActor isolation issues
            // under SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor with concurrent functions.invoke.
            let body = try JSONSerialization.data(
                withJSONObject: ["authorizationCode": authorizationCode]
            )
            try await client.functions.invoke(
                "store-apple-token",
                options: FunctionInvokeOptions(body: body)
            )
            print("[SIWA-Revoke] store-apple-token OK")
        } catch {
            // Function may be undeployed or Apple secrets missing — account still works; delete will fall back / retry revoke.
            var detail = error.localizedDescription
            if let functionsError = error as? FunctionsError,
               case let .httpError(code, data) = functionsError {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
                detail = "status=\(code) body=\(body)"
            }
            print("[SIWA-Revoke] store-apple-token failed \(detail)")
        }
    }

    /// Optional: presents Sign in with Apple for a **fresh** authorization code (TN3194).
    /// Not used by the default delete flow — that revokes via `apple_refresh_token` from `store-apple-token`
    /// so users are not shown a “Sign in” sheet while deleting. Kept for manual/fallback use.
    /// Returns nil if the user cancels or the sheet cannot be presented.
    @MainActor
    func requestAppleAuthorizationCodeForAccountDeletion() async -> String? {
        guard let window = Self.keyWindowForAppleAuth() else {
            print("[AccountDeletion] Apple auth code skipped — no key window")
            return nil
        }
        return await withCheckedContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            // Revoke only needs a fresh authorization code; do not request name/email again.
            request.requestedScopes = []

            let coordinator = AppleAuthorizationCodeCoordinator(window: window) { result in
                switch result {
                case .success(let authorization):
                    let code: String? = {
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let data = credential.authorizationCode,
                              let s = String(data: data, encoding: .utf8),
                              !s.isEmpty else { return nil }
                        return s
                    }()
                    print("[AccountDeletion] Apple auth code for revoke obtained=\(code != nil)")
                    continuation.resume(returning: code)
                case .failure(let error):
                    let ns = error as NSError
                    if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.canceled.rawValue {
                        print("[AccountDeletion] Apple auth code canceled by user — delete continues without fresh code")
                    } else {
                        print("[AccountDeletion] Apple auth code failed error=\(error.localizedDescription)")
                    }
                    continuation.resume(returning: nil)
                }
            }
            // Retain coordinator for the lifetime of the controller callback.
            objc_setAssociatedObject(request, &AppleAuthorizationCodeCoordinator.assocKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        }
    }

    @MainActor
    private static func keyWindowForAppleAuth() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    /// Formats Apple `PersonNameComponents` into a non-empty display name, or nil if Apple provided nothing usable.
    static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.isEmpty { return formatted }
        let parts = [components.givenName, components.middleName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// Reads the saved **account-holder** display name from auth `user_metadata` (set on first Sign in with Apple).
    /// This is not a player profile name.
    static func fullNameFromUserMetadata(_ user: User?) -> String? {
        guard let meta = user?.userMetadata else { return nil }
        for key in [fullNameMetadataKey, "name", "fullName"] {
            if let value = stringMetadata(meta[key]) {
                return value
            }
        }
        let given = stringMetadata(meta["given_name"]) ?? stringMetadata(meta["givenName"])
        let family = stringMetadata(meta["family_name"]) ?? stringMetadata(meta["familyName"])
        let parts = [given, family].compactMap { $0 }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func stringMetadata(_ value: AnyJSON?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        default:
            return nil
        }
    }

    /// Persists a non-empty **account-holder** name to `auth.users.raw_user_meta_data.full_name` (merges; does not wipe other keys).
    /// Refuses empty/nil input so an empty Apple name can never clear an existing account-holder name.
    /// Does not write to `public.players`.
    @discardableResult
    func persistFullNameToUserMetadata(_ fullName: String) async -> Bool {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[SIWA-Name] persistSkipped reason=emptyName refusedOverwrite=true")
            return false
        }
        guard currentUserId != nil else {
            print("[SIWA-Name] persistSkipped reason=noAuthUid")
            return false
        }
        // Compare against stored metadata only (not the in-memory Apple cache).
        if Self.fullNameFromUserMetadata(currentSession?.user) == trimmed {
            print("[SIWA-Name] persistSkipped reason=alreadyMatches existing=\(trimmed)")
            return true
        }
        let client = SupabaseClientManager.client
        do {
            _ = try await client.auth.update(
                user: UserAttributes(data: [Self.fullNameMetadataKey: .string(trimmed)])
            )
            // AuthClient already merges the updated user into its session store.
            if let session = try? await client.auth.session {
                await MainActor.run { currentSession = session }
            } else {
                await refreshSessionFromSupabase()
            }
            print("[SIWA-Name] persistOK field=auth.users.raw_user_meta_data.full_name value=\(trimmed)")
            return true
        } catch {
            print("[SIWA-Name] persistFailed error=\(error.localizedDescription)")
            return false
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
            lastAppleProvidedFullName = nil
        }
    }

    /// Deletes the account: prefers Edge Function `delete-account` (Apple token revoke + players/history + auth user),
    /// then falls back to `rpc("delete_user")` which deletes players/history + auth user.
    /// Local sign-out / navigation are handled by ``AccountDeletionService``.
    /// - Parameter appleAuthorizationCode: Optional fresh SIWA authorization code for Apple token revocation (TN3194).
    func deleteAccount(appleAuthorizationCode: String? = nil) async -> Bool {
        guard let session = currentSession else {
            print("[AuthFlow-Debug] auth operation=deleteAccount skipped — no session")
            return false
        }
        let client = SupabaseClientManager.client
        let uid = session.user.id.uuidString.lowercased()

        // Prefer Edge Function: Apple /auth/revoke + delete players/sessions + auth user.
        // Body is raw Data — no custom Decodable/Encodable types (avoids Swift 6 MainActor isolation errors).
        // Bound the invoke so a hung Edge Function can’t leave Delete Account looking dead forever.
        do {
            var payload: [String: Any] = [:]
            if let appleAuthorizationCode {
                payload["authorizationCode"] = appleAuthorizationCode
            }
            let body = try JSONSerialization.data(withJSONObject: payload)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await client.functions.invoke(
                        "delete-account",
                        options: FunctionInvokeOptions(body: body)
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 25_000_000_000)
                    throw CancellationError()
                }
                try await group.next()!
                group.cancelAll()
            }
            print("[AuthFlow-Debug] delete-account OK uid=\(uid)")
            return true
        } catch {
            print("[AuthFlow-Debug] delete-account Edge Function failed error=\(error.localizedDescription) — falling back to rpc(delete_user)")
        }

        // Fallback: SQL rpc deletes players + related history + auth.users (Apple revoke only via Edge Function).
        do {
            try await client.rpc("delete_user").execute()
            print("[AuthFlow-Debug] auth operation=deleteAccount rpc=delete_user success userId=\(uid) note=apple_token_revoke_requires_delete-account_edge_function")
            return true
        } catch {
            await MainActor.run { lastError = UserFacingErrorMessage.message(from: error) }
            print("[AuthFlow-Debug] auth operation=deleteAccount rpc=delete_user failed error=\(error.localizedDescription)")
            return false
        }
    }
}

/// Presents ASAuthorizationController and returns the credential result (used at account deletion for a fresh Apple auth code).
private final class AppleAuthorizationCodeCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static var assocKey: UInt8 = 0

    private let window: UIWindow
    private let onResult: (Result<ASAuthorization, Error>) -> Void
    private var hasResumed = false

    init(window: UIWindow, onResult: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.window = window
        self.onResult = onResult
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        resumeOnce(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        resumeOnce(.failure(error))
    }

    private func resumeOnce(_ result: Result<ASAuthorization, Error>) {
        guard !hasResumed else { return }
        hasResumed = true
        onResult(result)
    }
}
