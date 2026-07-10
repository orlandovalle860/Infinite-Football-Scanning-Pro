//
//  LoginView.swift
//  FootballScanningAI
//
//  Sign in with Apple or email/password. Shown when Supabase is configured and no session exists.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var isAppleSignInLoading = false
    @State private var showEmailForm = false
    /// Only set after a login/signup attempt fails; cleared when user edits email or password.
    @State private var attemptError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ResponsiveScrollScreen(horizontalPadding: 24, maxContentWidth: 360) {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("VisionPlay")
                            .font(.title.weight(.bold))
                            .foregroundColor(.white)
                        Text("See the Game")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                        Text("Sign in or create an account to sync your data")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                AuthManager.shared.handleAppleRequest(request)
                            },
                            onCompletion: { result in
                                isAppleSignInLoading = true
                                Task {
                                    await AuthManager.shared.handleAppleCompletion(result)
                                    await MainActor.run { isAppleSignInLoading = false }
                                }
                            }
                        )
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(8)
                        .signInWithAppleButtonStyle(.white)
                        .disabled(isAppleSignInLoading)

                        Button {
                            showEmailForm = true
                        } label: {
                            Text("Sign in with Email")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    if showEmailForm {
                        Text("or")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        VStack(spacing: 16) {
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
                        }

                        VStack(spacing: 12) {
                            Button {
                                submitSignIn()
                            } label: {
                                HStack {
                                    if isLoading { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)) }
                                    Text("Sign In")
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
                                submitSignUp()
                            } label: {
                                Text("Create Account")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.2))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || isLoading)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            auth.lastError = nil
            attemptError = nil
        }
    }

    private func submitSignIn() {
        focusedField = nil
        attemptError = nil
        isLoading = true
        Task {
            await auth.signIn(email: email, password: password)
            await MainActor.run {
                isLoading = false
                if auth.currentSession == nil, let msg = auth.lastError {
                    attemptError = msg
                }
            }
        }
    }

    private func submitSignUp() {
        focusedField = nil
        attemptError = nil
        isLoading = true
        Task {
            await auth.signUp(email: email, password: password)
            await MainActor.run {
                isLoading = false
                if auth.currentSession == nil, let msg = auth.lastError {
                    attemptError = msg
                }
            }
        }
    }
}

#Preview {
    LoginView()
}
