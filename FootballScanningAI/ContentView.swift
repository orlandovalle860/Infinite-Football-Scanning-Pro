//
//  ContentView.swift
//  FootballScanningAI
//
//  Created by Valle Family Mac Mini on 6/15/25.
//

import SwiftUI
import AVKit
import WebKit
import AVFoundation
import AudioToolbox
import UIKit
import Combine

struct DisplayModeButtonStyle: ButtonStyle {
    let isSelected: Bool
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color : color.opacity(0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CircleButtonStyle: ButtonStyle {
    let isSelected: Bool
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(isSelected ? color : Color.gray.opacity(0.3))
            )
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SquareButtonStyle: ButtonStyle {
    let isSelected: Bool
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color : Color.gray.opacity(0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ArrowButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.green : Color.gray.opacity(0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct StartButtonStyle: ButtonStyle {
    let isEnabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(isEnabled ? Color.blue : Color.blue.opacity(0.3))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ActivitiesButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.green)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Home “Start Training” activity tiles — label supplies yellow fill; style adds press feedback only.
struct HomeActivityLaunchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NumberColorButtonStyle: ButtonStyle {
    let isSelected: Bool
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue.opacity(0.3)
        } else {
            return color == .white ? Color(.sRGB, white: 0.15, opacity: 1.0) : Color(.sRGB, white: 0.95, opacity: 1.0)
        }
    }
}

struct CustomActionButtonStyle: ButtonStyle {
    let isActive: Bool
    let isEmpty: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEmpty ? Color.gray.opacity(0.3) : (isActive ? Color.green.opacity(0.3) : Color.gray.opacity(0.2)))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PresetActionButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TwitterVideoPlayerView: UIViewRepresentable {
    let tweetURL: String
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = URL(string: tweetURL) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: TwitterVideoPlayerView
        
        init(_ parent: TwitterVideoPlayerView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Video loaded successfully")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Failed to load video: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Failed to load video: \(error.localizedDescription)")
        }
    }
}

struct VideoPlayerView: View {
    let videoName: String
    let title: String
    let description: String
    let isTwitter: Bool
    let tweetURL: String?
    
    init(videoName: String, title: String, description: String, isTwitter: Bool = false, tweetURL: String? = nil) {
        self.videoName = videoName
        self.title = title
        self.description = description
        self.isTwitter = isTwitter
        self.tweetURL = tweetURL
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            if isTwitter, let url = tweetURL {
                TwitterVideoPlayerView(tweetURL: url)
                    .frame(height: 200)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            } else if let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .frame(height: 200)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            } else {
                // Fallback UI when video is not available
                ZStack {
                    Color.black.opacity(0.3)
                        .frame(height: 200)
                        .cornerRadius(12)
                    
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("Video Example")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
        }
    }
}

struct SplashScreen: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @State private var isActive = false

    private let splashDuration: TimeInterval = 2.5

    var body: some View {
        Group {
            if isActive {
                ContentView()
                    .environmentObject(connectionManager)
                    .environmentObject(multipeerManager)
                    .onAppear {
                        PBABeepSoundManager.shared.preloadCurrent()
                        AnalyticsManager.shared.track(.appOpened)
                        AnalyticsManager.shared.flushIfNeeded()
                    }
            } else {
                ZStack {
                    Color.white
                        .ignoresSafeArea()

                    GeometryReader { geo in
                        let logoWidth = min(geo.size.width * 0.82, geo.size.height * 0.94)
                        Image("SplashLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: logoWidth)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task(id: isActive) {
            guard !isActive else { return }
            let ns = UInt64(max(0.05, splashDuration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            isActive = true
        }
    }
}

struct ContentView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var profileManager = UserProfileManager()
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController
    /// Injected at root so any screen (including navigation destinations) can use @EnvironmentObject.
    @ObservedObject private var progressStore = ProgressStore.shared
    @StateObject private var playerStore = PlayerStore()
    @StateObject private var popToRootTrigger = PopToRootTrigger()
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    /// When this changes, MainAppView’s navigation stack is recreated so Home/Leave actually pops to root.
    @ObservedObject private var authManager = AuthManager.shared
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var multipeerManager: MultipeerManager

    var body: some View {
        Group {
            MainAppView(profileManager: profileManager, settingsViewModel: settingsViewModel, router: router)
        }
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
        .environmentObject(coachRemoteRequiredPrompt)
        .environmentObject(TrainingPartnerConnectionCoordinator.shared)
        .environmentObject(connectionManager)
        .environmentObject(multipeerManager)
        .navigationViewStyle(.stack)
        .environment(\.sizeCategory, .large)
        .environment(\.colorScheme, .dark)
    }
}

/// After Supabase sign-in: fetch players for current user. If none → Create Player (name only). If any → hydrate and show Home.
struct PostAuthView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var router: AppRouter
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController

    @State private var hasFetched = false
    @State private var showCreatePlayer = false
    @State private var playerFetchFailed = false
    @State private var loadGeneration = 0

    var body: some View {
        Group {
            if !hasFetched {
                ZStack {
                    Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.2)
                        Text("Loading…").font(.subheadline).foregroundColor(.white.opacity(0.8))
                    }
                }
            } else if playerFetchFailed {
                ZStack {
                    Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Couldn’t load your player profile.")
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text("Check your connection and try again.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Button("Retry") {
                            playerFetchFailed = false
                            hasFetched = false
                            loadGeneration += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                }
            } else if showCreatePlayer {
                CreatePlayerAfterAuthView(
                    profileManager: profileManager,
                    playerStore: playerStore,
                    twoMinuteTestResult: nil,
                    onComplete: {
                        showCreatePlayer = false
                        if let selectedId = playerStore.selectedPlayerId,
                           let selectedProfile = profileManager.profile(id: selectedId) {
                            profileManager.switchToProfile(selectedProfile)
                            playerStore.persist()
                        }
                    }
                )
                .environmentObject(progressStore)
            } else {
                MainAppView(profileManager: profileManager, settingsViewModel: settingsViewModel, router: router)
            }
        }
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
        .environmentObject(coachRemoteRequiredPrompt)
        .environmentObject(TrainingPartnerConnectionCoordinator.shared)
        .environmentObject(ConnectionManager.shared)
        .environmentObject(multipeerManager)
        .task(id: loadGeneration) {
            guard !hasFetched else { return }
            do {
                let list = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
                await MainActor.run {
                    hasFetched = true
                    playerFetchFailed = false
                    profileManager.reconcileWithSupabasePlayerList(list, playerStore: playerStore)
                    showCreatePlayer = profileManager.profiles.isEmpty
                }
                await AuthFlowOnboardingSync.resolveAndApplyOnboardingStateAfterLogin(
                    email: AuthManager.shared.currentUserEmail,
                    playerList: list,
                    context: "post_auth",
                    profileManager: profileManager
                )
            } catch {
                await MainActor.run {
                    hasFetched = true
                    playerFetchFailed = true
                    showCreatePlayer = false
                }
                print("[AuthFlow-Debug] context=post_auth fetchPlayers failed error=\(error.localizedDescription) routing=show_retry (not treating as empty roster)")
            }
        }
    }

}

private let coachDeviceShownHomeKey = "coachDeviceShownHome"

private struct WhatsNewControlsView: View {
    let onDismiss: () -> Void
    @State private var contentVisible = false

    private let bgTop = Color(red: 11.0 / 255.0, green: 15.0 / 255.0, blue: 26.0 / 255.0)
    private let bgBottom = Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [bgTop, bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 14)

                Text("What's New")
                    .font(.system(size: 30, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 44)

                VStack(spacing: 10) {
                    Text("New Controls")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                    Text("No buttons — just tap and swipe")
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("Tap → start / pass\nSwipe → log direction")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 34)

                VStack(spacing: 8) {
                    featureRow("More accurate timing")
                    featureRow("Clearer feedback")
                    featureRow("Progress tracking")
                    featureRow("Badges & streaks")
                }
                .padding(.horizontal, 28)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                } label: {
                    Text("Got It")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .cornerRadius(18)
                }
                .padding(.horizontal, 28)

                Text("You can view this again in Settings")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.gray)
                    .padding(.top, 12)

                Spacer(minLength: 18)
            }
            .opacity(contentVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: contentVisible)
        }
        .onAppear {
            contentVisible = false
            withAnimation(.easeInOut(duration: 0.2)) {
                contentVisible = true
            }
        }
    }

    private func featureRow(_ text: String) -> some View {
        Text("\u{2022} \(text)")
            .font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardAudienceRolePromptSheet: View {
    let onSelectCoach: () -> Void
    let onSelectParentPlayer: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("How are you using the app?")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                Button {
                    onSelectParentPlayer()
                } label: {
                    roleButtonLabel(
                        title: "Train Myself / With a Friend",
                        subtitle: "Run sessions and track your progress"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    onSelectCoach()
                } label: {
                    roleButtonLabel(
                        title: "Coach a Team",
                        subtitle: "Run sessions with a group and track players"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Text("You can change this anytime")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button("Not now") {
                    onDismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func roleButtonLabel(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct MainAppView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject private var authManager = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var connectionManager: ConnectionManager
    @ObservedObject private var coachRelayRemoteService = TrainingPartnerConnectionCoordinator.shared.coachRelayRemoteService
    @ObservedObject private var relayDisplaySession = TrainingPartnerConnectionCoordinator.shared.relayDisplaySession
    @ObservedObject private var partnerTrainingCoordinator = TrainingPartnerConnectionCoordinator.shared
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController
    @State private var showsTopToggle: Bool = true
    @State private var showLoginSheet: Bool = false
    @State private var showCreatePlayerAfterAuth: Bool = false
    @State private var hasHydratedPlayersForSession: Bool = false
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    @AppStorage(hasSeenIntroKey) private var hasSeenIntro = false
    @AppStorage(coachDeviceShownHomeKey) private var coachDeviceShownHome = false
    @AppStorage(AppRole.storageKey) private var appRoleRaw: String = AppRole.player.rawValue
    @AppStorage("dashboardAudienceRoleV1") private var dashboardAudienceRoleRaw: String = ""
    @AppStorage("dashboardAudienceRolePromptSeenV2") private var dashboardAudienceRolePromptSeen = false
    @AppStorage("whatsNewControlsSeenV1") private var whatsNewControlsSeen = false
    @State private var signOutUXPhase: SignOutUXPhase = .idle
    @State private var showDashboardAudienceRolePrompt = false
    @State private var showWhatsNewControlsPrompt = false
    /// One-time Solo vs Coach Remote (partner) choice; skipped when a stored training mode already exists (see ``PBASessionFlowPolicy.migrateTrainingModeOnboardingIfNeeded()``).
    @AppStorage(AppStorageKeys.hasLaunchedBefore) private var hasLaunchedBefore = false

    private var resolvedAppRole: AppRole { AppRole.resolved(from: appRoleRaw) }

    private var showFirstLaunchTrainingModeSelection: Binding<Bool> {
        Binding(
            get: { !hasLaunchedBefore && resolvedAppRole != .coachRemote },
            set: { _ in }
        )
    }

    /// iPhone: after first-launch training mode is chosen (``hasLaunchedBefore``), optional one-time Coach Remote hub for join alignment. Must **not** run before mode selection or it steals root and blocks ``FirstLaunchModeSelectionView``.
    private var iPhoneFirstLaunchUseCoachHubForConnection: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && !hasSeenIntro && hasLaunchedBefore
    }
    private var shouldShowAudiencePrompt: Bool {
        resolvedAppRole != .coachRemote
            && hasCompletedInitialTest
            && !dashboardAudienceRolePromptSeen
            && !authManager.isRestoring
    }
    private var shouldShowWhatsNewControlsPrompt: Bool {
        hasCompletedInitialTest
            && !whatsNewControlsSeen
            && !authManager.isRestoring
            && resolvedAppRole != .coachRemote
            && !showDashboardAudienceRolePrompt
    }

    /// After reinstall, local stores are empty but Supabase session may still restore from keychain; players then load asynchronously. Don't flash Intro until we know remote is empty too (signed-in + host).
    private var shouldWaitForRemoteHydration: Bool {
        guard Config.isSupabaseConfigured else { return false }
        guard ConnectionManager.shared.isHost else { return false }
        guard authManager.currentSession != nil else { return false }
        guard !hasHydratedPlayersForSession else { return false }
        return profileManager.profiles.isEmpty && playerStore.players.isEmpty
    }

    /// Player iPad with a live coach/display link must never sit on Intro, player picker, or Home under the join sheet — root is always ``playerHomeRoot`` (passive standby).
    private var iPadPlayerLiveCoachLinkTakesRoot: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && CoachRemoteSessionStartGate.isPadPlayerRole()
            && CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive()
    }

    private var launchBootstrapPlaceholder: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
        }
    }

    /// Coach Remote devices: root is ``CoachRemoteHubView`` (skips player Home). See ``AppRole``.
    @ViewBuilder
    private var coachRemoteRootView: some View {
        CoachRemoteHubView(settingsViewModel: settingsViewModel, profileManager: profileManager)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
            .onAppear {
                guard iPhoneFirstLaunchUseCoachHubForConnection else { return }
                appRoleRaw = AppRole.coachRemote.rawValue
                hasSeenIntro = true
                AppRoleDebug.log("routing_decision reason=iphone_first_launch_sync_coach_remote_for_join_alignment")
            }
    }

    /// Launch: auth/bootstrap → Intro until baseline is done locally or in Supabase user_metadata (see `AuthFlowOnboardingSync`); then Home / player pick.
    @ViewBuilder
    private var rootView: some View {
        Group {
            if authManager.isRestoring {
                launchBootstrapPlaceholder
            } else if resolvedAppRole == .coachRemote || iPhoneFirstLaunchUseCoachHubForConnection {
                coachRemoteRootView
            } else if iPadPlayerLiveCoachLinkTakesRoot {
                playerHomeRoot
            } else if shouldWaitForRemoteHydration {
                launchBootstrapPlaceholder
            } else if !hasSeenIntro {
                // One-time first-launch intro only.
                IntroOnboardingView(
                    settingsViewModel: settingsViewModel,
                    profileManager: profileManager
                )
            } else if playerStore.players.isEmpty, profileManager.profiles.isEmpty,
                      Config.isSupabaseConfigured, authManager.currentSession != nil {
                // Signed in with baseline done remotely but no local profiles yet (reinstall / coach device): pick or add a player — not the first-run 2-min intro.
                PlayerSelectionView(
                    profileManager: profileManager,
                    playerStore: playerStore,
                    settingsViewModel: settingsViewModel,
                    router: router,
                    signOutUXPhase: $signOutUXPhase
                )
            } else if playerStore.players.isEmpty, profileManager.profiles.isEmpty {
                playerHomeRoot
            } else if Config.isSupabaseConfigured, authManager.currentSession != nil, playerStore.selectedPlayerId == nil {
                PlayerSelectionView(
                    profileManager: profileManager,
                    playerStore: playerStore,
                    settingsViewModel: settingsViewModel,
                    router: router,
                    signOutUXPhase: $signOutUXPhase
                )
            } else {
                playerHomeRoot
            }
        }
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
    }

    private func logLaunchRouting(reason: String) {
        let route: String = {
            if authManager.isRestoring { return "bootstrap_auth_restoring" }
            if resolvedAppRole == .coachRemote || iPhoneFirstLaunchUseCoachHubForConnection { return "coach_remote_root" }
            if iPadPlayerLiveCoachLinkTakesRoot { return "ipad_player_coach_link_root" }
            if shouldWaitForRemoteHydration { return "bootstrap_wait_remote_hydration" }
            if !hasSeenIntro { return "intro_first_launch" }
            if hasCompletedInitialTest, playerStore.players.isEmpty, profileManager.profiles.isEmpty,
               Config.isSupabaseConfigured, authManager.currentSession != nil {
                return "player_selection_signed_in_no_local"
            }
            if playerStore.players.isEmpty, profileManager.profiles.isEmpty { return "home_no_local_identity" }
            if Config.isSupabaseConfigured, authManager.currentSession != nil, playerStore.selectedPlayerId == nil {
                return "player_selection"
            }
            return "home"
        }()
        LaunchProfileDebug.log("app_launch reason=\(reason) route=\(route)")
        LaunchProfileDebug.log("first_run hasSeenIntro=\(hasSeenIntro)")
        LaunchProfileDebug.log("first_run hasCompletedInitialTest=\(hasCompletedInitialTest)")
        LaunchProfileDebug.log("session authenticated=\(authManager.currentSession != nil) isRestoring=\(authManager.isRestoring)")
        LaunchProfileDebug.log("local playerCount=\(playerStore.players.count) profileCount=\(profileManager.profiles.count)")
        LaunchProfileDebug.log("remote hydrate hasHydratedPlayersForSession=\(hasHydratedPlayersForSession) shouldWaitRemote=\(shouldWaitForRemoteHydration)")
        AppRoleDebug.log("routing_decision reason=\(reason) appRole=\(resolvedAppRole.rawValue) route=\(route)")
    }

    private func refreshCoachingTrainingNudgesIfNeeded() {
        CoachingTrainingNotificationScheduler.refresh(
            enabled: settingsViewModel.coachingNudgesEnabled,
            playerId: playerStore.selectedPlayerId ?? profileManager.currentProfile?.id,
            profile: profileManager.currentProfile,
            progressStore: progressStore
        )
    }

    /// Player iPad with an active coach/display link — Home is replaced by a passive standby (no training or role switching).
    private var iPadPlayerDisplayConnectedStandby: Bool {
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return false }
        _ = coachRelayRemoteService.connectionState
        _ = relayDisplaySession.isCoachPaired
        return CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive()
    }

    @ViewBuilder
    private var playerHomeRoot: some View {
        ZStack {
            if iPadPlayerDisplayConnectedStandby {
                IPadPlayerDisplayConnectedStandbyView(coachLinkActive: CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive())
            } else {
                HomeDashboardView(
                    profileManager: profileManager,
                    settingsViewModel: settingsViewModel,
                    showsTopToggle: $showsTopToggle,
                    showLoginSheet: $showLoginSheet,
                    signOutUXPhase: $signOutUXPhase
                )
            }
            PartnerMidSessionDisconnectRecoveryOverlay()
                .zIndex(200)
        }
    }

    private func popNavigationToRootIfIPadPlayerStandby() {
        guard iPadPlayerDisplayConnectedStandby, !router.path.isEmpty else { return }
        router.popToRoot()
    }

    /// When the coach link goes live on a player iPad, leave first-run intro behind so we never flash tablet “Start Training” after the join sheet dismisses.
    private func markIntroSeenForIPadPlayerIfCoachLinked() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive() else { return }
        guard !hasSeenIntro else { return }
        hasSeenIntro = true
    }

    private func handleCoachSessionStartedNotification(_ notification: Notification) {
        guard let msg = notification.object as? TwoMinuteMessage else { return }
        guard case .sessionStarted(let activityId, let totalReps, let timestamp) = msg else { return }
        // 1) Session state (authoritative block metadata) — independent of navigation.
        TrainingPartnerConnectionCoordinator.shared.applySessionStartedFromCoach(
            activityId: activityId,
            totalReps: totalReps,
            startedAt: timestamp
        )
        // 2) Navigation — separate step; `.id(partnerDisplaySurfaceId)` recreates the drill surface if already on-route.
        applyIPadDisplayRouteFromCoachSessionStarted(activityId: activityId)
    }

    /// Relay `sessionStarted` from coach phone: open the matching partner **display** route (no local iPad tap).
    private func applyIPadDisplayRouteFromCoachSessionStarted(activityId: String) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
        guard CoachRemoteSessionStartGate.iPadDisplayCoachRelayLinkIsLive() else { return }
        guard let activity = ActivityKind.fromSessionActivityId(activityId) else {
            AppRoleDebug.log("sessionStarted ignored unknown activityId=\(activityId)")
            return
        }
        let route = PBASessionFlowPolicy.routeForActivityLaunch(activity)
        if router.path.last == route {
            AppRoleDebug.log("sessionStarted display already on route activity=\(activity.rawValue) — DisplaySessionState refreshed; surface id updated")
            return
        }
        router.popToRoot(endingPartnerSession: false)
        router.push(route)
        AppRoleDebug.log("sessionStarted display navigation activity=\(activity.rawValue) route=push")
    }

    /// Forces a fresh partner drill `View` identity when the coach restarts `sessionStarted` (new `partnerDisplaySurfaceId`).
    private func partnerDisplaySurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .id(partnerTrainingCoordinator.partnerDisplaySurfaceId)
    }

    private func mainAppOnAppear() {
        router.resetNavigationToHomeOnFirstMainAppLaunch()
        PBASessionFlowPolicy.migrateTrainingModeOnboardingIfNeeded()
#if DEBUG
        print("DEBUG SUPABASE_URL:", Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") ?? "nil")
        print("DEBUG SUPABASE_ANON_KEY:", Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") ?? "nil")
#endif
        print("[Supabase] App main screen appeared — checking config and unsynced sessions.")
        progressStore.load()
        // PlayerStore loads persisted players in its init (first frame); no duplicate load() here.
        if let selectedId = playerStore.selectedPlayerId,
           let selectedProfile = profileManager.profile(id: selectedId) {
            profileManager.switchToProfile(selectedProfile)
        }
        if !playerStore.players.isEmpty, !profileManager.profiles.isEmpty {
            if let current = profileManager.currentProfile,
               !playerStore.players.contains(where: { $0.id == current.id }) {
                playerStore.addPlayer(id: current.id, name: current.name)
            }
        }
        AppRoleDebug.log("launch appRole=\(resolvedAppRole.rawValue)")
        logLaunchRouting(reason: "MainAppView.onAppear_before_hydrate")
        hydratePlayersIfNeeded()
        logLaunchRouting(reason: "MainAppView.onAppear_after_hydrate_scheduled")
        // One-time clear of unsynced sessions and pending decisions so old data (outdated schema) is not retried.
        let clearedKey = "SupabaseDidClearUnsyncedQueue"
        if !UserDefaults.standard.bool(forKey: clearedKey) {
            progressStore.clearUnsyncedSessionQueue()
            SupabaseDecisionService.shared.clearPendingDecisionsQueue()
            UserDefaults.standard.set(true, forKey: clearedKey)
            print("[Supabase] Cleared unsynced sessions and pending decisions queue (one-time reset).")
        }
        let count = progressStore.unsyncedSessions.count
        print("[Supabase] Configured. Retrying \(count) unsynced session(s) on launch.")
        SupabaseSessionService.shared.retryPendingSessions(progressStore: progressStore)
        SupabaseDecisionService.shared.retryPendingDecisions()
        SupabasePlayerService.shared.retryPendingPlayers(profileManager: profileManager)
        SupabasePlayerService.shared.retryPendingDeletes()
        refreshCoachingTrainingNudgesIfNeeded()
        showDashboardAudienceRolePrompt = false
        showWhatsNewControlsPrompt = false
    }

    /// Split from `body` so the SwiftUI type checker can finish in reasonable time.
    private var mainAppNavigationAndCoachObservers: some View {
        Group {
            NavigationStack(path: router.pathBinding) {
                rootView
                    .onReceive(NotificationCenter.default.publisher(for: .twoMinuteMessageReceived)) { self.handleCoachSessionStartedNotification($0) }
                    .onReceive(NotificationCenter.default.publisher(for: .presentPlayerDisplayJoinPromptAfterStartNewSession).receive(on: RunLoop.main)) { _ in
                        guard hasLaunchedBefore else { return }
                        guard PBASessionFlowPolicy.lastSelectedTrainingMode().needsCoachRemoteJoinCodeFlow else { return }
                        guard CoachRemoteSessionStartGate.isPadPlayerRole() else { return }
                        coachRemoteRequiredPrompt.present(pendingRoute: nil)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        routeView(for: route)
                    }
            }
            .overlay(alignment: .topTrailing) {
                GlobalHomeNavigationOverlay()
            }
        }
        .onChange(of: router.path.count) { _, count in
            if count == 0 {
                popToRootTrigger.request = false
            }
        }
        .task(id: appRoleRaw) {
            guard UIDevice.current.userInterfaceIdiom == .pad else { return }
            guard AppRole.resolved(from: appRoleRaw) == .player else { return }
            await TrainingPartnerConnectionCoordinator.shared.warmUpCoachLinkSurfaceOnPlayerDisplayIfNeeded()
        }
        .onChange(of: coachRelayRemoteService.connectionState) { _, _ in
            markIntroSeenForIPadPlayerIfCoachLinked()
            popNavigationToRootIfIPadPlayerStandby()
        }
        .onChange(of: relayDisplaySession.isCoachPaired) { _, _ in
            markIntroSeenForIPadPlayerIfCoachLinked()
            popNavigationToRootIfIPadPlayerStandby()
        }
        .onChange(of: connectionManager.connectedPeerName) { _, _ in
            markIntroSeenForIPadPlayerIfCoachLinked()
            popNavigationToRootIfIPadPlayerStandby()
        }
    }

    private var mainAppEnvironmentAndBlockingOverlay: some View {
        mainAppNavigationAndCoachObservers
            .overlay {
                SignOutUXBlockingOverlay(phase: signOutUXPhase)
            }
            .animation(.easeInOut(duration: 0.2), value: signOutUXPhase)
            .environmentObject(connectionManager)
            .environmentObject(multipeerManager)
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
            .environmentObject(coachRemoteRequiredPrompt)
    }

    private var coachRemoteRequiredPromptPresentedBinding: Binding<Bool> {
        Binding(
            get: { coachRemoteRequiredPrompt.isPresented },
            set: { coachRemoteRequiredPrompt.isPresented = $0 }
        )
    }

    /// Further split so Swift can type-check `MainAppView` presentations (see `mainAppSheets`).
    private var mainAppWithCoachRemoteFullScreen: some View {
        mainAppEnvironmentAndBlockingOverlay
            .fullScreenCover(isPresented: coachRemoteRequiredPromptPresentedBinding, onDismiss: {
                coachRemoteRequiredPrompt.clearPendingSessionAfterDismiss()
            }) {
                CoachRemoteRequiredPromptView()
                    .environmentObject(coachRemoteRequiredPrompt)
                    .environmentObject(router)
            }
    }

    private var mainAppWithLoginSheet: some View {
        mainAppWithCoachRemoteFullScreen
            .sheet(isPresented: $showLoginSheet) {
                LoginView()
                    .onDisappear {
                        if authManager.currentSession != nil { hydratePlayersIfNeeded() }
                    }
            }
    }

    private var mainAppWithCreatePlayerSheet: some View {
        mainAppWithLoginSheet
            .sheet(isPresented: $showCreatePlayerAfterAuth) {
                CreatePlayerAfterAuthView(
                    profileManager: profileManager,
                    playerStore: playerStore,
                    twoMinuteTestResult: nil,
                    onComplete: {
                        showCreatePlayerAfterAuth = false
                        if let selectedId = playerStore.selectedPlayerId,
                           let selectedProfile = profileManager.profile(id: selectedId) {
                            profileManager.switchToProfile(selectedProfile)
                            playerStore.persist()
                        }
                    }
                )
                .environmentObject(progressStore)
            }
    }

    private var mainAppWithDashboardAudienceSheet: some View {
        mainAppWithCreatePlayerSheet
            .sheet(isPresented: $showDashboardAudienceRolePrompt) {
                DashboardAudienceRolePromptSheet(
                    onSelectCoach: {
                        dashboardAudienceRoleRaw = "coach"
                        dashboardAudienceRolePromptSeen = true
                        showDashboardAudienceRolePrompt = false
                    },
                    onSelectParentPlayer: {
                        dashboardAudienceRoleRaw = "parent_player"
                        dashboardAudienceRolePromptSeen = true
                        showDashboardAudienceRolePrompt = false
                    },
                    onDismiss: {
                        dashboardAudienceRolePromptSeen = true
                        showDashboardAudienceRolePrompt = false
                    }
                )
            }
    }

    private var mainAppSheets: some View {
        mainAppWithDashboardAudienceSheet
            .sheet(isPresented: $showWhatsNewControlsPrompt, onDismiss: {
                whatsNewControlsSeen = true
                showWhatsNewControlsPrompt = false
            }) {
                WhatsNewControlsView {
                    whatsNewControlsSeen = true
                    showWhatsNewControlsPrompt = false
                }
            }
            .fullScreenCover(isPresented: showFirstLaunchTrainingModeSelection) {
                FirstLaunchModeSelectionView(onComplete: {})
                    .interactiveDismissDisabled()
            }
    }

    private var mainAppSceneAndAuthObservers: some View {
        mainAppSheets
            .onAppear(perform: mainAppOnAppear)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshCoachingTrainingNudgesIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .coachingTrainingNudgesShouldRefresh)) { _ in
                refreshCoachingTrainingNudgesIfNeeded()
            }
            .onChange(of: authManager.isRestoring) { _, restoring in
                if !restoring {
                    logLaunchRouting(reason: "auth_isRestoring_false")
                    hydratePlayersIfNeeded()
                }
            }
            .onChange(of: authManager.currentSession != nil) { _, hasSession in
                if !hasSession {
                    hasHydratedPlayersForSession = false
                    showCreatePlayerAfterAuth = false
                } else { hydratePlayersIfNeeded() }
                logLaunchRouting(reason: "session_changed hasSession=\(hasSession)")
            }
    }

    private var mainAppRoutingObservers: some View {
        mainAppSceneAndAuthObservers
            .onChange(of: hasHydratedPlayersForSession) { _, v in
                logLaunchRouting(reason: "hasHydratedPlayersForSession=\(v)")
            }
            .onChange(of: hasCompletedInitialTest) { _, v in
                logLaunchRouting(reason: "hasCompletedInitialTest=\(v)")
            }
            .onChange(of: hasSeenIntro) { _, v in
                logLaunchRouting(reason: "hasSeenIntro=\(v)")
            }
            .onChange(of: appRoleRaw) { oldValue, newValue in
                AppRoleDebug.log("role_change old=\(oldValue) new=\(newValue) routing=\(AppRole.resolved(from: newValue) == .coachRemote ? "coach_remote_root" : "player_flow")")
                router.popToRoot()
                logLaunchRouting(reason: "app_role_storage_changed")
            }
            .onChange(of: hasCompletedInitialTest) { _, _ in
                showDashboardAudienceRolePrompt = false
            }
            .onChange(of: dashboardAudienceRoleRaw) { _, _ in
                showDashboardAudienceRolePrompt = false
            }
            .onChange(of: showDashboardAudienceRolePrompt) { _, _ in
                showWhatsNewControlsPrompt = false
            }
            .onReceive(NetworkReachabilityObserver.shared.reachableSubject) { _ in
                SupabaseSessionService.shared.retryPendingSessions(progressStore: progressStore)
                SupabaseDecisionService.shared.retryPendingDecisions()
                SupabasePlayerService.shared.retryPendingPlayers(profileManager: profileManager)
                SupabasePlayerService.shared.retryPendingDeletes()
                AnalyticsManager.shared.flushIfNeeded()
            }
    }

    var body: some View {
        mainAppRoutingObservers
    }

    /// When signed in, fetch players from Supabase and hydrate stores once per session. If no players, offer Create Player sheet.
    private func hydratePlayersIfNeeded() {
        guard Config.isSupabaseConfigured, authManager.currentSession != nil, !hasHydratedPlayersForSession else {
            LaunchProfileDebug.log("hydrate_skipped supabase=\(Config.isSupabaseConfigured) session=\(authManager.currentSession != nil) alreadyHydrated=\(hasHydratedPlayersForSession)")
            return
        }
        LaunchProfileDebug.log("hydrate_start fetching players for current user")
        Task {
            do {
                let list = try await SupabasePlayerService.shared.fetchPlayersForCurrentUser()
                await MainActor.run {
                    LaunchProfileDebug.log("hydrate_success remoteRowCount=\(list.count) — reconciling local stores")
                    hasHydratedPlayersForSession = true
                    profileManager.reconcileWithSupabasePlayerList(list, playerStore: playerStore)
                    // Use remote row count — reconcile may no-op on non-display devices, leaving locals empty while server has players.
                    showCreatePlayerAfterAuth = list.isEmpty
                    logLaunchRouting(reason: "after_reconcile remoteRows=\(list.count) localProfiles=\(profileManager.profiles.count)")
                }
                await AuthFlowOnboardingSync.resolveAndApplyOnboardingStateAfterLogin(
                    email: authManager.currentUserEmail,
                    playerList: list,
                    context: "hydrate",
                    profileManager: profileManager
                )
            } catch {
                await MainActor.run {
                    LaunchProfileDebug.log("hydrate_failed error=\(error.localizedDescription)")
                    hasHydratedPlayersForSession = true
                    showCreatePlayerAfterAuth = false
                    logLaunchRouting(reason: "hydrate_catch")
                }
                print("[AuthFlow-Debug] context=hydrate fetchPlayers failed error=\(error.localizedDescription) routing=keep_local_state (not opening create_player)")
                await AuthFlowOnboardingSync.resolveAndApplyOnboardingStateAfterLogin(
                    email: authManager.currentUserEmail,
                    playerList: [],
                    context: "hydrate_error",
                    profileManager: profileManager
                )
            }
        }
    }

    /// Same persistence as ``TrainingModeSelectionView`` / ``PBASessionFlowPolicy.routeForActivityLaunch`` (not a hardcoded `.partner`).
    private var persistedTrainingMode: TrainingMode { PBASessionFlowPolicy.lastSelectedTrainingMode() }

    @ViewBuilder
    private func routeView(for route: AppRoute) -> some View {
        switch route {
        case .twoMinuteRoleSelection:
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .coachRemote:
            CoachRemoteHubView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .partnerPairing:
            PartnerSessionStartView()
                .environmentObject(router)
        case .twoMinuteCoachRemote:
            CoachRemoteActivityConnectionGate {
                TwoMinuteCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
            .environmentObject(router)
        case .dribbleOrPassCoachRemote:
            CoachRemoteActivityConnectionGate {
                DribbleOrPassCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
            .environmentObject(router)
        case .awayFromPressureCoachRemote:
            CoachRemoteActivityConnectionGate {
                AwayFromPressureCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
            .environmentObject(router)
        case .oneTouchPassingCoachRemote:
            CoachRemoteActivityConnectionGate {
                OneTouchPassingCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
            .environmentObject(router)
        case .curriculum:
            PBACurriculumView(
                settingsViewModel: settingsViewModel,
                profileManager: profileManager,
                progressStore: progressStore,
                playerStore: playerStore,
                popToRootTrigger: popToRootTrigger
            )
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .progress:
            PlayerImprovementProgressView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .profileInsights:
            PlayerProfileProgressInsightsView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(router)
        case .achievements:
            AchievementsView(profileManager: profileManager)
                .environmentObject(playerStore)
                .environmentObject(router)
        case .soloActivitySelection:
            SoloActivitySelectionView()
                .environmentObject(router)
                .environmentObject(coachRemoteRequiredPrompt)
        case .soloSessionDuration(let activity):
            SoloSessionDurationSelectionView(activity: activity)
                .environmentObject(router)
        case .warmupHub:
            WarmupHubView()
                .environmentObject(router)
        case .warmup(let mode):
            MainView(settingsViewModel: settingsViewModel, profileManager: profileManager, displayMode: mode, showModeSelection: false)
        case .trainingModeSelection:
            partnerDisplaySurface {
                TwoMinuteCriticalScanSessionView(config: TwoMinuteTestConfig.baseline, mode: persistedTrainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .twoMinuteSetup(let mode):
            partnerDisplaySurface {
                TwoMinuteCriticalScanSessionView(config: TwoMinuteTestConfig.baseline, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .twoMinuteGetReady(let mode):
            partnerDisplaySurface {
                TwoMinuteCriticalScanSessionView(config: TwoMinuteTestConfig.baseline, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .awayFromPressureRoleSelection:
            partnerDisplaySurface {
                AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: persistedTrainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .awayFromPressureTrainingModeSelection:
            partnerDisplaySurface {
                AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: persistedTrainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .awayFromPressureSetup(let mode):
            partnerDisplaySurface {
                AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .dribbleOrPassRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: persistedTrainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: persistedTrainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPassSetup(let mode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingRoleSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: persistedTrainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingTrainingModeSelection:
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: persistedTrainingMode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassingSetup(let mode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .dribbleOrPass(let mode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    DribbleOrPassDisplaySessionView(config: DribbleOrPassConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .oneTouchPassing(let mode):
            if profileManager.isPremiumActive(playerId: playerStore.selectedPlayerId) {
                partnerDisplaySurface {
                    OneTouchPassingDisplaySessionView(config: OneTouchPassingConfig.defaultConfig(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                        .environmentObject(progressStore)
                        .environmentObject(playerStore)
                        .environmentObject(popToRootTrigger)
                        .environmentObject(router)
                }
            } else {
                PremiumPaywallView(profileManager: profileManager)
                    .environmentObject(playerStore)
                    .environmentObject(router)
            }
        case .awayFromPressure(let mode):
            partnerDisplaySurface {
                AwayFromPressureDisplaySessionView(config: AwayFromPressureConfig.config(for: .standard), mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .twoMinuteTest(let mode):
            partnerDisplaySurface {
                TwoMinuteCriticalScanSessionView(config: TwoMinuteTestConfig.baseline, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
            }
        case .debugMenu:
            #if DEBUG
            DebugMenuView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(router)
            #else
            Text("Tester tools are not available in this build.")
                .foregroundStyle(.secondary)
                .padding()
            #endif
        }
    }
}

/// SCREEN 1 — INTRO. First launch: iPhone defaults to Coach Remote story; iPad keeps display vs remote choice.
struct IntroOnboardingView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var router: AppRouter
    @AppStorage(hasSeenIntroKey) private var hasSeenIntro = false
    @AppStorage(AppRole.storageKey) private var appRoleRaw: String = AppRole.player.rawValue
    @State private var headlineVisible = false
    @State private var subtextVisible = false
    @State private var buttonVisible = false
    @State private var buttonPressed = false
    @State private var buttonIdlePulse = false

    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        Group {
            if isIPhone {
                iphoneIntroLayout
            } else {
                tabletIntroLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AnalyticsManager.shared.track(.introScreenViewed)
            headlineVisible = false
            subtextVisible = false
            buttonVisible = false
            buttonPressed = false
            buttonIdlePulse = false

            withAnimation(.easeInOut(duration: 0.35)) {
                headlineVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    subtextVisible = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    buttonVisible = true
                }
                buttonIdlePulse = true
            }
        }
    }

    /// iPhone: Coach Remote is the expected role; sessions are driven from this device with iPad as display.
    private var iphoneIntroLayout: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 48)
            Text("This phone is your control center.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 28)
                .opacity(headlineVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: headlineVisible)

            Text("The iPad shows the drill. You start the session here and run reps as Coach Remote—training doesn’t begin on the phone alone.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .opacity(subtextVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: subtextVisible)

            Spacer(minLength: 12)

            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    buttonPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        buttonPressed = false
                    }
                }
                appRoleRaw = AppRole.coachRemote.rawValue
                hasSeenIntro = true
            } label: {
                Text("Start Coaching Session")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.yellow)
                    .cornerRadius(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 28)
            .opacity(buttonVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: buttonVisible)
            .scaleEffect(buttonPressed ? 0.97 : (buttonIdlePulse ? 1.02 : 1.0))
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: buttonIdlePulse)
            .accessibilityLabel("Start Coaching Session")
            .accessibilityHint("Use this iPhone as Coach Remote with an iPad display.")

            Button {
                appRoleRaw = AppRole.player.rawValue
                hasSeenIntro = true
            } label: {
                Text("Player profile on this iPhone")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                    )
                    .cornerRadius(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 28)
            .opacity(buttonVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: buttonVisible)
            .accessibilityLabel("Player profile on this iPhone")
            .accessibilityHint("View progress and home on this device. Start sessions from Coach Remote with an iPad display.")

            Spacer(minLength: 52)
        }
    }

    /// iPad (and Mac Catalyst): original display-first vs Coach Remote choice.
    private var tabletIntroLayout: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 48)
            Text("Do you know what you're going to do before the ball arrives?")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 28)
                .opacity(headlineVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: headlineVisible)

            Text("Elite players do.")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .opacity(subtextVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: subtextVisible)

            Spacer(minLength: 12)

            Text("This iPad is the display. Sessions are started from Coach Remote on a phone—nothing starts here.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(subtextVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: subtextVisible)

            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    buttonPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        buttonPressed = false
                    }
                }
                appRoleRaw = AppRole.player.rawValue
                hasSeenIntro = true
            } label: {
                Text("Continue")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.yellow)
                    .cornerRadius(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 28)
            .opacity(buttonVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: buttonVisible)
            .scaleEffect(buttonPressed ? 0.97 : (buttonIdlePulse ? 1.02 : 1.0))
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: buttonIdlePulse)
            .accessibilityLabel("Continue")
            .accessibilityHint("Use this iPad as the training display. Connect a phone with Coach Remote.")

            Spacer(minLength: 52)
        }
    }
}

/// Card style for Home dashboard: consistent for all non-pinned cards.
struct StartPageCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private let hasSeenPlayerSwitcherTooltipKey = "hasSeenPlayerSwitcherTooltip"

/// SCREEN 8 — HOME DASHBOARD. Main app after onboarding. Pinned Train Now + scrollable cards.
typealias HomeDashboardView = IntroView

struct IntroView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Binding var showsTopToggle: Bool
    @Binding var showLoginSheet: Bool
    @Binding var signOutUXPhase: SignOutUXPhase
    @ObservedObject private var authManager = AuthManager.shared
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var coachRemoteRequiredPrompt: CoachRemoteRequiredPromptController
    @State private var showHowItWorks = false
    @State private var showStatusUpgrade = false
    @State private var upgradedStatus: PlayerStatus?
    @State private var showPlayersSheet = false
    @State private var showBeepSelector = false
    @State private var activeProgressModal: ProgressModalType?
    @State private var progressModalScale: CGFloat = 0.92
    @State private var progressModalOpacity: Double = 0
    @AppStorage(hasSeenPlayerSwitcherTooltipKey) private var hasSeenPlayerSwitcherTooltip = false
    // Programmatic navigation so buttons reliably push (NavigationLink in ScrollView can miss taps).
    @State private var isStartTrainingPressed = false
    /// Prevents double-tap from scheduling two pushes (avoids freeze / duplicate navigation after completing a session).
    @State private var isNavigatingToTraining = false
    @State private var snapshotMetricInfoToShow: (title: String, message: String)?
    /// Latest session_summary for Daily Goal card (Last Score / Target). Fetched when player changes.
    @State private var dashboardData: HomeDashboardData?
    @State private var guidedProgress = GuidedCurriculumProgress(
        stage: 1,
        loop: 1,
        nextActivity: .awayFromPressure,
        focus: "Decide away from pressure quickly — your first decision is what we score."
    )
    @State private var currentPlayerIdentity: PlayerIdentity?
    @State private var trendingIdentity: PlayerIdentity?
    @State private var showSignOutConfirmation = false
    @State private var showSwitchPlayerConfirmation = false

    /// Home segmented control: Solo vs Coach Remote path (``TrainingMode.partner``). Wall maps to the Partner segment for display.
    private enum HomeTrainingModeSegment: String, Hashable {
        case solo
        case partner
    }

    @State private var homeTrainingModeSegment: HomeTrainingModeSegment = .solo
    @State private var highlightPrimaryAction: Bool = false
    @State private var isStartSessionPressed = false
    @State private var homeLogoWatermark: UIImage?

    private enum ProgressModalType: Identifiable {
        case levelUp(previousTier: String, newTier: String, previousAvg: Double?, newAvg: Double?, previousAccuracy: Int?, newAccuracy: Int?)
        case stageUnlocked(stage: Int, activity: ActivityKind)
        case curriculumComplete(decisionSpeedChange: String?, accuracyChange: String?, forwardThinkingChange: String?, recommendedActivity: ActivityKind)
        case adaptiveWedgeDifficulty(level: Int)
        case badgeTierUnlocked(event: BadgeTierUnlockEvent)
        case identityChanged(identity: PlayerIdentity)

        var id: String {
            switch self {
            case .levelUp(_, let newTier, _, _, _, _):
                return "levelup_\(newTier)"
            case .stageUnlocked(let stage, let activity):
                return "stage_\(stage)_\(activity.rawValue)"
            case .curriculumComplete(_, _, _, let recommendedActivity):
                return "curriculum_complete_\(recommendedActivity.rawValue)"
            case .adaptiveWedgeDifficulty(let level):
                return "adaptive_wedge_difficulty_\(level)"
            case .badgeTierUnlocked(let event):
                return "badge_tier_unlocked_\(event.track.rawValue)_\(event.level)"
            case .identityChanged(let identity):
                return "identity_changed_\(identity.rawValue)"
            }
        }
    }

    private var playerId: UUID? { playerStore.selectedPlayerId }
    private var last5: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: playerId) }
    private var consistencyLabel: ConsistencyLabel { DashboardConsistency.label(from: last5) }
    private var decisionScore: Int { DashboardDecisionScore.score(from: last5) }
    private var status: PlayerStatus { DashboardDecisionScore.status(score: decisionScore, consistencyLabel: consistencyLabel) }
    private var dailyCompleted: Int { DailyTargetState.completedBlocksToday(playerId: playerId) }
    private var dailyTarget: Int { DailyTargetState.targetBlocksPerDay }
    private var dailyDecisionsCompleted: Int { DailyDecisionProgress.decisionsCompletedToday(playerId: playerId) }
    private var dailyDecisionGoal: Int { DailyDecisionProgress.goalPerDay }
    private var hasAnyBlock: Bool { !last5.isEmpty }
    private var trainingStreakDays: Int { profileManager.trainingStreakDays() }
    private var weeklyStreakWeeks: Int { profileManager.currentWeeklyStreak() }
    private var sessionsThisWeek: Int { profileManager.sessionsCompletedThisWeek() }
    private var weeklyStreakTitle: String { "🔥 \(weeklyStreakWeeks) Week Training Streak" }
    /// Day streak for top of home: "🔥 X-Day Training Streak".
    private var dayStreakTitle: String { "🔥 \(trainingStreakDays)-Day Training Streak" }
    /// Button label for recommended activity: "Start 2-Minute Test" or activity name e.g. "Dribble or Pass".
    private var recommendedActivityButtonTitle: String {
        return RecommendationEngine.activityTitle(pinnedActivity)
    }
    /// Most recent Decision Speed Score for the current player (v1: any training activity so a just-completed block shows immediately).
    /// Score 0 is valid and must be displayed.
    private var homeDecisionSpeedScore: Int? {
        return localLatestScoredSession?.decisionSpeedScore
    }

    /// Last 7 training session scores from ProgressStore (oldest → newest). Used when dashboardData.trendScores is empty (e.g. no Supabase).
    private var localTrendScores: [Int] {
        let training: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        let list = progressStore.sessions.filter { training.contains($0.activity) && $0.playerId == playerId }
        let scores = Array(list.prefix(7)).compactMap(\.decisionSpeedScore)
        return scores.reversed()
    }

    /// Latest training session with a score (for Home score and local Performance Breakdown when dashboardData is nil). Newest-first so this is the most recent.
    private var localLatestScoredSession: SessionRecord? {
        let training: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        return progressStore.sessions.first { training.contains($0.activity) && $0.playerId == playerId && $0.decisionSpeedScore != nil }
    }
    /// Second-most-recent training session with a score (for "change since last session" when showing latest score from any activity).
    private var localPreviousScoredSession: SessionRecord? {
        let training: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        let scored = progressStore.sessions.filter { training.contains($0.activity) && $0.playerId == playerId && $0.decisionSpeedScore != nil }
        return scored.count >= 2 ? scored[1] : nil
    }
    /// Fast decision % from last 7 scored sessions (for Performance Breakdown when Supabase has no value).
    private var localFastPercent: Double? {
        let training: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        let scored = progressStore.sessions.filter { training.contains($0.activity) && $0.playerId == playerId && $0.decisionSpeedScore != nil }
        let withBucket = Array(scored.prefix(7)).compactMap(\.speedBucket)
        guard !withBucket.isEmpty else { return nil }
        let fastCount = withBucket.filter { $0 == .fast }.count
        return Double(fastCount) / Double(withBucket.count)
    }
    /// Change from previous scored session (any activity) so it matches the score we display.
    private var homeDecisionSpeedScoreChange: Int? {
        guard let cur = localLatestScoredSession?.decisionSpeedScore,
              let prev = localPreviousScoredSession?.decisionSpeedScore else { return nil }
        return cur - prev
    }
    /// True when we have exactly one scored training session for this player.
    private var isBaselineDecisionSpeedScore: Bool {
        localLatestScoredSession != nil && localPreviousScoredSession == nil
    }
    /// Recommended: 3 sessions (full blocks) per week.
    private static let weeklySessionGoal: Int = 3
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    @AppStorage(hasSeenIntroKey) private var hasSeenIntro = false
    @AppStorage(AppRole.storageKey) private var appRoleRaw: String = AppRole.player.rawValue
    @AppStorage("dashboardAudienceRoleV1") private var dashboardAudienceRoleRaw: String = ""

    private var lastAFPSessionResult: SessionResult? {
        profileManager.recentTrainSessions(limit: 20).first { $0.activityType == .awayFromPressure }
    }

    /// Most recent session (any activity) for Scan Efficiency snapshot.
    private var mostRecentSessionResult: SessionResult? {
        profileManager.recentTrainSessions(limit: 1).first
    }

    /// Scan Efficiency 0–100 from most recent session (accuracy + first-touch + speed).
    private var scanEfficiencyScore: Int? {
        guard let s = mostRecentSessionResult else { return nil }
        return Int(round(ScanEfficiency.score(from: s)))
    }

    /// Recent session results (for snapshot metrics). Uses profile for current player.
    private var recentSessionsForSnapshot: [SessionResult] {
        profileManager.recentTrainSessions(limit: 5)
    }

    /// Decision speed: average decision time in seconds from recent sessions that have avgDecisionTime. Nil if none.
    private var snapshotDecisionSpeedSeconds: Double? {
        let times = recentSessionsForSnapshot.compactMap { $0.avgDecisionTime }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    /// Trend for decision speed (lower is better): ↓ Improving when faster, ↑ Needs work when slower, → Stable when similar.
    private var snapshotDecisionSpeedTrend: String {
        let times = recentSessionsForSnapshot.compactMap { $0.avgDecisionTime }
        guard times.count >= 2 else { return "" }
        let newer = times[0], older = times[1]
        let diff = older - newer
        if diff > 0.05 { return "↓ Improving" }
        if diff < -0.05 { return "↑ Needs work" }
        return "→ Stable"
    }

    /// Trend for correct decisions (higher is better): ↑ Improving, → Stable, or ↓ Needs work from consistency label.
    private var snapshotCorrectTrend: String {
        guard last5.count >= 2 else { return "" }
        switch consistencyLabel {
        case .improving: return "↑ Improving"
        case .steady: return "→ Stable"
        case .streaky: return "↓ Needs work"
        }
    }

    /// Home trend always follows the current guided training focus.
    private var snapshotTrendActivity: ActivityKind { continueTrainingCardActivity }

    private enum HomeTrendMetric {
        case escapeRate
        case decisionRate
        case decisionWindow
        case balanced
    }

    private var snapshotTrendMetric: HomeTrendMetric {
        switch snapshotTrendActivity {
        case .awayFromPressure: return .escapeRate
        case .dribbleOrPass: return .decisionRate
        case .oneTouchPassing: return .decisionWindow
        case .twoMinuteTest: return .balanced
        }
    }

    /// Activity-specific sessions for the quick trend graph (oldest → newest).
    private var snapshotTrendActivitySessions: [SessionResult] {
        profileManager.sessionResultsForCharts()
            .filter { $0.activityType == snapshotTrendActivity }
    }

    private func sessionAccuracyPercent(_ session: SessionResult) -> Double? {
        guard session.totalReps > 0 else { return nil }
        return Double(session.correctCount) / Double(session.totalReps) * 100.0
    }

    private func sessionBalancedScore(_ session: SessionResult) -> Double? {
        guard let accuracy = sessionAccuracyPercent(session),
              let window = session.avgDecisionWindowSeconds else { return nil }
        let normalizedWindow = min(max((window + 0.15) / 0.45, 0.0), 1.0) * 100.0
        return (accuracy * 0.55) + (normalizedWindow * 0.45)
    }

    private var snapshotTrendTitle: String {
        switch snapshotTrendMetric {
        case .escapeRate:
            return "\(RecommendationEngine.activityTitle(snapshotTrendActivity)) — Correct First-Decision Trend"
        case .decisionRate:
            return "\(RecommendationEngine.activityTitle(snapshotTrendActivity)) — Correct Decision Trend"
        case .decisionWindow:
            return "\(RecommendationEngine.activityTitle(snapshotTrendActivity)) — Decision Timing Trend"
        case .balanced:
            return "\(RecommendationEngine.activityTitle(snapshotTrendActivity)) — Balanced Scan Trend"
        }
    }

    private var snapshotTrendValueLabel: String {
        switch snapshotTrendMetric {
        case .decisionWindow: return "s"
        case .escapeRate, .decisionRate, .balanced: return "%"
        }
    }

    /// Pin percent-based home trends to 0–100 so the axis never implies values above 100%.
    private var snapshotTrendYAxisRange: (Double, Double)? {
        switch snapshotTrendMetric {
        case .decisionWindow: return nil
        case .escapeRate, .decisionRate, .balanced: return (0, 100)
        }
    }

    private func snapshotTrendMetricValue(_ session: SessionResult) -> Double? {
        switch snapshotTrendMetric {
        case .escapeRate, .decisionRate:
            return sessionAccuracyPercent(session)
        case .decisionWindow:
            return session.avgDecisionWindowSeconds
        case .balanced:
            return sessionBalancedScore(session)
        }
    }

    /// Up to 7 points for current focus activity, based on its primary metric emphasis.
    private var snapshotTrendPoints: [ChartDataPoint] {
        let lastSeven = Array(snapshotTrendActivitySessions.suffix(7))
        return lastSeven.enumerated().compactMap { index, session in
            guard let value = snapshotTrendMetricValue(session) else { return nil }
            return ChartDataPoint(sessionIndex: index + 1, value: value)
        }
    }

    private var snapshotTrendPrimaryLabel: String {
        guard let latest = snapshotTrendActivitySessions.last else { return "—" }
        switch snapshotTrendMetric {
        case .escapeRate:
            return sessionAccuracyPercent(latest).map { "\(Int(round($0)))%" } ?? "—"
        case .decisionRate:
            return sessionAccuracyPercent(latest).map { "\(Int(round($0)))%" } ?? "—"
        case .decisionWindow:
            return latest.avgDecisionWindowSeconds.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—"
        case .balanced:
            return sessionBalancedScore(latest).map { "\(Int(round($0)))%" } ?? "—"
        }
    }

    private var snapshotTrendPrimaryMetricName: String {
        switch snapshotTrendMetric {
        case .escapeRate: return "Correct first decisions"
        case .decisionRate: return "Correct decisions"
        case .decisionWindow: return "Decision timing"
        case .balanced: return "Balanced score"
        }
    }

    /// Human-readable trend insight for the current focus activity.
    private var snapshotTrendInsightLine: String {
        let title = RecommendationEngine.activityTitle(snapshotTrendActivity)
        let latestValues = Array(snapshotTrendPoints.suffix(3)).map(\.value)
        guard latestValues.count >= 2 else { return "Complete more \(title) sessions to unlock trend insights." }
        let olderAvg = latestValues.dropLast().reduce(0, +) / Double(max(1, latestValues.count - 1))
        let newer = latestValues.last ?? olderAvg
        let delta = newer - olderAvg
        switch snapshotTrendMetric {
        case .escapeRate:
            if delta >= 3 { return "First-decision accuracy is improving in recent \(title) sessions." }
            if delta <= -3 { return "First-decision accuracy dipped in your last \(title) block — commit opposite the red earlier." }
            return "First-decision accuracy is stable across recent \(title) sessions."
        case .decisionRate:
            if delta >= 3 { return "Decision quality is improving in your recent \(title) blocks." }
            if delta <= -3 { return "Decision quality slipped in your last \(title) block — confirm the cue before committing." }
            return "Decision quality is stable across recent \(title) sessions."
        case .decisionWindow:
            if delta > 0.04 { return "You're deciding earlier relative to arrival in recent \(title) sessions." }
            if delta < -0.04 { return "You were later relative to arrival last \(title) session — reset early scans next block." }
            return "Your decision timing is stable in recent \(title) sessions."
        case .balanced:
            if delta >= 3 { return "Your timing and selection are improving together in recent training blocks." }
            if delta <= -3 { return "Your balance of timing and selection dipped in your latest session — reset and re-center next block." }
            return "Your timing-selection balance is stable across recent training sessions."
        }
    }

    /// Six chronological values (oldest → newest) for the current graph metric, for “Your Trend” (last 3 vs previous 3).
    private var lastSixMetricValuesForGraphInsight: [Double] {
        let sessions = snapshotTrendActivitySessions
        var collected: [Double] = []
        for s in sessions.reversed() {
            guard let v = snapshotTrendMetricValue(s) else { continue }
            collected.append(v)
            if collected.count == 6 { break }
        }
        guard collected.count == 6 else { return [] }
        return collected.reversed()
    }

    private struct HomeGraphInsight: Equatable {
        let recentAvg: Double
        let previousAvg: Double
        let trendLabel: String
        let interpretation: String
    }

    /// Trend from last six sessions: recentAvg = last 3, previousAvg = the three before that.
    private var homeGraphInsight: HomeGraphInsight? {
        let values = lastSixMetricValuesForGraphInsight
        guard values.count == 6 else { return nil }
        let previousAvg = (values[0] + values[1] + values[2]) / 3.0
        let recentAvg = (values[3] + values[4] + values[5]) / 3.0
        let higherIsBetter = snapshotTrendMetric != .decisionWindow
        let diff = recentAvg - previousAvg
        let threshold: Double = snapshotTrendMetric == .decisionWindow ? 0.04 : 3.0
        let trendLabel: String
        if abs(diff) <= threshold {
            trendLabel = "Inconsistent"
        } else if higherIsBetter {
            trendLabel = diff > 0 ? "Improving" : "Declining"
        } else {
            trendLabel = diff < 0 ? "Improving" : "Declining"
        }
        let interpretation: String
        switch trendLabel {
        case "Improving":
            interpretation = "You're recognizing the right option earlier — this leads to faster play under pressure."
        case "Inconsistent":
            interpretation = "You see the right option sometimes, but not consistently under pressure."
        default:
            interpretation = "Decisions are happening later — this will lead to turnovers in games."
        }
        return HomeGraphInsight(recentAvg: recentAvg, previousAvg: previousAvg, trendLabel: trendLabel, interpretation: interpretation)
    }

    /// Dashed reference at 80 on the 0–100 axis for first-decision and decision-correctness % charts only.
    /// Omitted for decision timing (seconds) and for balanced scan score (composite 0–100 — “80%” would misread as accuracy).
    private var graphTargetReferenceY: Double? {
        switch snapshotTrendMetric {
        case .escapeRate, .decisionRate: return 80
        case .balanced, .decisionWindow: return nil
        }
    }

    /// Shown only when `graphTargetReferenceY` is non-nil; wording matches the active `HomeTrendMetric`.
    private var graphTargetLabelText: String? {
        guard graphTargetReferenceY != nil else { return nil }
        switch snapshotTrendMetric {
        case .escapeRate:
            return "Target: 80% correct first decisions"
        case .decisionRate:
            return "Target: 80% correct decisions"
        case .balanced, .decisionWindow:
            return nil
        }
    }

    private func logGraphTargetLabelDebug() {
        let ref = graphTargetReferenceY
        let label = graphTargetLabelText
        let metricName: String = {
            switch snapshotTrendMetric {
            case .escapeRate: return "correct_first_decisions_pct"
            case .decisionRate: return "correct_decisions_pct"
            case .balanced: return "balanced_scan_score"
            case .decisionWindow: return "decision_window_seconds"
            }
        }()
        print("[GraphTargetLabel-Debug] metric=\(metricName) targetValue=\(ref.map { String($0) } ?? "nil") targetLabel=\(label ?? "nil") referenceLineShown=\(ref != nil)")
    }

    /// One short line under the Home graph (player-friendly; no formulas).
    private var homeGraphMicroExplanationPrimaryLine: String? {
        guard snapshotTrendPoints.count >= 2 else { return nil }
        switch snapshotTrendMetric {
        case .escapeRate:
            return ChartMetricDescriptions.correctFirstDecisionTrend
        case .decisionRate:
            return ChartMetricDescriptions.correctDecisionTrend
        case .decisionWindow:
            return ChartMetricDescriptions.decisionTiming
        case .balanced:
            return ChartMetricDescriptions.balancedScanTrend
        }
    }

    private func logGraphClarityDebug() {
        guard snapshotTrendPoints.count >= 2 else { return }
        let graphType: String = {
            switch snapshotTrendMetric {
            case .escapeRate: return "correct_first_decision_trend"
            case .decisionRate: return "correct_decision_trend"
            case .decisionWindow: return "decision_timing"
            case .balanced: return "balanced_scan_trend"
            }
        }()
        let text = homeGraphMicroExplanationPrimaryLine ?? ""
        print("[GraphClarityRefine-Debug] graphType=\(graphType) explanation=\"\(text)\"")
    }

    private var currentFocusActivitySessionsNewestFirst: [SessionResult] {
        profileManager.recentTrainSessions(limit: 20).filter { $0.activityType == continueTrainingCardActivity }
    }

    private var latestFocusSession: SessionResult? { currentFocusActivitySessionsNewestFirst.first }

    private var previousFocusSessionRecord: SessionRecord? {
        guard currentFocusActivitySessionsNewestFirst.count >= 2 else { return nil }
        return sessionRecord(from: currentFocusActivitySessionsNewestFirst[1])
    }

    private var coachInsightBody: String {
        guard let latest = latestFocusSession else {
            return "Complete your next block to unlock a personalized coaching insight."
        }
        return CoachInsightGenerator.coachInsight(for: latest, previous: previousFocusSessionRecord)
    }

    private func sessionRecord(from session: SessionResult) -> SessionRecord {
        let speedBucket = UniversalBlockSummaryHeadline.resolve(
            fast: session.speedCounts.fast,
            medium: session.speedCounts.medium,
            slow: session.speedCounts.slow
        ).bucket
        return SessionRecord(
            id: session.id,
            date: session.date,
            activity: session.activityType,
            gridSize: .fiveByFive,
            difficulty: session.difficulty ?? .standard,
            reps: session.totalReps,
            decisionsCompleted: session.totalReps,
            correct: session.correctCount,
            forwardCorrect: session.forwardChoiceCount,
            speedBucket: speedBucket,
            bias: session.biasDirection?.userFacingName,
            avgLatency: session.avgDecisionTime,
            profile: nil,
            playerId: session.playerID,
            decisionSpeedScore: session.estimatedDecisionSpeedScore
        )
    }

    /// Static benchmark: Elite Academy average decision speed (seconds). Lower is better.
    private static let eliteAcademyAverageDecisionSpeed: Double = 0.60

    /// Best (fastest) decision speed in seconds for current player. Nil if none.
    private var bestDecisionSpeedSeconds: Double? { profileManager.fastestDecisionSpeedSeconds() }
    /// Decision consistency from most recent session (for recommendation).
    private var introViewDecisionConsistency: DecisionConsistencyLabel? {
        DecisionConsistencyLabel.from(session: mostRecentSessionResult)
    }

    /// Automatic recommendation by player level with overrides for timing, bias, consistency.
    private var trainingRecommendation: TrainingRecommendationResult {
        TrainingRecommendation.recommend(progressStore: progressStore, playerId: playerId, last5: last5, hasCompletedInitialTest: hasCompletedInitialTest, lastAFPSessionResult: lastAFPSessionResult, decisionConsistency: introViewDecisionConsistency)
    }

    /// Guided next activity from curriculum stage progression.
    private var pinnedActivity: ActivityKind { guidedProgress.nextActivity }

    /// Activity shown in the yellow card.
    private var continueTrainingCardActivity: ActivityKind {
        return pinnedActivity
    }

    /// Route for the first screen of this activity’s flow (role selection). Train Now uses this so the whole flow stays on the path-based stack.
    private func routeForTrainNowActivity(_ activity: ActivityKind) -> AppRoute {
        PBASessionFlowPolicy.routeForActivityLaunch(activity)
    }

    /// Home segmented control: Solo vs Partner (``HomeTrainingModeSegment``).
    private var selectedMode: TrainingMode {
        homeTrainingModeSegment == .solo ? .solo : .partner
    }

    private func startActivity(_ activity: ActivityKind) {
        navigateToActivity(activity, mode: selectedMode)
    }

    @ViewBuilder
    private func homeActivityButton(_ title: String, activity: ActivityKind) -> some View {
        Button {
            startActivity(activity)
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.yellow)
                .cornerRadius(14)
        }
        .buttonStyle(HomeActivityLaunchButtonStyle())
    }

    private func navigateToActivity(_ activity: ActivityKind, mode: TrainingMode) {
        print("Starting activity with mode:", mode)
        PBASessionFlowPolicy.persistTrainingMode(mode)
        let route: AppRoute
        switch activity {
        case .dribbleOrPass:
            route = .dribbleOrPass(mode: mode)
        case .oneTouchPassing:
            route = .oneTouchPassing(mode: mode)
        case .awayFromPressure:
            route = .awayFromPressure(mode: mode)
        case .twoMinuteTest:
            route = .twoMinuteTest(mode: mode)
        }
        router.pushRespectingCoachRemotePadGate(route, coachRemotePrompt: coachRemoteRequiredPrompt)
    }

    /// Quick entry: open a full session using the current Home training mode.
    private var homeActivityLaunchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start Training")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                homeActivityButton("Dribble or Pass", activity: .dribbleOrPass)
                homeActivityButton("One-Touch Passing", activity: .oneTouchPassing)
                homeActivityButton("Away From Pressure", activity: .awayFromPressure)
                homeActivityButton(ActivityKind.twoMinuteTest.displayName, activity: .twoMinuteTest)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ordered list of 3 activities for Recommended Daily Training (guided activity first).
    private var dailyPlanBlocks: [ActivityKind] {
        let trainingActivities: [ActivityKind] = [.awayFromPressure, .dribbleOrPass, .oneTouchPassing]
        let recommended = guidedProgress.nextActivity
        guard trainingActivities.contains(recommended) else {
            return trainingActivities
        }
        let rest = trainingActivities.filter { $0 != recommended }
        return [recommended] + rest
    }

    /// Focus line for guided next training card.
    private var focusText: String { guidedProgress.focus }
    #if DEBUG
    private var wedgeDifficultyLevel: Int { WedgeDifficultyEngine.currentLevel(playerId: playerId) }
    #endif
    /// True when this player has no completed sessions in ProgressStore yet.
    /// Uses `hasCompletedInitialTest` so a guest baseline (or merged account flag) still skips the first-run card after sign-in when ProgressStore rows are keyed to another id.
    private var needsBaselineAssessment: Bool {
        if hasCompletedInitialTest { return false }
        let hasTrainingSessions = progressStore.sessions.contains { $0.playerId == playerId }
        let baselineCompleted = GuidedCurriculumEngine.hasCompletedBaseline(playerId: playerId)
        return !hasTrainingSessions && !baselineCompleted
    }

    /// Skill progression: next activity and message (accuracy, reaction time, decision speed score mastery).
    private var skillProgressionRecommendation: SkillProgressionRecommendation? {
        SkillProgressionEngine.recommendedNextActivity(progressStore: progressStore, playerId: playerId)
    }

    /// Guided mastery stage for the current recommended focus (perception path order: AFP=1, DOP=2, OTP=3).
    private var nextTrainingStageLabel: String {
        switch continueTrainingCardActivity {
        case .awayFromPressure: return "Stage 1 of 3"
        case .dribbleOrPass: return "Stage 2 of 3"
        case .oneTouchPassing: return "Stage 3 of 3"
        case .twoMinuteTest: return "Stage 1 of 3"
        }
    }

    /// iPad in player display mode: data and pairing only; sessions start from Coach Remote.
    private var isPadPlayerPresentationMode: Bool {
        CoachRemoteSessionStartGate.isPadPlayerRole()
    }

    /// iPad in **player** role is usually a passive field display for Coach Remote, so local “Start” buttons are hidden. If the user chose **Solo** (or Wall), allow the same self-start flow as on iPhone. Partner mode still shows the passive “coach runs from the phone” copy when appropriate.
    private var canStartLocalTrainingFromHome: Bool {
        if !isPadPlayerPresentationMode { return true }
        return homeTrainingModeSegment == .solo
    }

    /// Encouragement message for Today's Goal based on blocks completed today.
    private var todayGoalEncouragement: String {
        switch dailyCompleted {
        case 0: return "Complete \(dailyTarget) blocks today."
        case 1: return "Nice start — keep going."
        case 2: return "One more to reach today's goal."
        default: return "Goal achieved today. Great work."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if Config.isSupabaseConfigured, authManager.currentSession == nil {
                Button {
                    showLoginSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "icloud")
                        Text("Sign in")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                }
                .buttonStyle(.plain)
            }
            homePlayerBar
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)

            Spacer()

            homeMainTrainingSection
                .padding(.horizontal, 28)
                .offset(y: 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(homeScreenBackground)
        .task(id: "home-launch-setup") {
            await performHomeLaunchSetup()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
#if DEBUG
            if AppConfig.testerMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Tester Tools") {
                        router.push(.debugMenu)
                    }
                    .foregroundColor(.white.opacity(0.9))
                }
            }
#endif
            if !isPadPlayerPresentationMode {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Switch to Coach Remote") {
                            let old = appRoleRaw
                            appRoleRaw = AppRole.coachRemote.rawValue
                            router.popToRoot()
                            AppRoleDebug.log("role_change reason=home_menu_coach old=\(old) new=\(AppRole.coachRemote.rawValue) routing=coach_remote_root")
                        }
                    } label: {
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .accessibilityLabel("Switch device role")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.profileInsights)
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.75))
                }
                .accessibilityLabel("Profile, progress and insights")
            }
            if Config.isSupabaseConfigured, authManager.currentSession != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSwitchPlayerConfirmation = true
                    } label: {
                        Image(systemName: "person.2")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .accessibilityLabel("Switch Player")
                    .disabled(signOutUXPhase != .idle)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .accessibilityLabel("Use a Different Account")
                    .disabled(signOutUXPhase != .idle)
                }
            }
        }
        .alert("Switch Player?", isPresented: $showSwitchPlayerConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Switch Player") {
                SwitchPlayerService.performSwitchPlayer(
                    profileManager: profileManager,
                    playerStore: playerStore,
                    router: router
                )
            }
        } message: {
            Text("You’ll return to player selection so another player can continue.")
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                print("[SignOut-UX] sign-out confirm tapped")
                hasSeenIntro = false
                Task {
                    await SignOutUXRunner.run(
                        phase: $signOutUXPhase,
                        profileManager: profileManager,
                        playerStore: playerStore,
                        progressStore: progressStore,
                        router: router
                    )
                }
            }
        } message: {
            Text("You’ll return to the sign-in screen and can use a different account.")
        }
        .alert(snapshotMetricInfoToShow?.title ?? "", isPresented: Binding(
            get: { snapshotMetricInfoToShow != nil },
            set: { if !$0 { snapshotMetricInfoToShow = nil } }
        )) {
            Button("OK", role: .cancel) { snapshotMetricInfoToShow = nil }
        } message: {
            if let msg = snapshotMetricInfoToShow?.message {
                Text(msg)
            }
        }
        .sheet(isPresented: $showPlayersSheet) {
            PlayersSheetView(profileManager: profileManager)
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBeepSelector) {
            PBABeepSelectorView()
        }
        .sheet(isPresented: $showHowItWorks) { HowItWorksView() }
        .overlay {
            if showStatusUpgrade, let s = upgradedStatus {
                statusUpgradeToast(status: s)
            }
        }
        .overlay {
            if let modal = activeProgressModal {
                progressModalView(modal)
                    .scaleEffect(progressModalScale)
                    .opacity(progressModalOpacity)
                    .onAppear {
                        progressModalScale = 0.92
                        progressModalOpacity = 0
                        withAnimation(.easeOut(duration: 0.2)) {
                            progressModalScale = 1.0
                            progressModalOpacity = 1.0
                        }
                        triggerProgressHaptic()
                    }
            }
        }
        .task(id: playerId?.uuidString) {
            dashboardData = await HomeDashboardDataService.shared.fetchDashboardData(playerId: playerId)
            refreshGuidedProgress()
        }
        .onAppear {
            showsTopToggle = false
            checkStatusUpgrade()
            popToRootTrigger.request = false
            profileManager.ensureWeeklyRolloverIfNeeded()
            refreshGuidedProgress()
        }
        .onChange(of: playerId?.uuidString) {
            refreshGuidedProgress()
        }
        .onDisappear { showsTopToggle = true }
    }

    private func refreshGuidedProgress() {
        let previousStage = loadLastSeenStage()
        let previousLoop = loadLastSeenLoop()
        let previousTier = loadLastSeenTier()
        let previousIdentity = PlayerIdentityEngine.loadLastIdentity(playerId: playerId)
        let previousStats = rollingPerformanceStats()
        let selectedProfileSessions = profileManager.profile(id: playerId)?.sessionResults ?? []
        let newIdentity = PlayerIdentityEngine.confirmedIdentity(from: selectedProfileSessions, previousIdentity: previousIdentity)
        currentPlayerIdentity = newIdentity ?? previousIdentity
        trendingIdentity = PlayerIdentityEngine.trendingTowardIdentity(from: selectedProfileSessions, currentIdentity: currentPlayerIdentity)
        let wedgeDifficultyIncreased = WedgeDifficultyEngine.evaluateAndAdvanceIfNeeded(playerId: playerId, sessions: selectedProfileSessions)
        let wedgeDifficultyLevel = WedgeDifficultyEngine.currentLevel(playerId: playerId)
        guidedProgress = GuidedCurriculumEngine.evaluateAndAdvance(
            playerId: playerId,
            sessions: selectedProfileSessions
        )
        let newStats = rollingPerformanceStats()
        evaluateProgressModals(
            previousStage: previousStage,
            previousLoop: previousLoop,
            previousTier: previousTier,
            previousIdentity: previousIdentity,
            newIdentity: newIdentity,
            previousStats: previousStats,
            newStats: newStats,
            sessions: selectedProfileSessions,
            wedgeDifficultyIncreased: wedgeDifficultyIncreased,
            wedgeDifficultyLevel: wedgeDifficultyLevel
        )
        saveLastSeenStage(guidedProgress.stage)
        saveLastSeenLoop(guidedProgress.loop)
        if let tier = newStats.tier {
            saveLastSeenTier(tier)
        }
        if let newIdentity {
            PlayerIdentityEngine.saveIdentity(newIdentity, playerId: playerId)
        }
        #if DEBUG
        let selected = playerId?.uuidString ?? "nil"
        let currentProfileId = profileManager.currentProfile?.id.uuidString ?? "nil"
        let afpSessions = selectedProfileSessions.filter { $0.activityType == .awayFromPressure }
        let afpPlayerIds = afpSessions.map { $0.playerID.uuidString }.joined(separator: ",")
        let lastRecord = progressStore.last(pinnedActivity, playerId: playerId)
        let latestScored = localLatestScoredSession
        let snapshotFirst = recentSessionsForSnapshot.first
        let filteredForPlayer = progressStore.sessions.filter { $0.playerId == playerId }
        let nilPlayerSessions = progressStore.sessions.filter { $0.playerId == nil }.count
        print("[PBA-Debug] Home refresh: selectedPlayerId=\(selected), currentProfileId=\(currentProfileId), guided={\(GuidedCurriculumEngine.debugState(playerId: playerId))}")
        print("[PBA-Debug] Home refresh data: pinnedActivity=\(pinnedActivity.rawValue), lastRecord.playerId=\(lastRecord?.playerId?.uuidString ?? "nil"), latestScored.playerId=\(latestScored?.playerId?.uuidString ?? "nil"), snapshotFirst.playerId=\(snapshotFirst?.playerID.uuidString ?? "nil"), homeDecisionSpeedScore=\(homeDecisionSpeedScore.map(String.init) ?? "nil"), selectedPlayerSessions=\(filteredForPlayer.count), nilPlayerSessions=\(nilPlayerSessions), afpSessionCount=\(afpSessions.count), afpPlayerIds=[\(afpPlayerIds)]")
        #endif
    }

    private struct RollingStats {
        let avgTime: Double?
        let accuracyPercent: Int?
        let tier: String?
    }

    private func rollingPerformanceStats() -> RollingStats {
        let sessions = profileManager.profile(id: playerId)?.sessionResults ?? []
        let training = sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        let recent = Array(training.prefix(5))
        let times = recent.compactMap(\.avgDecisionTime)
        let avg = times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
        let validAccSessions = recent.filter { $0.totalReps > 0 }
        let acc: Int? = {
            guard !validAccSessions.isEmpty else { return nil }
            let avgAcc = validAccSessions.reduce(0.0) { $0 + (Double($1.correctCount) / Double($1.totalReps)) } / Double(validAccSessions.count)
            return Int(round(avgAcc * 100.0))
        }()
        let tier: String? = {
            guard let avg else { return nil }
            if avg < 0.90 { return "Elite" }
            if avg <= 1.10 { return "Strong" }
            if avg <= 1.20 { return "Developing" }
            return "Emerging"
        }()
        return RollingStats(avgTime: avg, accuracyPercent: acc, tier: tier)
    }

    private func tierRank(_ tier: String) -> Int {
        switch tier {
        case "Emerging": return 0
        case "Developing": return 1
        case "Strong": return 2
        case "Elite": return 3
        default: return -1
        }
    }

    private func evaluateProgressModals(previousStage: Int?, previousLoop: Int?, previousTier: String?, previousIdentity: PlayerIdentity?, newIdentity: PlayerIdentity?, previousStats: RollingStats, newStats: RollingStats, sessions: [SessionResult], wedgeDifficultyIncreased: Bool, wedgeDifficultyLevel: Int) {
        activeProgressModal = nil
    }

    private func recentAverageDecisionTime(from sessions: [SessionResult]) -> Double? {
        let training = sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        let recent = Array(training.prefix(3)).compactMap(\.avgDecisionTime)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    private func earlyAverageDecisionTime(from sessions: [SessionResult]) -> Double? {
        let training = sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }
        let early = Array(training.suffix(3)).compactMap(\.avgDecisionTime)
        guard !early.isEmpty else { return nil }
        return early.reduce(0, +) / Double(early.count)
    }

    private func recentAccuracyPercent(from sessions: [SessionResult]) -> Double? {
        let training = Array(sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }.prefix(3))
        let valid = training.filter { $0.totalReps > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0.0) { $0 + (Double($1.correctCount) / Double($1.totalReps) * 100.0) } / Double(valid.count)
    }

    private func earlyAccuracyPercent(from sessions: [SessionResult]) -> Double? {
        let training = Array(sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }.suffix(3))
        let valid = training.filter { $0.totalReps > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0.0) { $0 + (Double($1.correctCount) / Double($1.totalReps) * 100.0) } / Double(valid.count)
    }

    private func recentForwardThinkingPercent(from sessions: [SessionResult]) -> Double? {
        let training = Array(sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }.prefix(3))
        let values = training.compactMap { s -> Double? in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choices = s.forwardChoiceCount else { return nil }
            return Double(choices) / Double(opp) * 100.0
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func earlyForwardThinkingPercent(from sessions: [SessionResult]) -> Double? {
        let training = Array(sessions.filter { [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains($0.activityType) }.suffix(3))
        let values = training.compactMap { s -> Double? in
            guard let opp = s.forwardOpportunityCount, opp > 0, let choices = s.forwardChoiceCount else { return nil }
            return Double(choices) / Double(opp) * 100.0
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func metricChangeText(oldValue: Double?, newValue: Double?, unit: String, lowerIsBetter: Bool) -> String? {
        guard let oldValue, let newValue else { return nil }
        let delta = newValue - oldValue
        let improved = lowerIsBetter ? (delta < 0) : (delta > 0)
        let symbol = improved ? "▲" : "▼"
        if unit == "s" {
            return String(format: "%@ %.2f%@ → %.2f%@", symbol, oldValue, unit, newValue, unit)
        }
        return String(format: "%@ %.0f%@ → %.0f%@", symbol, oldValue, unit, newValue, unit)
    }

    private func progressModalView(_ modal: ProgressModalType) -> some View {
        VStack(spacing: 12) {
            switch modal {
            case .levelUp:
                Text("Session Update")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.yellow)
                Text("Keep training to log more reps.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                Button("Continue") {
                    dismissProgressModal()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow)
                .cornerRadius(12)
            case .stageUnlocked(let stage, let activity):
                Text("Stage Unlocked")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.yellow)
                Text(RecommendationEngine.activityTitle(activity))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Text(stageUnlockMessage(for: stage))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                if !canStartLocalTrainingFromHome {
                    Button("OK") {
                        dismissProgressModal()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    Text("Your coach starts training from Coach Remote on a phone.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                } else {
                    Button("Start Stage \(stage)") {
                        dismissProgressModal()
                        router.pushRespectingCoachRemotePadGate(routeForTrainNowActivity(activity), coachRemotePrompt: coachRemoteRequiredPrompt)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    Button("Keep Training") {
                        dismissProgressModal()
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                }
            case .curriculumComplete(_, _, _, let recommendedActivity):
                Text("Curriculum Complete")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.yellow)
                Text("You completed all 3 stages.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                Text("Next Focus: \(RecommendationEngine.activityTitle(recommendedActivity))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                if !canStartLocalTrainingFromHome {
                    Button("OK") {
                        dismissProgressModal()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    Text("Your coach starts the next focus from Coach Remote.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                } else {
                    Button("Start Next Focus") {
                        dismissProgressModal()
                        router.pushRespectingCoachRemotePadGate(routeForTrainNowActivity(recommendedActivity), coachRemotePrompt: coachRemoteRequiredPrompt)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    Button("Keep Training") {
                        dismissProgressModal()
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                }
            case .adaptiveWedgeDifficulty:
                Text("Your training just got sharper.")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.yellow)
                Text("You're reacting faster, so cues will be slightly less obvious.\nThis will help you read earlier and decide quicker.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                Button("Keep Training") {
                    dismissProgressModal()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow)
                .cornerRadius(12)
            case .badgeTierUnlocked(let event):
                Text("Level Up!")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.yellow)
                Image(systemName: event.track.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.yellow)
                Text("\(event.track.title) \(romanNumeral(event.level))")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Text("New tier unlocked")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                Button("Keep Training") {
                    dismissProgressModal()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow)
                .cornerRadius(12)
            case .identityChanged(let identity):
                Text("New Identity")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.yellow)
                Text(identity.title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Text(identity.changeMessage)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                Button("Keep Training") {
                    dismissProgressModal()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow)
                .cornerRadius(12)
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(Color.black.opacity(0.9))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .onTapGesture {}
    }

    private func stageUnlockMessage(for stage: Int) -> String {
        switch stage {
        case 2: return "You're ready to choose actions under pressure."
        case 3: return "You're ready to decide before expected arrival."
        default: return "You've unlocked the next challenge."
        }
    }

    private func romanNumeral(_ level: Int) -> String {
        switch level {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        default: return "I"
        }
    }

    private func dismissProgressModal() {
        withAnimation(.easeIn(duration: 0.16)) {
            progressModalOpacity = 0
            progressModalScale = 0.96
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            activeProgressModal = nil
            refreshGuidedProgress()
        }
    }

    private func progressKey(_ base: String) -> String {
        let pid = playerId?.uuidString ?? "global"
        return "\(base)_\(pid)"
    }

    private func loadLastSeenTier() -> String? {
        UserDefaults.standard.string(forKey: progressKey("pba_last_seen_tier"))
    }

    private func saveLastSeenTier(_ tier: String) {
        UserDefaults.standard.set(tier, forKey: progressKey("pba_last_seen_tier"))
    }

    private func loadLastSeenStage() -> Int? {
        let v = UserDefaults.standard.integer(forKey: progressKey("pba_last_seen_stage"))
        return v == 0 ? nil : v
    }

    private func saveLastSeenStage(_ stage: Int) {
        UserDefaults.standard.set(stage, forKey: progressKey("pba_last_seen_stage"))
    }

    private func loadLastSeenLoop() -> Int? {
        let v = UserDefaults.standard.integer(forKey: progressKey("pba_last_seen_loop"))
        return v == 0 ? nil : v
    }

    private func saveLastSeenLoop(_ loop: Int) {
        UserDefaults.standard.set(loop, forKey: progressKey("pba_last_seen_loop"))
    }

    private func triggerProgressHaptic() {
#if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
#endif
    }

#if DEBUG
    private func resetCurriculumForSelectedPlayer() {
        guidedProgress = GuidedCurriculumEngine.resetCurriculumForPlayer(
            playerId: playerId,
            baselineCompleted: false
        )
        refreshGuidedProgress()
    }
#endif

    /// 1. Current Focus card (top): single dominant guided CTA with stage + path context.
    private var dailyGoalCard: some View {
        Group {
            if needsBaselineAssessment {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Your Training")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("Train your first touch under pressure so we can personalize your path. Takes 2 minutes.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !canStartLocalTrainingFromHome {
                        Text("Your coach runs \(ActivityKind.twoMinuteTest.displayName) from Coach Remote on a phone.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button {
                            guard !isNavigatingToTraining else { return }
                            isNavigatingToTraining = true
                            isStartTrainingPressed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                isStartTrainingPressed = false
                                router.pushRespectingCoachRemotePadGate(PBASessionFlowPolicy.routeForActivityLaunch(.twoMinuteTest), coachRemotePrompt: coachRemoteRequiredPrompt)
                                isNavigatingToTraining = false
                            }
                        } label: {
                            Text("Start \(ActivityKind.twoMinuteTest.displayName)")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.yellow)
                                .cornerRadius(14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isStartTrainingPressed ? 0.98 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isStartTrainingPressed)
                        .disabled(isNavigatingToTraining)
                        .accessibilityLabel("Start \(ActivityKind.twoMinuteTest.displayName)")
                        .accessibilityHint("Double tap to start your first training session.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Focus")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(RecommendationEngine.activityTitle(continueTrainingCardActivity))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    HStack {
                        Text(nextTrainingStageLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.yellow)
                        Spacer()
                        Text("Loop \(guidedProgress.loop)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text("Focus: \(focusText)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                    if !canStartLocalTrainingFromHome {
                        Text("Training is started from Coach Remote on your coach’s phone.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button {
                            guard !isNavigatingToTraining else { return }
                            isNavigatingToTraining = true
                            isStartTrainingPressed = true
                            let route = routeForTrainNowActivity(continueTrainingCardActivity)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                isStartTrainingPressed = false
                                router.pushRespectingCoachRemotePadGate(route, coachRemotePrompt: coachRemoteRequiredPrompt)
                                isNavigatingToTraining = false
                            }
                        } label: {
                            Text("Start Training")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.yellow)
                                .cornerRadius(14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isStartTrainingPressed ? 0.98 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isStartTrainingPressed)
                        .disabled(isNavigatingToTraining)
                        .accessibilityLabel("Start Training")
                        .accessibilityHint("Double tap to continue the guided training path.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var trainingPathIndicator: some View {
        HStack(spacing: 8) {
            stageDot(1, title: "AFP")
            stageConnector
            stageDot(2, title: "DOP")
            stageConnector
            stageDot(3, title: "OTP")
        }
    }

    private var currentStageIndex: Int {
        switch continueTrainingCardActivity {
        case .awayFromPressure: return 1
        case .dribbleOrPass: return 2
        case .oneTouchPassing: return 3
        case .twoMinuteTest: return 1
        }
    }

    private func stageDot(_ stage: Int, title: String) -> some View {
        let isActive = stage == currentStageIndex
        let isCompleted = stage < currentStageIndex
        return HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.yellow : (isCompleted ? Color.green : Color.white.opacity(0.35)))
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption2.weight(isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .yellow : .white.opacity(0.75))
        }
    }

    private var stageConnector: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    /// 2. Decision Speed Score: latest score and improvement since previous session. Uses same source as Player progress (ProgressStore) so both cards stay in sync.
    private var decisionSpeedScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Decision Speed Score")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            // Important: score 0 is valid and must be displayed. Only nil means no data.
            switch homeDecisionSpeedScore {
            case .some(let score):
                Text("\(score)")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)
                if isBaselineDecisionSpeedScore {
                    Text("Starting Score")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.yellow)
                }
                if score == 0 {
                    Text("Coach Note: Your decisions are being logged, but they are currently landing in the slow range. Keep training to raise this score.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                homeImprovementText
            case .none:
                Text("—")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white.opacity(0.7))
                Text("Complete a session to see your score.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Improvement text from ProgressStore (same source as homeDecisionSpeedScore) so top and Player progress section never disagree.
    private var homeImprovementText: some View {
        Group {
            if let change = homeDecisionSpeedScoreChange {
                Text(change == 0 ? "Same as last session" : (change > 0 ? "+\(change)" : "\(change)") + " since last session")
                    .font(.subheadline)
                    .foregroundColor(change >= 0 ? .green : .white.opacity(0.9))
            } else {
                Text("First session — no comparison yet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    /// 3. Progress Trend: last 7 decision_speed_score values (oldest → newest). Uses Supabase when available and non-empty, else local ProgressStore so recent blocks show immediately.
    private var progressTrendSection: some View {
        let trend = (dashboardData?.trendScores).flatMap { $0.isEmpty ? nil : $0 } ?? localTrendScores
        return VStack(alignment: .leading, spacing: 10) {
            Text("Progress Trend")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            if !trend.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(trend.reversed().enumerated()), id: \.offset) { index, value in
                            Text("\(value)")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                            if index < trend.count - 1 {
                                Text("→")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No trend data yet. Complete sessions to see your progress.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 4. Performance Breakdown: Accuracy %, Average Reaction Time, Fast Decision %. Uses Supabase when available and non-empty, else local ProgressStore so recent blocks show immediately.
    private var performanceBreakdownSection: some View {
        let acc = dashboardData?.accuracy ?? localLatestScoredSession.flatMap { s in s.decisionsCompleted > 0 ? Double(s.correct) / Double(s.decisionsCompleted) : nil }
        let avgReactionMs = dashboardData?.avgReactionMs ?? localLatestScoredSession.flatMap { $0.avgLatency }.map { $0 * 1000 }
        let fastPercent = dashboardData?.fastPercent ?? localFastPercent
        let avgSeconds = avgReactionMs.map { $0 / 1000.0 }
        let decisionZone: String? = avgSeconds.map { t in
            if t < 0.90 { return "Early" }
            if t <= 1.10 { return "On Time" }
            if t <= 1.20 { return "Late" }
            return "Too Late"
        }
        let decisionZoneEmoji: String = {
            switch decisionZone {
            case "Early": return "🟢"
            case "On Time": return "🔵"
            case "Late": return "🟠"
            case "Too Late": return "🔴"
            default: return "⚪"
            }
        }()
        let decisionMessage: String? = {
            switch decisionZone {
            case "Late": return "You're close — commit slightly earlier."
            case "Too Late": return "Decisions are coming too late — scan earlier."
            case "On Time": return "Good timing — push toward earlier decisions."
            case "Early": return "Excellent — you're deciding early."
            default: return nil
            }
        }()
        let nextTargetText: String? = {
            switch decisionZone {
            case "Too Late": return "Next Target: Late (< 1.20s)"
            case "Late": return "Next Target: On Time (< 1.10s)"
            case "On Time": return "Next Target: Early (< 0.90s)"
            case "Early": return "Next Target: Keep Early consistently"
            default: return nil
            }
        }()
        let zoneProgress: Double? = avgSeconds.map { t in
            let minSec = 0.80
            let maxSec = 1.30
            let normalized = (t - minSec) / (maxSec - minSec)
            return max(0.0, min(1.0, 1.0 - normalized))
        }
        let accuracyMessage: String? = {
            guard let acc else { return nil }
            if acc >= 0.90, decisionZone == "Late" || decisionZone == "Too Late" {
                return "Excellent accuracy — now focus on deciding faster."
            }
            if acc < 0.75 {
                return "Slow down slightly to improve decision quality."
            }
            return nil
        }()
        let latestForwardThinkingPercent: Int? = {
            let sessions = profileManager.profile(id: playerId)?.sessionResults ?? []
            guard let latestWithForward = sessions.first(where: { ($0.forwardOpportunityCount ?? 0) > 0 }),
                  let opp = latestWithForward.forwardOpportunityCount,
                  let choice = latestWithForward.forwardChoiceCount,
                  opp > 0 else { return nil }
            return Int(round(Double(choice) / Double(opp) * 100.0))
        }()
        let forwardMessage: String? = {
            guard let pct = latestForwardThinkingPercent else { return nil }
            if pct < 50 { return "Look forward more when space is available." }
            if pct < 70 { return "Good forward intent — keep spotting forward options." }
            return "Excellent forward thinking."
        }()
        let overallSummary: String? = {
            guard let zone = decisionZone, let acc else { return nil }
            let accuracyStrong = acc >= 0.85
            if (zone == "Late" || zone == "Too Late") && accuracyStrong {
                return "You're accurate, but slightly late. Speed up your decision timing to unlock higher-level play."
            }
            if zone == "On Time" && accuracyStrong {
                return "Good balance: accurate and on time. Push toward earlier decisions."
            }
            if zone == "Early" && accuracyStrong {
                return "Excellent profile: early decisions with strong accuracy."
            }
            return "Keep building: improve both timing and decision quality."
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Performance Breakdown")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            if let zone = decisionZone, let sec = avgSeconds {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Decision Speed")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                    Text("\(decisionZoneEmoji) \(zone) (\(String(format: "%.2fs", sec)))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    if let p = zoneProgress {
                        decisionZoneProgressBar(progress: p)
                    }
                    if let decisionMessage {
                        Text(decisionMessage)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.86))
                    }
                    if let nextTargetText {
                        Text(nextTargetText)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.yellow.opacity(0.95))
                    }
                }
            }

            if let acc = acc {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                    Text("🟢 \(Int(round(acc * 100)))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    if let accuracyMessage {
                        Text(accuracyMessage)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.86))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Forward Thinking")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                if let forwardPct = latestForwardThinkingPercent {
                    Text("\(forwardPct)%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    if let forwardMessage {
                        Text(forwardMessage)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.86))
                    }
                } else {
                    Text("Complete more sessions to unlock")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
            }

            if let overallSummary {
                Text(overallSummary)
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.95))
                    .padding(.top, 2)
            }

            HStack(spacing: 12) {
                if let score = homeDecisionSpeedScore {
                    Text("Score: \(score)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                }
                if let fast = fastPercent {
                    Text("Fast %: \(Int(round(fast * 100)))%")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                }
            }
            if acc == nil && avgReactionMs == nil && fastPercent == nil {
                Text("Complete a session to see performance stats.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decisionZoneProgressBar(progress: Double) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let markerX = CGFloat(progress) * width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.9),
                                Color.orange.opacity(0.9),
                                Color.blue.opacity(0.9),
                                Color.green.opacity(0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                    .offset(x: max(0, min(width - 12, markerX - 6)))
            }
        }
        .frame(height: 12)
        .overlay(
            HStack {
                Text("Too Late")
                Spacer()
                Text("Late")
                Spacer()
                Text("On Time")
                Spacer()
                Text("Early")
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.72))
            .offset(y: 12),
            alignment: .bottom
        )
        .padding(.bottom, 12)
    }

    /// 5. Training Streak: current streak in days.
    private var trainingStreakSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Training Streak")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            HStack(spacing: 6) {
                Text("\(trainingStreakDays) days")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Text("🔥")
                    .font(.title3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playerSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Snapshot")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            if last5.count >= 2 {
                snapshotMetricRow(label: "Decision Speed", value: snapshotDecisionSpeedSeconds.map { String(format: "%.2fs", $0) } ?? "—", trend: snapshotDecisionSpeedTrend, leadingIcon: "bolt.fill")
                snapshotMetricRow(label: "Correct Decisions", value: "\(decisionScore)%", trend: snapshotCorrectTrend)
            } else if hasAnyBlock {
                Text("Run your first block to get your score.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Run your first block to get your score.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(weeklyStreakTitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Text("\(weeklyStreakWeeks) week streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text("Complete 3 sessions this week to keep your streak alive.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
    }

    private func snapshotMetricRow(label: String, value: String, trend: String, leadingIcon: String? = nil) -> some View {
        HStack {
            if let icon = leadingIcon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text(value)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.95))
                if !trend.isEmpty {
                    Text(trend)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }

    /// Recommended Daily Training: 3 blocks (recommended first), ~10 min, Start Training launches first activity.
    private var recommendedDailyTrainingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommended Daily Training")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("About 10 minutes")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(dailyPlanBlocks.enumerated()), id: \.element) { index, activity in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Block \(index + 1)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 52, alignment: .leading)
                        Text(activity.displayName)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.95))
                        Text("— 12 reps")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
            Button {
                router.pushRespectingCoachRemotePadGate(routeForTrainNowActivity(dailyPlanBlocks[0]), coachRemotePrompt: coachRemoteRequiredPrompt)
            } label: {
                Text("Start Training")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    /// Personal Bests: Fastest Decision Speed (with band + explanation), best away-from-pressure first-decision accuracy, Best Forward Thinking.
    private var personalBestsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🏆 Personal Bests")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            personalBestDecisionSpeedRow(session: profileManager.sessionResultsForCharts().max {
                ($0.avgDecisionWindowSeconds ?? -.greatestFiniteMagnitude) < ($1.avgDecisionWindowSeconds ?? -.greatestFiniteMagnitude)
            })
            personalBestRow(label: "Best AFP first-decision accuracy", value: profileManager.bestPressureEscapePercent().map { String(format: "%.0f%%", $0) })
            personalBestRow(label: "Best Forward Thinking", value: profileManager.bestForwardIntentPercent().map { String(format: "%.0f%%", $0) })
        }
    }

    private func personalBestDecisionSpeedRow(session: SessionResult?) -> some View {
        let window = session?.avgDecisionWindowSeconds
        return HStack(alignment: .top) {
            Text("Best decision timing")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(window.map { DecisionTimingModel.summaryText(windowSeconds: $0) } ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white.opacity(0.95))
                if let s = session, let band = DecisionSpeedBand.band(forSession: s) {
                    Text(band.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(band.color)
                    Text(band.explanation)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func personalBestRow(label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Spacer(minLength: 8)
            Text(value ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.white.opacity(0.95))
        }
    }

    private func performHomeLaunchSetup() async {
        let logoName = Self.homeLogoWatermarkImageName
        async let persistedMode = Task.detached(priority: .userInitiated) {
            PBASessionFlowPolicy.lastSelectedTrainingMode()
        }.value
        async let logo = Task.detached(priority: .utility) {
            UIImage(named: logoName)
        }.value

        switch await persistedMode {
        case .solo:
            homeTrainingModeSegment = .solo
        case .partner, .wall:
            homeTrainingModeSegment = .partner
        }
        homeLogoWatermark = await logo
        highlightPrimaryAction = false
        try? await Task.sleep(for: .milliseconds(400))
        highlightPrimaryAction = true
    }

    private func startPartnerSession() {
        let coordinator = TrainingPartnerConnectionCoordinator.shared
        if coordinator.isPartnerTrainingSessionActive {
            return
        }
        let mode: TrainingMode = .partner
        PBASessionFlowPolicy.persistTrainingMode(mode)
        router.push(.partnerPairing)
    }

    private var showsHomeStartSession: Bool {
        homeTrainingModeSegment == .partner || canStartLocalTrainingFromHome
    }

    private static let homeLogoWatermarkImageName = "pba_logo"

    /// Gradient + subtle brand watermark behind all home UI (non-interactive).
    private var homeScreenBackground: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            if let homeLogoWatermark {
                Image(uiImage: homeLogoWatermark)
                    .resizable()
                    .scaledToFit()
                    .blur(radius: 0.5)
                    .opacity(0.06)
                    .padding(.horizontal, 60)
                    .offset(y: -60)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    private var homeStartSessionTitle: String {
        "Start Session"
    }

    private var homeStartSessionScale: CGFloat {
        if isStartSessionPressed { return 0.97 }
        return highlightPrimaryAction ? 1.02 : 1.0
    }

    /// Top: player selector only (toolbar holds small utility icons).
    private var homePlayerBar: some View {
        HStack {
            Button {
                hasSeenPlayerSwitcherTooltip = true
                showPlayersSheet = true
            } label: {
                HStack(spacing: 6) {
                    Text(playerStore.selectedPlayer?.name ?? "Player")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("▼")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Selected player profile")
            Spacer()
        }
    }

    /// Main training controls: mode toggle, primary start, secondary warmup.
    private var homeMainTrainingSection: some View {
        VStack(spacing: 20) {
            Picker("", selection: $homeTrainingModeSegment) {
                Text("Solo").tag(HomeTrainingModeSegment.solo)
                Text("Partner").tag(HomeTrainingModeSegment.partner)
            }
            .pickerStyle(.segmented)
            .onChange(of: homeTrainingModeSegment) { _, new in
                let mode: TrainingMode = (new == .solo) ? .solo : .partner
                PBASessionFlowPolicy.persistTrainingMode(mode)
                #if DEBUG
                print("[Home] Training mode (persisted):", mode)
                #endif
            }

            if showsHomeStartSession {
                Button {
                    performStartSession()
                } label: {
                    Text(homeStartSessionTitle)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(Color.yellow)
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(homeTrainingModeSegment == .partner ? "Start partner session" : "Start solo session")
                .scaleEffect(homeStartSessionScale)
                .animation(.easeOut(duration: 0.1), value: isStartSessionPressed)
                .animation(.easeOut(duration: 0.25), value: highlightPrimaryAction)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isStartSessionPressed = true }
                        .onEnded { _ in isStartSessionPressed = false }
                )
            }

            Button {
                router.push(.warmupHub)
            } label: {
                Text("Quick Warmup")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick warmup")
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private func performStartSession() {
        switch homeTrainingModeSegment {
        case .partner:
            startPartnerSession()
        case .solo:
            startSoloSession()
        }
    }

    private var homeTopSection: some View {
        homePlayerBar
    }

    private func startSoloSession() {
        guard canStartLocalTrainingFromHome else { return }
        guard !isNavigatingToTraining else { return }
        isNavigatingToTraining = true
        PBASessionFlowPolicy.persistTrainingMode(.solo)
        router.push(.soloActivitySelection)
        isNavigatingToTraining = false
    }

    private var quickPerformanceSnapshotSection: some View {
        let activityTitle = RecommendationEngine.activityTitle(snapshotTrendActivity)
        return VStack(alignment: .leading, spacing: 10) {
            Text(snapshotTrendTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            HStack(spacing: 10) {
                Text("\(snapshotTrendPrimaryMetricName):")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                Text(snapshotTrendPrimaryLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            if let insight = homeGraphInsight {
                Text("Your Trend: \(insight.trendLabel)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(insight.interpretation)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if snapshotTrendPoints.count >= 2 {
                ProgressLineChartView(
                    title: "",
                    points: snapshotTrendPoints,
                    valueLabel: snapshotTrendValueLabel,
                    yAxisRange: snapshotTrendYAxisRange,
                    referenceLineY: graphTargetReferenceY,
                    emptyStateMessage: nil
                )
                .padding(.horizontal, -16)
                if let hint = homeGraphMicroExplanationPrimaryLine {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if let targetLabel = graphTargetLabelText {
                    Text(targetLabel)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Text("Showing last \(snapshotTrendPoints.count) \(snapshotTrendPoints.count == 1 ? "session" : "sessions") for \(activityTitle).")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
                if homeGraphInsight == nil {
                    Text(snapshotTrendInsightLine)
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.9))
                }
            } else {
                Text("Complete at least 2 \(activityTitle) sessions to see trends.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            logGraphTargetLabelDebug()
            logGraphClarityDebug()
        }
        .onChange(of: snapshotTrendActivity) { _, _ in
            logGraphTargetLabelDebug()
            logGraphClarityDebug()
        }
        .onChange(of: homeGraphInsight) { _, new in
            if let g = new {
                print("[GraphInsight-Debug] recentAvg=\(g.recentAvg) previousAvg=\(g.previousAvg) trend=\(g.trendLabel)")
            }
        }
    }

    private var coachInsightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach Insight")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text(coachInsightBody)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stageProgressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Path")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            if needsBaselineAssessment {
                Text("Path not set")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                Text("Complete \(ActivityKind.twoMinuteTest.displayName) to begin.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text(nextTrainingStageLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.yellow)
                HStack(spacing: 14) {
                    pathStatusItem(label: "AFP", isActive: currentStageIndex == 1, isCompleted: currentStageIndex > 1)
                    pathStatusItem(label: "DOP", isActive: currentStageIndex == 2, isCompleted: currentStageIndex > 2)
                    pathStatusItem(label: "OTP", isActive: currentStageIndex == 3, isCompleted: false)
                }
                Text(currentStageIndex == 3 ? "Mastery path: Stage 3 → Loop next" : "Mastery path: Stage \(currentStageIndex) → Stage \(currentStageIndex + 1)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathStatusItem(label: String, isActive: Bool, isCompleted: Bool) -> some View {
        let stateText = isCompleted ? "Completed" : (isActive ? "Current" : "Upcoming")
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(isCompleted ? "✔" : (isActive ? "●" : "○"))
                    .font(.caption.weight(.bold))
                    .foregroundColor(isActive ? .yellow : (isCompleted ? .green : .white.opacity(0.6)))
                Text(label)
                    .font(.caption.weight(isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .yellow : .white.opacity(0.82))
            }
            Text(stateText)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
        }
    }

    private var secondaryActionsSection: some View { homeSecondaryActionsForCurrentMode }

    /// Partner: full shortcuts including progress and benchmarks. Solo: navigation only (no score surfaces).
    private var homeSecondaryActionsForCurrentMode: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            otherActivityRow(title: "View Path", subtitle: "See curriculum stages") {
                router.push(.curriculum)
            }
            if homeTrainingModeSegment == .partner {
                otherActivityRow(title: "View Progress", subtitle: "Check trends and report card") {
                    router.push(.progress)
                }
                otherActivityRow(title: "Achievements", subtitle: "See earned and locked badges") {
                    router.push(.achievements)
                }
                if canStartLocalTrainingFromHome {
                    otherActivityRow(title: "Train \(ActivityKind.twoMinuteTest.displayName)", subtitle: "Train again and track your progress") {
                        router.pushRespectingCoachRemotePadGate(PBASessionFlowPolicy.routeForActivityLaunch(.twoMinuteTest), coachRemotePrompt: coachRemoteRequiredPrompt)
                    }
                }
            }
            if !isPadPlayerPresentationMode {
                otherActivityRow(title: "Coach Remote", subtitle: "Open partner training remote") {
                    router.push(.coachRemote)
                }
            }
            otherActivityRow(title: "Scan Warmups", subtitle: "Open warmup activities") {
                router.push(.warmupHub)
            }
#if DEBUG
            otherActivityRow(title: "Reset curriculum for selected player", subtitle: "Debug: clear guided stage/loop/recommendation") {
                resetCurriculumForSelectedPlayer()
            }
#endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Largest element on screen: Recommended Training title + one primary CTA button.
    private var recommendedTrainingHeroCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recommended Training")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Button {
                guard !isNavigatingToTraining else { return }
                isNavigatingToTraining = true
                isStartTrainingPressed = true
                let route = routeForTrainNowActivity(pinnedActivity)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    isStartTrainingPressed = false
                    router.pushRespectingCoachRemotePadGate(route, coachRemotePrompt: coachRemoteRequiredPrompt)
                    isNavigatingToTraining = false
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.semibold))
                    Text(recommendedActivityButtonTitle)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.yellow)
                .cornerRadius(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isStartTrainingPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isStartTrainingPressed)
            .disabled(isNavigatingToTraining)
            .accessibilityLabel(recommendedActivityButtonTitle)
            .accessibilityHint("Double tap to start recommended training.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Navigation card to progress/trends. Does not repeat Decision Speed Score (shown in top card).
    private var homeProgressAndScoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Player Progress")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
            Text("See your trends and improvements.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Button {
                router.push(.progress)
            } label: {
                Text("View Progress")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Other activities in a smaller list. These are secondary to the guided Next Training action.
    private var otherActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other Activities (Secondary)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            VStack(spacing: 8) {
                otherActivityRow(title: "View Path", subtitle: "See full progression and current stage") {
                    router.push(.curriculum)
                }
                otherActivityRow(title: "Coach Remote", subtitle: "Open remote controls for partner training") {
                    router.push(.coachRemote)
                }
                otherActivityRow(title: ActivityKind.twoMinuteTest.displayName, subtitle: "Train first-touch decisions under pressure") {
                    router.pushRespectingCoachRemotePadGate(PBASessionFlowPolicy.routeForActivityLaunch(.twoMinuteTest), coachRemotePrompt: coachRemoteRequiredPrompt)
                }
                otherActivityRow(title: "Personal Bests", subtitle: "Fastest decision speed, AFP first-decision accuracy, forward intent") {
                    router.push(.progress)
                }
                Button {
                    router.push(.warmupHub)
                } label: {
                    HStack {
                        Text("Scan Warmups")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func otherActivityRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var curriculumPreviewCard: some View {
        Button {
            #if DEBUG
            print("[Home] Perception Training Path card tapped → pushing AppRoute.curriculum")
            #endif
            router.push(.curriculum)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Perception Training Path")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                pathRow("Playing Away From Pressure", sublabel: pathSublabel(.awayFromPressure), activity: .awayFromPressure, isRecommended: continueTrainingCardActivity == .awayFromPressure)
                pathRow("Dribble or Pass", sublabel: pathSublabel(.dribbleOrPass), activity: .dribbleOrPass, isRecommended: continueTrainingCardActivity == .dribbleOrPass)
                pathRow("One-Touch Passing", sublabel: pathSublabel(.oneTouchPassing), activity: .oneTouchPassing, isRecommended: continueTrainingCardActivity == .oneTouchPassing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func pathSublabel(_ activity: ActivityKind) -> String {
        guard progressStore.isUnlocked(activity: activity, playerId: playerId) else { return "Locked" }
        if progressStore.isReady(activity: activity, playerId: playerId) { return "Ready to Advance" }
        let n = progressStore.lastN(activity, n: 3, playerId: playerId).count
        if n >= 2 { return "Almost There" }
        return "Keep Training"
    }

    private var scanWarmupsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Normal Scanning Activities")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Build scanning habits. Tap any tile to open that activity.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                warmupTile("Color Scan", mode: .colors)
                warmupTile("Number Scan", mode: .numbers)
                warmupTile("Arrow Scan", mode: .colorsArrows)
                warmupTile("Lane Scan", mode: .lanes)
                warmupTile("Colors + Numbers", mode: .colorsNumbers)
            }
        }
    }

    private func warmupTile(_ title: String, mode: DisplayMode) -> some View {
        Button {
            router.push(.warmup(mode))
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var twoMinuteTestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ActivityKind.twoMinuteTest.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Train first-touch decisions under pressure.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
            Button {
                router.pushRespectingCoachRemotePadGate(PBASessionFlowPolicy.routeForActivityLaunch(.twoMinuteTest), coachRemotePrompt: coachRemoteRequiredPrompt)
            } label: {
                Text("Start Training")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var coachRemoteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach Remote")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Use this device to run reps: next rep, PASS, log direction. Choose the activity the player is on.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
            Button {
                router.push(.coachRemote)
            } label: {
                Text("Open Coach Remote")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.yellow)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    /// Recommended Next Activity from skill progression (mastery: accuracy, reaction time, decision speed score). Shown only after 2-Minute Test.
    @ViewBuilder
    private var recommendedNextActivityCard: some View {
        if let rec = skillProgressionRecommendation {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended Next Activity")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(rec.message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Primary stat at top of Home: Decision Speed (average), Best, and Elite Academy benchmark.
    private var decisionSpeedPrimaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Decision Speed")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text(snapshotDecisionSpeedSeconds.map { String(format: "%.2fs", $0) } ?? "—")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Best:")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.85))
                    Text(bestDecisionSpeedSeconds.map { String(format: "%.2fs", $0) } ?? "—")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white)
                }
                HStack(spacing: 4) {
                    Text("Elite Avg:")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.85))
                    Text(String(format: "%.2fs", Self.eliteAcademyAverageDecisionSpeed))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white.opacity(0.95))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("See your trends and improvements.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
            Button {
                router.push(.progress)
            } label: {
                Text("View Progress")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    /// Home screen: no checkmarks; only highlight the recommended next activity (●). Others show ○.
    private func pathRow(_ title: String, sublabel: String, activity: ActivityKind, isRecommended: Bool) -> some View {
        let unlocked = progressStore.isUnlocked(activity: activity, playerId: playerId)
        let icon: String
        let iconColor: Color
        if !unlocked {
            icon = "lock.fill"
            iconColor = .white.opacity(0.4)
        } else if isRecommended {
            icon = "circle.fill"
            iconColor = .yellow
        } else {
            icon = "circle"
            iconColor = .white.opacity(0.5)
        }
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(unlocked ? 0.9 : 0.5))
                Text(sublabel)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func introDestination(for activity: ActivityKind) -> some View {
        switch activity {
        case .twoMinuteTest:
            TwoMinuteRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .awayFromPressure:
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .dribbleOrPass:
            DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .oneTouchPassing:
            OneTouchPassingRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }

    private func statusUpgradeToast(status: PlayerStatus) -> some View {
        VStack(spacing: 8) {
            Text("Status Upgraded")
                .font(.headline)
                .foregroundColor(.white)
            Text("You're becoming a \(status.rawValue).")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Text("You're deciding earlier and using the whole field.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(24)
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .padding(.horizontal, 32)
        .onTapGesture { showStatusUpgrade = false }
    }

    private func checkStatusUpgrade() {
        let previous = PlayerStatus.loadLastStatus(playerId: playerId)
        let order: [PlayerStatus] = [.beginner, .developing, .playmaker, .elite]
        guard let prevIdx = previous.flatMap({ order.firstIndex(of: $0) }),
              let currIdx = order.firstIndex(of: status),
              currIdx > prevIdx else {
            if hasAnyBlock { status.saveAsLastStatus(playerId: playerId) }
            return
        }
        upgradedStatus = status
        showStatusUpgrade = true
        status.saveAsLastStatus(playerId: playerId)
    }
}

// MARK: - 2-Minute Test flow

enum TwoMinuteTestHelperSelection: Hashable {
    case partner
    case wall
}

struct TwoMinuteRoleSelectionView: View {
    private static let globalLastRoleKey = "pba.lastSelectedDeviceRole"
    private enum SavedTwoMinuteRole: String {
        case display
        case coachRemote
    }

    private static let lastRoleKey = "twoMinuteTest.lastSelectedDeviceRole"

    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var partnerTrainingCoordinator = TrainingPartnerConnectionCoordinator.shared
    @AppStorage("userMode") private var userMode: String = "coach"
    @State private var showTrainingModeSelection = false
    @State private var savedRole: SavedTwoMinuteRole?
    @State private var showFullRoleSelection = false

    private var continueTitle: String {
        "Continue"
    }

    private var roleContextIconName: String {
        switch savedRole {
        case .display: return "rectangle.on.rectangle"
        case .coachRemote: return "hand.tap"
        case .none: return "info.circle"
        }
    }

    private var roleContextText: String {
        switch savedRole {
        case .display: return "This device will be the display"
        case .coachRemote: return "This device will control the session"
        case .none: return ""
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            Text(ActivityKind.twoMinuteTest.displayName)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text("Ready to train?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal)

            if let savedRole, !showFullRoleSelection {
                Text("Start immediately with your last role.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button {
                    continueWithSavedRole(savedRole)
                } label: {
                    Text(continueTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(Color.yellow)
                        .cornerRadius(18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 28)
                HStack(spacing: 6) {
                    Image(systemName: roleContextIconName)
                        .font(.caption.weight(.semibold))
                    Text(roleContextText)
                        .font(.subheadline)
                }
                .foregroundColor(.white.opacity(0.74))

                Button {
                    showFullRoleSelection = true
                } label: {
                    Text("Switch device role")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.86))
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text("Choose one. The other device should choose the other role.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                VStack(spacing: 16) {
                    Button {
                        saveLastRole(.display)
                        userMode = "solo"
                        showTrainingModeSelection = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "tv")
                                Text("Display")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                            }
                            Text("This device shows the ball cues. Place it behind the player.")
                                .font(.footnote)
                                .foregroundColor(.black.opacity(0.8))
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(Color.yellow)
                        .cornerRadius(18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 28)

                    Button {
                        saveLastRole(.coachRemote)
                        userMode = "coach"
                        router.push(.coachRemote)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "hand.raised")
                                Text("Coach remote")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                            }
                            Text("Choose which activity the player is on, then tap it. Tap Connect to Display first.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 28)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: Self.globalLastRoleKey) {
                savedRole = SavedTwoMinuteRole(rawValue: raw)
            } else if let raw = UserDefaults.standard.string(forKey: Self.lastRoleKey) {
                savedRole = SavedTwoMinuteRole(rawValue: raw)
            } else {
                savedRole = nil
            }
            showFullRoleSelection = false
        }
        .navigationDestination(isPresented: $showTrainingModeSelection) {
            TwoMinuteCriticalScanSessionView(config: TwoMinuteTestConfig.baseline, mode: PBASessionFlowPolicy.lastSelectedTrainingMode(), settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
                .id(partnerTrainingCoordinator.partnerDisplaySurfaceId)
        }
    }

    private func continueWithSavedRole(_ role: SavedTwoMinuteRole) {
        switch role {
        case .display:
            saveLastRole(.display)
            userMode = "solo"
            showTrainingModeSelection = true
        case .coachRemote:
            saveLastRole(.coachRemote)
            userMode = "coach"
            router.push(.coachRemote)
        }
    }

    private func saveLastRole(_ role: SavedTwoMinuteRole) {
        UserDefaults.standard.set(role.rawValue, forKey: Self.globalLastRoleKey)
        UserDefaults.standard.set(role.rawValue, forKey: Self.lastRoleKey)
        savedRole = role
    }
}

struct TwoMinuteTestSetupView: View {
    let mode: TrainingMode
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @State private var navigateToGetReady = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            Text("Set up")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("• Put the iPad behind the player.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Text("• Player stays inside of a 5×5 square.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                if mode == .partner {
                    Text("• Coach stands about 12 yards in front with the ball.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 8)

            Button {
                popToRootTrigger.request = false
                navigateToGetReady = true
            } label: {
                Text("Continue")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 20)
                    .background(Color.yellow)
                    .cornerRadius(18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .pbaHomeToolbar(router: router)
        .navigationDestination(isPresented: $navigateToGetReady) {
            TwoMinuteGetReadyView(mode: mode, config: TwoMinuteTestConfig.baseline, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
    }
}

/// Two-Minute: Setup → this view shows Instructions or Session (no separate Get Ready screen).
struct TwoMinuteGetReadyView: View {
    let mode: TrainingMode
    let config: TwoMinuteTestConfig
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var partnerTrainingCoordinator = TrainingPartnerConnectionCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showLeaveAlert = false

    @State private var phase: Bool = true

    var body: some View {
        Group {
            if phase {
                TwoMinuteCriticalScanSessionView(config: config, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                    .environmentObject(progressStore)
                    .environmentObject(playerStore)
                    .environmentObject(popToRootTrigger)
                    .environmentObject(router)
                    .id(mode.requiresPhoneDisplayRelay ? partnerTrainingCoordinator.partnerDisplaySurfaceId.uuidString : "twoMinute-get-ready-solo")
            } else {
                EmptyView()
            }
        }
        .alert("Leave training?", isPresented: $showLeaveAlert) {
            Button("Stay", role: .cancel) {}
            Button("Leave", role: .destructive) {
                router.popToRoot(endingPartnerSession: false)
            }
        } message: {
            Text("Your current block will not be saved.")
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .pbaHomeToolbar(router: router)
    }
}

/// Simple explanation sheet for "How it works" link.
private struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("It's about when you decide, not how you touch. Know your first decision before the ball reaches you.")
                        .foregroundColor(.primary)

                    Text("Use the drills to practice pocket moments and deciding early.")
                        .foregroundColor(.primary)
                }
                .padding(24)
            }
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 30)
            
            Text(text)
                .foregroundColor(.white)
        }
    }
}

struct PlayerExample: View {
    let name: String
    let description: String
    let videoURL: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
            
            Link(destination: URL(string: videoURL)!) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Watch Example")
                }
                .foregroundColor(.blue)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Scanning Activities Section (extracted to reduce MainView body type complexity and fix runtime type-resolution crash)
private struct ScanningActivitiesSectionView: View {
    @Binding var displayMode: DisplayMode
    @Binding var selectedNumbers: Set<Int>
    @Binding var selectedLanes: Set<String>
    @Binding var selectedColors: [Color]
    @Binding var selectedBeepInterval: BeepInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scanning Activities")
                .font(.headline)
                .foregroundColor(.white)
                .environment(\.sizeCategory, .large)

            // Normal Scan Activities
            VStack(alignment: .leading, spacing: 8) {
                Text("Normal Scan Activities")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 4)
                    .environment(\.sizeCategory, .large)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    modeButton(title: "Colors", mode: .colors, color: .blue)
                    modeButton(title: "Numbers", mode: .numbers, color: .blue)
                    modeButton(title: "Lanes", mode: .lanes, color: .blue)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    modeButton(title: "Colors + Arrows", mode: .colorsArrows, color: .blue)
                    modeButton(title: "Colors + Numbers", mode: .colorsNumbers, color: .blue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                modeButton(title: "Playing Away from Pressure", mode: .pressureResponse, color: .orange)
                modeButton(title: "One-Touch Passing", mode: .oneTouchPassing, color: .purple)
                modeButton(title: "4-Goal Game", mode: .fourGoalGame, color: .yellow)
                modeButton(title: "Dribble or Pass", mode: .scanningGame, color: .green)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .opacity(0.7)
        }
        .padding(.horizontal)
        .environment(\.sizeCategory, .large)
    }

    private func modeButton(title: String, mode: DisplayMode, color: Color) -> some View {
        Button(action: {
            displayMode = mode
            selectedNumbers.removeAll()
            selectedLanes.removeAll()
            if mode == .lanes { selectedColors.removeAll() }
            selectedBeepInterval = .medium
        }) {
            Text(title)
                .font(.system(size: title.count > 15 ? 11 : 13, weight: .semibold))
                .foregroundColor(displayMode == mode ? .white : .white.opacity(0.7))
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == mode, color: color))
    }
}

private struct WarmupHubView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scan Warmups")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Choose a warmup. Each one opens its own setup screen with customization options.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                VStack(spacing: 10) {
                    warmupRow("Color Scan", mode: .colors)
                    warmupRow("Number Scan", mode: .numbers)
                    warmupRow("Arrow Scan", mode: .colorsArrows)
                    warmupRow("Lane Scan", mode: .lanes)
                    warmupRow("Colors + Numbers", mode: .colorsNumbers)
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Warmups")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func warmupRow(_ title: String, mode: DisplayMode) -> some View {
        Button {
            router.push(.warmup(mode))
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MainView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    let showModeSelection: Bool
    @AppStorage("dashboardAudienceRoleV1") private var dashboardAudienceRoleRaw: String = ""
    @AppStorage("whatsNewControlsSeenV1") private var whatsNewControlsSeen = false
    @State private var showWhatsNewControls = false
    
    @State private var selectedColors: [Color] = []
    @State private var selectedNumbers: Set<Int> = []
    @State private var selectedLanes: Set<String> = []
    @State private var displayMode: DisplayMode = .colors
    @State private var changeInterval: Double = 1.5
    @State private var laneSpeed: Double = 4.0
    @State private var showDisplay: Bool = false
    @State private var showActivities: Bool = false
    @State private var isScanning: Bool = false
    @State private var currentIndex: Int = 0
    @State private var currentColor: Color
    @State private var currentNumber: Int = 1
    @State private var currentNumberColor: Color = .blue
    @State private var currentLane: String = "Left"
    @State private var laneColors: [String: Color] = [:]
    @State private var animationDirection: Bool = true // true = top to bottom, false = bottom to top
    @State private var animationOffset: CGFloat = 0
    @State private var timer: Timer?
    // Sound and critical scan settings now managed by ViewModel
    @State private var isActive: Bool = true
    @State private var audioPlayer: AVAudioPlayer?
    @State private var criticalScanAudioPlayer: AVAudioPlayer?
    
    // New state variables for colorsNumbers and colorsArrows modes
    @State private var currentArrowDirection: String = "arrow.up"
    @State private var showNumberOrArrow: Bool = false
    @State private var beepTimer: Timer?
    @State private var numberRange: Double = 2.0 // Legacy variable - now uses selectedNumbers instead
    @State private var selectedArrows: Set<String> = [] // Selected arrows for Colors + Arrows mode
    @State private var selectedBeepInterval: BeepInterval = .medium // Default to medium
    @State private var beepMode: BeepMode = .range // Default to range mode
    @State private var fixedBeepInterval: Double = 3.0 // Default fixed interval in seconds
    // Critical scan settings now managed by ViewModel
    @State private var selectedColorSet: ScanningColorSet = .standard // Default to standard colors
    @State private var selectedActionSet: ActionSet = .basic // Default to basic actions
    @State private var fourGoalLeftColor: Color = .blue
    @State private var fourGoalRightColor: Color = .white
    
    // Helper function to get color names for the picker
    private func colorName(for color: Color) -> String {
        if color == Color(red: 0.8, green: 0.0, blue: 0.0) { return "Red" }
        if color == .blue { return "Blue" }
        if color == .green { return "Green" }
        if color == Color(red: 1.0, green: 0.8, blue: 0.0) { return "Yellow" }
        if color == Color(red: 0.9, green: 0.5, blue: 0.0) { return "Orange" }
        if color == .white { return "White" }
        if color == .black { return "Black" }
        if color == Color(red: 1.0, green: 0.4, blue: 0.8) { return "Pink" }
        return "Unknown"
    }
    
    // Custom actions now managed by SettingsViewModel
    @State private var showingCustomActionSheet = false
    @State private var editingActionNumber: Int = 1
    @State private var showingActionList = false
    @State private var selectedActionForNumber: Int = 1
    
    // Screen protection toggle for outdoor/indoor training
    @State private var screenProtectionEnabled: Bool = true // Default to enabled for safety
    
    // Number and Arrow Color Selection
    @State private var numberColor: Color = .white // Default to white
    @State private var arrowColor: Color = .white // Default to white
    
    // Session tracking
    @State private var sessionStartTime: Date?
    @State private var sessionDuration: TimeInterval = 0
    
    // Arrow directions for colorsArrows mode
    private let arrowDirections = [
        "arrow.up",
        "arrow.down", 
        "arrow.left",
        "arrow.right",
        "arrow.up.left",
        "arrow.up.right",
        "arrow.down.left",
        "arrow.down.right"
    ]
    
    // Scanning circles for normal scan phase
    @State private var currentScanningCircleColor: Color = .white
    @State private var scanningCircleTimer: Timer?
    @State private var scanningColorIndex: Int = 0
    
    @State private var countdown: Int = 3
    @State private var isCountingDown: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    // Screen protection timer for outdoor use
    @State private var screenProtectionTimer: Timer?
    
    // Scanning Game state variables
    @State private var selectedUserTeamColor: TeamColor = .blue
    @State private var selectedOpponentColor: TeamColor = .red
    @State private var selectedPlayerGender: PlayerGender = .male
    
    // Team composition settings for scanning game
    @State private var numberOfOpponents: Int = 2
    @State private var numberOfTeammates: Int = 1
    @State private var numberOfOpenSpaces: Int = 1

    let availableLanes = ["Left", "Center", "Right"]
    
    init(settingsViewModel: SettingsViewModel, profileManager: UserProfileManager, selectedColors: [Color] = [], displayMode: DisplayMode = .colors, changeInterval: Double = 1.5, selectedNumbers: Set<Int> = [], showModeSelection: Bool = true) {
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        _currentColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
        _currentNumberColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
        self.showModeSelection = showModeSelection
        self.selectedColors = selectedColors
        self.displayMode = displayMode
        self.changeInterval = changeInterval
        self.selectedNumbers = selectedNumbers
    }
    
    var body: some View {
        if showDisplay {
            // Display View - Full Screen
            DisplayView(
                selectedColors: selectedColors,
                displayMode: displayMode,
                changeInterval: changeInterval,
                selectedNumbers: Array(selectedNumbers).sorted(),
                soundEnabled: settingsViewModel.soundEnabled,
                laneSpeed: laneSpeed,
                numberRange: numberRange,
                selectedArrows: Array(selectedArrows),
                selectedBeepInterval: selectedBeepInterval,
                beepMode: beepMode,
                fixedBeepInterval: fixedBeepInterval,
                criticalScanDelay: settingsViewModel.criticalScanDelay,
                criticalScanDuration: settingsViewModel.criticalScanDuration,
                criticalScanResetTime: settingsViewModel.criticalScanResetTime,
                teammateMovementDuration: settingsViewModel.teammateMovementDuration,
                opponentMovementDuration: settingsViewModel.opponentMovementDuration,
                trainingPerspective: settingsViewModel.trainingPerspective,
                selectedColorSet: selectedColorSet,
                selectedActionSet: selectedActionSet,
                customActions: settingsViewModel.customActions,
                screenProtectionEnabled: settingsViewModel.screenProtectionEnabled,
                numberColor: numberColor,
                arrowColor: arrowColor,
                userTeamColor: selectedUserTeamColor,
                opponentColor: selectedOpponentColor,
                playerGender: selectedPlayerGender,
                numberOfOpponents: numberOfOpponents,
                numberOfTeammates: numberOfTeammates,
                numberOfOpenSpaces: numberOfOpenSpaces,
                fourGoalLeftColor: fourGoalLeftColor,
                fourGoalRightColor: fourGoalRightColor,
                showDisplay: $showDisplay,
                profileManager: profileManager
            )
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { showDisplay = false }
            .navigationBarHidden(true)
        } else {
            // Configuration View
        ZStack {
                    // Background
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.05, green: 0.05, blue: 0.1),
                            Color(red: 0.1, green: 0.1, blue: 0.15)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    // Content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 15) {
                        // Training Environment Section (moved to top)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Training Environment")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Toggle("", isOn: $settingsViewModel.screenProtectionEnabled)
                                        .toggleStyle(SwitchToggleStyle(tint: .green))
                                    Spacer()
                                }
                                .padding(.bottom, 4)
                                
                                Text(settingsViewModel.screenProtectionEnabled ? "Outdoor Training" : "Indoor Training")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text(settingsViewModel.screenProtectionEnabled ? "Maximum brightness (100%) & prevents sleep - Use for bright sunlight or hot conditions" : "Standard brightness & prevents sleep - Recommended for indoor training")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text(settingsViewModel.screenProtectionEnabled ? "Recommended: Use when training outdoors in bright sunlight, hot weather, or when you need maximum visibility" : "Recommended: Use for indoor training, overcast days, or when you want to save battery")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.ultraThinMaterial)
                                .opacity(0.7)
                        }
                        .padding(.horizontal)
                        
                        // Sound Toggle
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Sound")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Toggle("", isOn: $settingsViewModel.soundEnabled)
                                    .labelsHidden()
                            }
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.ultraThinMaterial)
                                .opacity(0.7)
                        }
                        .padding(.horizontal)

                        // Coach-style training reminders (local notifications; throttled in scheduler).
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Training nudges")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $settingsViewModel.coachingNudgesEnabled)
                                    .labelsHidden()
                            }
                            Text("Short, soccer-focused prompts — at most one reminder window scheduled per day.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.ultraThinMaterial)
                                .opacity(0.7)
                        }
                        .padding(.horizontal)
                        .onChange(of: settingsViewModel.coachingNudgesEnabled) { _, new in
                            if new {
                                CoachingTrainingNotificationScheduler.requestAuthorizationIfNeeded { granted in
                                    DispatchQueue.main.async {
                                        if !granted {
                                            settingsViewModel.coachingNudgesEnabled = false
                                        }
                                        NotificationCenter.default.post(name: .coachingTrainingNudgesShouldRefresh, object: nil)
                                    }
                                }
                            } else {
                                NotificationCenter.default.post(name: .coachingTrainingNudgesShouldRefresh, object: nil)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Usage Mode")
                                .font(.headline)
                                .foregroundColor(.white)

                            Picker(
                                "Usage Mode",
                                selection: Binding(
                                    get: { dashboardAudienceRoleRaw.isEmpty ? "parent_player" : dashboardAudienceRoleRaw },
                                    set: { dashboardAudienceRoleRaw = $0 }
                                )
                            ) {
                                Text("Train").tag("parent_player")
                                Text("Coach").tag("coach")
                            }
                            .pickerStyle(.segmented)

                            Text("You can change this anytime.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))

                            Button {
                                showWhatsNewControls = true
                            } label: {
                                Text("View What's New")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.ultraThinMaterial)
                                .opacity(0.7)
                        }
                        .padding(.horizontal)

#if DEBUG
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Developer")
                                .font(.headline)
                                .foregroundColor(.white)

                            Button {
                                whatsNewControlsSeen = false
                                showWhatsNewControls = true
                            } label: {
                                Text("Show What's New Screen")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Text("Resets the seen state and opens the screen now.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.ultraThinMaterial)
                                .opacity(0.7)
                        }
                        .padding(.horizontal)
#endif
                        
                        // Mode selection is shown only in the full warmup browser.
                        if showModeSelection {
                            ScanningActivitiesSectionView(
                                displayMode: $displayMode,
                                selectedNumbers: $selectedNumbers,
                                selectedLanes: $selectedLanes,
                                selectedColors: $selectedColors,
                                selectedBeepInterval: $selectedBeepInterval
                            )
                        }
                            
                            // Number Color Selection (for modes that use numbers)
                            if displayMode == .numbers || displayMode == .colorsNumbers {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Number Color")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    HStack(spacing: 15) {
                                        Button(action: {
                                            numberColor = .white
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(.white)
                                                    .frame(width: 20, height: 20)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(numberColor == .white ? .blue : .gray, lineWidth: 3)
                                                    )
                                                Text("White")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: numberColor == .white, color: .blue))
                                        
                                        Button(action: {
                                            numberColor = .black
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(.black)
                                                    .frame(width: 20, height: 20)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(numberColor == .black ? .blue : .gray, lineWidth: 3)
                                                    )
                                                Text("Black")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: numberColor == .black, color: .blue))
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Arrow Color Selection (for modes that use arrows)
                            if displayMode == .colorsArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Arrow Color")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    HStack(spacing: 15) {
                                        Button(action: {
                                            arrowColor = .white
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(.white)
                                                    .frame(width: 20, height: 20)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(arrowColor == .white ? .blue : .gray, lineWidth: 3)
                                                    )
                                                Text("White")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: arrowColor == .white, color: .blue))
                                        
                                        Button(action: {
                                            arrowColor = .black
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(.black)
                                                    .frame(width: 20, height: 20)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(arrowColor == .black ? .blue : .gray, lineWidth: 3)
                                                    )
                                                Text("Black")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: arrowColor == .black, color: .blue))
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            

                            
                            // Beep Interval Selection (for Colors, Colors + Numbers, Colors + Arrows, Numbers, Lanes, Critical Scan modes, Scanning Game, Pressure Response, One-Touch Passing, and 4-Goal Game)
                            if displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .numbers || displayMode == .lanes || displayMode == .scanningGame || displayMode == .pressureResponse || displayMode == .oneTouchPassing || displayMode == .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Beep Interval")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Controls how often beep sounds occur during training to signal actions")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    // Beep Mode Toggle
                                    HStack(spacing: 8) {
                                        ForEach(BeepMode.allCases, id: \.self) { mode in
                                            Button(action: {
                                                beepMode = mode
                                            }) {
                                                Text(mode.rawValue)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(beepMode == mode ? .white : .white.opacity(0.7))
                                                    .padding(.vertical, 12)
                                                    .padding(.horizontal, 8)
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(DisplayModeButtonStyle(isSelected: beepMode == mode, color: .purple))
                                        }
                                    }
                                    
                                    // Range Mode Options
                                    if beepMode == .range {
                                        HStack(spacing: 8) {
                                            ForEach(BeepInterval.allCases, id: \.self) { interval in
                                                Button(action: {
                                                    selectedBeepInterval = interval
                                                }) {
                                                    Text(interval.rawValue)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(selectedBeepInterval == interval ? .white : .white.opacity(0.7))
                                                        .padding(.vertical, 12)
                                                        .padding(.horizontal, 8)
                                                        .frame(maxWidth: .infinity)
                                                }
                                                .buttonStyle(DisplayModeButtonStyle(isSelected: selectedBeepInterval == interval, color: .orange))
                                            }
                                        }
                                    }
                                    
                                    // Fixed Mode Options
                                    if beepMode == .fixed {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Fixed Interval")
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            HStack {
                                                Slider(value: $fixedBeepInterval, in: 0.5...15.0, step: 0.5)
                                                    .accentColor(.orange)
                                                
                                                Text("\(fixedBeepInterval, specifier: "%.1f")s")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .frame(minWidth: 50)
                                            }
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Critical Scan Color Selection (only for 4-Goal Game mode)
                            if displayMode == .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Critical Scan Colors")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Choose two colors for the critical scan phase. The screen will randomly use one of these colors.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Left Color")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Left Color", selection: $fourGoalLeftColor) {
                                                ForEach(availableColors, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color)
                                                            .frame(width: 20, height: 20)
                                                        Text(colorName(for: color))
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Right Color")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Right Color", selection: $fourGoalRightColor) {
                                                ForEach(availableColors, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color)
                                                            .frame(width: 20, height: 20)
                                                        Text(colorName(for: color))
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }

                            // Lane Selection
                            if displayMode == .lanes {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Lanes")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    HStack(spacing: 15) {
                                        ForEach(availableLanes, id: \.self) { lane in
                                            Button(action: {
                                                if selectedLanes.contains(lane) {
                                                    selectedLanes.remove(lane)
                                                } else {
                                                    selectedLanes.insert(lane)
                                                }
                                            }) {
                                                Text(lane)
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding()
                                            }
                                            .buttonStyle(DisplayModeButtonStyle(isSelected: selectedLanes.contains(lane), color: .blue))
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.8)
                                }
                                .padding(.horizontal)
                                
                                // Color Selection for Lanes
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(selectedLanes.isEmpty ? "Select Colors" : "Select Colors (\(selectedLanes.count) colors max)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    ScrollView {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                                            ForEach(availableColors, id: \.self) { color in
                                                Circle()
                                                    .fill(color)
                                                    .frame(width: 60, height: 60)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.gray, lineWidth: selectedColors.contains(color) ? 3 : 0)
                                                    )
                                                    .opacity(selectedColors.contains(color) ? 1.0 : 0.5)
                                                    .clipShape(Circle())
                                                    .onTapGesture {
                                                        if selectedColors.contains(color) {
                                                            selectedColors.removeAll { $0 == color }
                                                        } else {
                                                            selectedColors.append(color)
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                    .frame(height: 150)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Color Selection
                            if displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Colors")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    ScrollView {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                                            ForEach(availableColors, id: \.self) { color in
                                                Circle()
                                                    .fill(color)
                                                    .frame(width: 60, height: 60)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.gray, lineWidth: selectedColors.contains(color) ? 3 : 0)
                                                    )
                                                    .opacity(selectedColors.contains(color) ? 1.0 : 0.5)
                                                    .clipShape(Circle())
                                                    .onTapGesture {
                                                        if selectedColors.contains(color) {
                                                            selectedColors.removeAll { $0 == color }
                                                        } else {
                                                            selectedColors.append(color)
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                    .frame(height: 150)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Number Selection
                            if displayMode == .numbers {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Numbers")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 12), count: 4), spacing: 12) {
                                        ForEach(1...9, id: \.self) { number in
                                            Button(action: {
                                                if selectedNumbers.contains(number) {
                                                    selectedNumbers.remove(number)
                                                } else {
                                                    selectedNumbers.insert(number)
                                                }
                                            }) {
                                                Text("\(number)")
                                                    .font(.system(size: 24, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 70, height: 70)
                                            }
                                            .buttonStyle(CircleButtonStyle(isSelected: selectedNumbers.contains(number), color: .blue))
                                        }
                                    }
                                }
                                .padding(.vertical, 15)
                                .padding(.horizontal, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.8)
                                }
                                .padding(.horizontal)
                                
                                // Color Selection for Numbers
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Colors")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    ScrollView {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                                            ForEach(availableColors, id: \.self) { color in
                                                Circle()
                                                    .fill(color)
                                                    .frame(width: 60, height: 60)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.gray, lineWidth: selectedColors.contains(color) ? 3 : 0)
                                                    )
                                                    .opacity(selectedColors.contains(color) ? 1.0 : 0.5)
                                                    .clipShape(Circle())
                                                    .onTapGesture {
                                                        if selectedColors.contains(color) {
                                                            selectedColors.removeAll { $0 == color }
                                                        } else {
                                                            selectedColors.append(color)
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                    .frame(height: 150)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Number Selection (only for Colors + Numbers mode)
                            if displayMode == .colorsNumbers {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Numbers (1-10)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Choose which numbers can appear during training")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                                        ForEach(1...10, id: \.self) { number in
                                            Button(action: {
                                                if selectedNumbers.contains(number) {
                                                    selectedNumbers.remove(number)
                                                } else {
                                                    selectedNumbers.insert(number)
                                                }
                                            }) {
                                                Text("\(number)")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 40, height: 40)
                                            }
                                            .buttonStyle(SquareButtonStyle(isSelected: selectedNumbers.contains(number), color: .green))
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Arrow Selection (only for Colors + Arrows mode)
                            if displayMode == .colorsArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Arrow Directions")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                                        ForEach(arrowDirections, id: \.self) { arrow in
                                            Button(action: {
                                                if selectedArrows.contains(arrow) {
                                                    selectedArrows.remove(arrow)
                                                } else {
                                                    selectedArrows.insert(arrow)
                                                }
                                            }) {
                                                Image(systemName: arrow)
                                                    .font(.system(size: 24, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 60, height: 60)
                                            }
                                            .buttonStyle(ArrowButtonStyle(isSelected: selectedArrows.contains(arrow)))
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Lane Speed Slider (only show in lanes mode)
                            if displayMode == .lanes {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Lane Speed: \(String(format: "%.1f", laneSpeed))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Controls how fast the colored lanes move up and down the screen")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Slider(value: $laneSpeed, in: 2.0...10.0, step: 0.5)
                                        .accentColor(.blue)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Time Interval Slider (only show for modes that use it)
                            if displayMode != .scanningGame && displayMode != .pressureResponse && displayMode != .oneTouchPassing && displayMode != .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .lanes ? "Color Changing Time Interval: \(String(format: "%.1f", changeInterval))s" : displayMode == .numbers ? "Color and Number Changing Time Interval: \(String(format: "%.1f", changeInterval))s" : "Time Interval: \(String(format: "%.1f", changeInterval))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text(displayMode == .numbers ? "Controls how often the colors and numbers change on the screen" : "Controls how often colors change on the screen")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Slider(value: $changeInterval, in: 0.5...3.0, step: 0.1)
                                        .accentColor(.blue)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Scanning Circle Time Interval (only for Critical Scan modes, Scanning Game, Pressure Response, One-Touch Passing, and 4-Goal Game)
                            if displayMode == .scanningGame || displayMode == .pressureResponse || displayMode == .oneTouchPassing || displayMode == .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Scanning Circle Time Interval: \(String(format: "%.1f", changeInterval))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Controls how fast the scanning circles change color")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Slider(value: $changeInterval, in: 0.5...3.0, step: 0.1)
                                        .accentColor(.blue)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Critical Scan Delay Slider (only for Critical Scan mode, Scanning Game, Pressure Response, One-Touch Passing, and 4-Goal Game)
                            if displayMode == .scanningGame || displayMode == .pressureResponse || displayMode == .oneTouchPassing || displayMode == .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Critical Scan Delay: \(String(format: "%.1f", settingsViewModel.criticalScanDelay))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Time between the initial beep sound and when the red screen and the action appear on screen")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Slider(value: $settingsViewModel.criticalScanDelay, in: 0.5...3.0, step: 0.1)
                                        .accentColor(.red)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Critical Scan Duration Slider (only for Critical Scan mode, Scanning Game, Pressure Response, One-Touch Passing, and 4-Goal Game)
                            if displayMode == .scanningGame || displayMode == .pressureResponse || displayMode == .oneTouchPassing || displayMode == .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Critical Scan Duration: \(String(format: "%.1f", settingsViewModel.criticalScanDuration))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("How long the yellow screen and the action stay visible on screen during the critical scan")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Slider(value: $settingsViewModel.criticalScanDuration, in: 0.5...2.0, step: 0.1)
                                        .accentColor(.orange)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Teammate Speed Control (only for One-Touch Passing mode)
                            if displayMode == .oneTouchPassing {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Teammate Movement Speed")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Control how fast your teammate moves into position")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Picker("Speed Level", selection: $settingsViewModel.teammateSpeedLevel) {
                                        Text("Slow").tag("slow")
                                        Text("Medium").tag("medium")
                                        Text("Fast").tag("fast")
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .accentColor(.green)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Training Perspective Control (only for One-Touch Passing and Pressure Response modes)
                            if displayMode == .oneTouchPassing || displayMode == .pressureResponse {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Training Perspective")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Choose where the action takes place relative to your position")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Picker("Perspective", selection: $settingsViewModel.trainingPerspective) {
                                        Text("Back").tag("back")
                                        Text("Front").tag("front")
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .accentColor(.blue)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Opponent Speed Control (Pressure Response, 4-Goal Game, Dribble or Pass, One-Touch Passing)
                            if displayMode == .pressureResponse || displayMode == .fourGoalGame || displayMode == .scanningGame || displayMode == .oneTouchPassing {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Opponent Movement Speed")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text(displayMode == .scanningGame ? "Control how fast defenders move to their positions" : displayMode == .oneTouchPassing ? "Control how fast the defender moves to the side" : "Control how fast the opponent moves")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Picker("Opponent Speed", selection: $settingsViewModel.opponentSpeedLevel) {
                                        Text("Slow").tag("slow")
                                        Text("Medium").tag("medium")
                                        Text("Fast").tag("fast")
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .background(Color.blue.opacity(0.3))
                                    .cornerRadius(8)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Critical Scan Reset Time Slider (only for Critical Scan mode, Scanning Game, Pressure Response, and One-Touch Passing)
                            if displayMode == .scanningGame || displayMode == .pressureResponse || displayMode == .oneTouchPassing {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Reset Time: \(String(format: "%.0f", settingsViewModel.criticalScanResetTime))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Time you have to complete the action and return back to the training area before the next scan begins")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Slider(value: $settingsViewModel.criticalScanResetTime, in: 1.0...10.0, step: 1.0)
                                        .accentColor(.purple)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Scanning Circle Colors (only for Critical Scan mode, Scanning Game, Pressure Response, One-Touch Passing, and 4-Goal Game)
                            if displayMode == .scanningGame || displayMode == .pressureResponse || displayMode == .oneTouchPassing || displayMode == .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Scanning Circle Colors")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Picker("Color Set", selection: $selectedColorSet) {
                                        ForEach(ScanningColorSet.allCases, id: \.self) { colorSet in
                                            Text(colorSet.rawValue).tag(colorSet)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .accentColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Team Color Controls (only for Scanning Game and 4-Goal Game modes)
                            if displayMode == .scanningGame || displayMode == .fourGoalGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Team Colors")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Select your team color and opponent (defender) color")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Your Team")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Your Team", selection: $selectedUserTeamColor) {
                                                ForEach(TeamColor.allCases.filter { $0 != selectedOpponentColor }, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color.color)
                                                            .frame(width: 20, height: 20)
                                                        Text(color.rawValue)
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Opponent")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Opponent", selection: $selectedOpponentColor) {
                                                ForEach(TeamColor.allCases.filter { $0 != selectedUserTeamColor }, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color.color)
                                                            .frame(width: 20, height: 20)
                                                        Text(color.rawValue)
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Player Gender")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Choose male or female player silhouettes")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 15) {
                                        Button(action: {
                                            selectedPlayerGender = .male
                                        }) {
                                            HStack {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.white)
                                                Text("Male")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: selectedPlayerGender == .male, color: .blue))
                                        
                                        Button(action: {
                                            selectedPlayerGender = .female
                                        }) {
                                            HStack {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.white)
                                                Text("Female")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: selectedPlayerGender == .female, color: .blue))
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                                
                                // Team Composition (only for Scanning Game, not 4-Goal Game)
                                if displayMode == .scanningGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Team Composition")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Configure the number of players for different skill levels")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    VStack(spacing: 15) {
                                        // Opponents
                                        HStack {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("Opponents")
                                                    .font(.subheadline)
                                                    .foregroundColor(.white.opacity(0.9))
                                                Text("More opponents = harder")
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                            Spacer()
                                            HStack(spacing: 10) {
                                                Button(action: {
                                                    if numberOfOpponents > 1 {
                                                        numberOfOpponents -= 1
                                                    }
                                                }) {
                                                    Image(systemName: "minus.circle.fill")
                                                        .font(.title2)
                                                        .foregroundColor(.red)
                                                }
                                                
                                                Text("\(numberOfOpponents)")
                                                    .font(.title3)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .frame(minWidth: 30)
                                                
                                                Button(action: {
                                                    if numberOfOpponents < 4 {
                                                        numberOfOpponents += 1
                                                    }
                                                }) {
                                                    Image(systemName: "plus.circle.fill")
                                                        .font(.title2)
                                                        .foregroundColor(.green)
                                                }
                                            }
                                        }
                                        
                                        // Teammates
                                        HStack {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("Teammates")
                                                    .font(.subheadline)
                                                    .foregroundColor(.white.opacity(0.9))
                                                Text("More teammates = easier")
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                            Spacer()
                                            HStack(spacing: 10) {
                                                Button(action: {
                                                    if numberOfTeammates > 0 {
                                                        numberOfTeammates -= 1
                                                    }
                                                }) {
                                                    Image(systemName: "minus.circle.fill")
                                                        .font(.title2)
                                                        .foregroundColor(.red)
                                                }
                                                
                                                Text("\(numberOfTeammates)")
                                                    .font(.title3)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .frame(minWidth: 30)
                                                
                                                Button(action: {
                                                    if numberOfTeammates < 3 {
                                                        numberOfTeammates += 1
                                                    }
                                                }) {
                                                    Image(systemName: "plus.circle.fill")
                                                        .font(.title2)
                                                        .foregroundColor(.green)
                                                }
                                            }
                                        }
                                        
                                        // Open Spaces
                                        HStack {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("Open Spaces")
                                                    .font(.subheadline)
                                                    .foregroundColor(.white.opacity(0.9))
                                                Text("Empty positions to scan")
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                            Spacer()
                                            HStack(spacing: 10) {
                                                Button(action: {
                                                    if numberOfOpenSpaces > 0 {
                                                        numberOfOpenSpaces -= 1
                                                    }
                                                }) {
                                                    Image(systemName: "minus.circle.fill")
                                                        .font(.title2)
                                                        .foregroundColor(.red)
                                                }
                                                
                                                Text("\(numberOfOpenSpaces)")
                                                    .font(.title3)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .frame(minWidth: 30)
                                                
                                                Button(action: {
                                                    if numberOfOpenSpaces < 2 {
                                                        numberOfOpenSpaces += 1
                                                    }
                                                }) {
                                                    Image(systemName: "plus.circle.fill")
                                                        .font(.title2)
                                                        .foregroundColor(.green)
                                                }
                                            }
                                        }
                                        
                                        // Total validation
                                        let totalPositions = numberOfOpponents + numberOfTeammates + numberOfOpenSpaces
                                        if totalPositions != 4 {
                                            Text("Total positions must equal 4 (currently \(totalPositions))")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                                }
                            }
                            
                            // Pressure Response Controls (only for Pressure Response mode)
                            if displayMode == .pressureResponse {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Team Colors")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Select your team color and opponent color")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Your Team")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Your Team", selection: $selectedUserTeamColor) {
                                                ForEach(TeamColor.allCases.filter { $0 != selectedOpponentColor }, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color.color)
                                                            .frame(width: 20, height: 20)
                                                        Text(color.rawValue)
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Opponent")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Opponent", selection: $selectedOpponentColor) {
                                                ForEach(TeamColor.allCases.filter { $0 != selectedUserTeamColor }, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color.color)
                                                            .frame(width: 20, height: 20)
                                                        Text(color.rawValue)
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Player Gender")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Choose male or female player silhouettes")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 15) {
                                        Button(action: {
                                            selectedPlayerGender = .male
                                        }) {
                                            HStack {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.white)
                                                Text("Male")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: selectedPlayerGender == .male, color: .blue))
                                        
                                        Button(action: {
                                            selectedPlayerGender = .female
                                        }) {
                                            HStack {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.white)
                                                Text("Female")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: selectedPlayerGender == .female, color: .blue))
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // One-Touch Passing Controls (only for One-Touch Passing mode)
                            if displayMode == .oneTouchPassing {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Team Colors")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Select your team color and opponent color")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Your Team")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Your Team", selection: $selectedUserTeamColor) {
                                                ForEach(TeamColor.allCases.filter { $0 != selectedOpponentColor }, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color.color)
                                                            .frame(width: 20, height: 20)
                                                        Text(color.rawValue)
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Opponent")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            
                                            Picker("Opponent", selection: $selectedOpponentColor) {
                                                ForEach(TeamColor.allCases.filter { $0 != selectedUserTeamColor }, id: \.self) { color in
                                                    HStack {
                                                        Circle()
                                                            .fill(color.color)
                                                            .frame(width: 20, height: 20)
                                                        Text(color.rawValue)
                                                    }
                                                    .tag(color)
                                                }
                                            }
                                            .pickerStyle(MenuPickerStyle())
                                            .accentColor(.white)
                                        }
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Player Gender")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Choose male or female player silhouettes")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    HStack(spacing: 15) {
                                        Button(action: {
                                            selectedPlayerGender = .male
                                        }) {
                                            HStack {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.white)
                                                Text("Male")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: selectedPlayerGender == .male, color: .blue))
                                        
                                        Button(action: {
                                            selectedPlayerGender = .female
                                        }) {
                                            HStack {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.white)
                                                Text("Female")
                                                    .foregroundColor(.white)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: selectedPlayerGender == .female, color: .blue))
                                    }
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.7)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Start Button
                            Button(action: {
                                if isStartEnabled {
                                    showDisplay = true
                                }
                            }) {
                                Text("Start Training to See the Game Better!")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(StartButtonStyle(isEnabled: isStartEnabled))
                            .disabled(!isStartEnabled)
                            .padding(.horizontal)
                            
                            // Helper text when start button is disabled
                            if !isStartEnabled {
                                Text(requiredSelectionsText)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .padding(.bottom, 10)
                            }
                            
                            // Activities Button
                            Button(action: {
                                showActivities = true
                            }) {
                                Text("Training Activities")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(ActivitiesButtonStyle())
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                }
                .navigationTitle(setupTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.clear, for: .navigationBar)
                .foregroundColor(.white)
                .safeAreaInset(edge: .top) {
                    if !showModeSelection {
                        Text(setupSubtitle)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                    }
                }
                .sheet(isPresented: $showActivities) {
                    ActivitiesGuideView(selectedMode: displayMode)
                }
                .sheet(isPresented: $showingCustomActionSheet) {
                    CustomActionSheet(
                        actionNumber: editingActionNumber,
                        currentAction: settingsViewModel.customActions.first { $0.number == editingActionNumber }?.action ?? "",
                        selectedActionSet: selectedActionSet,
                        onSave: { newAction in
                            settingsViewModel.updateCustomAction(
                                number: editingActionNumber,
                                action: newAction,
                                isCustom: true
                            )
                        }
                    )
                }
                .sheet(isPresented: $showingActionList) {
                    ActionListSheet(
                        actionNumber: selectedActionForNumber,
                        currentAction: settingsViewModel.customActions.first { $0.number == selectedActionForNumber }?.action ?? "",
                        basicActions: ActionSet.basic.actions + ActionSet.advanced.actions + ActionSet.defensive.actions,
                        onSelect: { selectedAction in
                            settingsViewModel.updateCustomAction(
                                number: selectedActionForNumber,
                                action: selectedAction,
                                isCustom: !ActionSet.basic.actions.contains(selectedAction)
                            )
                        }
                    )
                }
                .sheet(isPresented: $showWhatsNewControls) {
                    WhatsNewControlsView {
                        whatsNewControlsSeen = true
                        showWhatsNewControls = false
                    }
                }
                
            }
        }
    
    private var isStartEnabled: Bool {
        switch displayMode {
        case .colors:
            // Require at least one color for basic colors activity
            return !selectedColors.isEmpty
        case .colorsNumbers:
            // Require at least one color and one number
            return !selectedColors.isEmpty && !selectedNumbers.isEmpty
        case .colorsArrows:
            // Require at least one color and one arrow
            return !selectedColors.isEmpty && !selectedArrows.isEmpty
        case .numbers:
            // Require at least one number and one color
            return !selectedNumbers.isEmpty && !selectedColors.isEmpty
        case .lanes:
            // Require at least one lane and one color
            return !selectedLanes.isEmpty && !selectedColors.isEmpty
        case .scanningGame:
            // Require different team colors and valid team composition
            let totalPositions = numberOfOpponents + numberOfTeammates + numberOfOpenSpaces
            return selectedUserTeamColor != selectedOpponentColor && totalPositions == 4
        case .pressureResponse:
            // Require different team colors for pressure response
            return selectedUserTeamColor != selectedOpponentColor
        case .oneTouchPassing:
            // Require different team colors for one-touch passing
            return selectedUserTeamColor != selectedOpponentColor
        case .fourGoalGame:
            // 4-Goal Game works with default values
            return true
        }
    }

    private var setupTitle: String {
        switch displayMode {
        case .colors: return "Color Scan Setup"
        case .numbers: return "Number Scan Setup"
        case .colorsArrows: return "Arrow Scan Setup"
        case .lanes: return "Lane Scan Setup"
        case .colorsNumbers: return "Colors + Numbers Setup"
        case .scanningGame: return "Dribble or Pass Setup"
        case .pressureResponse: return "Playing Away From Pressure Setup"
        case .oneTouchPassing: return "One-Touch Passing Setup"
        case .fourGoalGame: return "4-Goal Game Setup"
        }
    }

    private var setupSubtitle: String {
        switch displayMode {
        case .colors: return "Choose colors and timing before you begin."
        case .numbers: return "Choose number set, colors, and timing."
        case .colorsArrows: return "Choose arrows, colors, and timing."
        case .lanes: return "Choose lanes, colors, and movement speed."
        case .colorsNumbers: return "Combine color + number cues with your preferred timing."
        case .scanningGame: return "Set team colors, player mix, and speed."
        case .pressureResponse: return "Set pressure-response colors and speed."
        case .oneTouchPassing: return "Set one-touch passing colors and movement settings."
        case .fourGoalGame: return "Set gate colors and movement settings."
        }
    }
    
    private var requiredSelectionsText: String {
        switch displayMode {
        case .colors:
            if selectedColors.isEmpty {
                return "Please select at least one color to start training"
            }
        case .colorsNumbers:
            if selectedColors.isEmpty && selectedNumbers.isEmpty {
                return "Please select at least one color and one number"
            } else if selectedColors.isEmpty {
                return "Please select at least one color"
            } else if selectedNumbers.isEmpty {
                return "Please select at least one number"
            }
        case .colorsArrows:
            if selectedColors.isEmpty && selectedArrows.isEmpty {
                return "Please select at least one color and one arrow direction"
            } else if selectedColors.isEmpty {
                return "Please select at least one color"
            } else if selectedArrows.isEmpty {
                return "Please select at least one arrow direction"
            }
        case .numbers:
            if selectedNumbers.isEmpty && selectedColors.isEmpty {
                return "Please select at least one number and one color"
            } else if selectedNumbers.isEmpty {
                return "Please select at least one number"
            } else if selectedColors.isEmpty {
                return "Please select at least one color"
            }
        case .lanes:
            if selectedLanes.isEmpty && selectedColors.isEmpty {
                return "Please select at least one lane and one color"
            } else if selectedLanes.isEmpty {
                return "Please select at least one lane"
            } else if selectedColors.isEmpty {
                return "Please select at least one color"
            }
        case .scanningGame:
            if selectedUserTeamColor == selectedOpponentColor {
                return "Please select different colors for your team and opponent"
            }
            let totalPositions = numberOfOpponents + numberOfTeammates + numberOfOpenSpaces
            if totalPositions != 4 {
                return "Team composition must equal exactly 4 positions (currently \(totalPositions))"
            }
        case .pressureResponse:
            if selectedUserTeamColor == selectedOpponentColor {
                return "Please select different colors for your team and opponent"
            }
        case .oneTouchPassing:
            if selectedUserTeamColor == selectedOpponentColor {
                return "Please select different colors for your team and opponent"
            }
        case .fourGoalGame:
            return "" // 4-Goal Game works with defaults
        }
        return ""
    }

    private let availableColors: [Color] = [
        Color(red: 0.8, green: 0.0, blue: 0.0), // Darker red
        .blue,
        .green,
        Color(red: 1.0, green: 0.8, blue: 0.0), // Bright yellow
        Color(red: 0.9, green: 0.5, blue: 0.0), // Darker orange (distinct from red and yellow)
        .white,
        .black,
        Color(red: 1.0, green: 0.4, blue: 0.8)
    ]
}

struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
                    Circle()
                .fill(color)
                .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                )
        }
    }
}

struct NumberButton: View {
    let number: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.blue : Color.gray)
                .cornerRadius(20)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppRouter())
            .environmentObject(MultipeerManager())
    }
}



struct DisplayView: View {
    let selectedColors: [Color]
    let displayMode: DisplayMode
    let changeInterval: Double
    let selectedNumbers: [Int]
    let soundEnabled: Bool
    let laneSpeed: Double
    let numberRange: Double
    let selectedArrows: [String]
    let selectedBeepInterval: BeepInterval
    let beepMode: BeepMode
    let fixedBeepInterval: Double
    let criticalScanDelay: Double
    let criticalScanDuration: Double
    let criticalScanResetTime: Double
    let teammateMovementDuration: Double
    let opponentMovementDuration: Double
    let trainingPerspective: String
    let selectedColorSet: ScanningColorSet
        let selectedActionSet: ActionSet
    let customActions: [CustomAction]
        let screenProtectionEnabled: Bool
        let numberColor: Color
        let arrowColor: Color
    let userTeamColor: TeamColor
    let opponentColor: TeamColor
    let playerGender: PlayerGender
    let numberOfOpponents: Int
    let numberOfTeammates: Int
    let numberOfOpenSpaces: Int
    let fourGoalLeftColor: Color
    let fourGoalRightColor: Color
        @Binding var showDisplay: Bool
        @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject var multipeerManager: MultipeerManager

    @State private var currentColor: Color
    @State private var currentNumber: Int = 1
    @State private var currentNumberColor: Color = .blue
    @State private var currentLane: String = "Left"
    @State private var laneColors: [String: Color] = [:]
    @State private var animationDirection: Bool = true // true = top to bottom, false = bottom to top
    @State private var animationOffset: CGFloat = 0
    @State private var timer: Timer?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var criticalScanAudioPlayer: AVAudioPlayer?
    @State private var isActive: Bool = true
    
    // New state variables for colorsNumbers and colorsArrows modes
    @State private var currentArrowDirection: String = "arrow.up"
    @State private var showNumberOrArrow: Bool = false
    @State private var beepTimer: Timer?
    @State private var isBeepScheduled: Bool = false // Prevent multiple concurrent beep schedules
    @State private var isBeepLockActive: Bool = false
    @State private var resumeColorTimerWorkToken = UUID()
    private let beepLockDuration: TimeInterval = 0.20
    private let cueVisibleDuration: TimeInterval = 1.40
        
        // Session tracking
        @State private var sessionStartTime: Date?
        @State private var sessionDuration: TimeInterval = 0
    
    // Arrow directions for colorsArrows mode
    private let arrowDirections = [
        "arrow.up",
        "arrow.down", 
        "arrow.left",
        "arrow.right",
        "arrow.up.left",
        "arrow.up.right",
        "arrow.down.left",
        "arrow.down.right"
    ]
    
    // Critical Scan state variables
    @State private var criticalScanPhase: String = "NORMAL"
    @State private var criticalScanTimer: Timer?
    
    // Scanning circles for normal scan phase
    @State private var currentScanningCircleColor: Color = .white
    @State private var scanningCircleTimer: Timer?
    @State private var scanningColorIndex: Int = 0
    
    @State private var countdown: Int = 3
    @State private var isCountingDown: Bool = true
    @State private var countdownTimer: Timer?
    @Environment(\.dismiss) private var dismiss
    
    // Screen protection timer for outdoor use
    @State private var screenProtectionTimer: Timer?
    
    // Scanning Game state variables
    @State private var scanningGamePhase: String = "NORMAL"
    @State private var activePlayers: [GamePlayer] = []
    @State private var playersVisible: Bool = false
    @State private var scanningGameTimer: Timer?
    /// Wandering and committed positions (key = player id). Updated by wander timer and on trigger.
    @State private var scanningGamePositions: [UUID: CGPoint] = [:]
    @State private var scanningGameWanderTimer: Timer?
    
    // Pressure Response state variables
    @State private var currentPressureDirection: PressureDirection?
    @State private var pressureResponseTimer: Timer?
    @State private var opponentPositionX: CGFloat = 0
    @State private var opponentPositionY: CGFloat = 0
    @State private var opponentMovingDirection: Bool = true // true = moving right, false = moving left
    // Defender wandering in upper screen (prepare phase) — only for Pressure Response
    @State private var pressureResponseDefenderWanderX: CGFloat = 0.5
    @State private var pressureResponseDefenderWanderY: CGFloat = 0.25
    @State private var pressureResponseWanderTimer: Timer?
    /// Current round's defender action (for animation phases). nil when not in a triggered round.
    @State private var pressureResponseDefenderAction: PressureResponseDefenderAction?
    /// For "fake step then drop": show defender at this X during fake, then animate to real side.
    @State private var pressureResponseFakeStepX: CGFloat?
    @State private var pressureResponseNoPressEndWorkToken = UUID()
    
    // One-Touch Passing state variables
    @State private var currentPassDirection: PassDirection?
    @State private var teammatePositionX: CGFloat = 0
    @State private var teammatePositionY: CGFloat = 0
    @State private var oneTouchPassingTimer: Timer?
    /// true = teammate on left, false = teammate on right (no tap — movement only)
    @State private var oneTouchTeammateOnLeft: Bool?
    /// Teammate image name for this round (set once so face doesn’t change during the round)
    @State private var oneTouchTeammateImageNameForRound: String = ""
    @State private var oneTouchWanderTimer: Timer?
    
    // 4-Goal Game state variables
    @State private var fourGoalGamePhase: String = "NORMAL"
    @State private var fourGoalGameTimer: Timer?

    @State private var leftImagePosition: ImagePosition = .middleLeft
    @State private var rightImagePosition: ImagePosition = .middleRight
    @State private var leftImageTargetPosition: GoalCorner = .topLeft
    @State private var rightImageTargetPosition: GoalCorner = .bottomRight
    @State private var imageMovementTimer: Timer?
    @State private var selectedCriticalScanColor: Color = .blue
    

    
    let availableLanes = ["Left", "Center", "Right"]
    /// Same display size for all player images (YOU, teammate, opponent) across activities.
    private static let playerImageSizeRatio: CGFloat = 0.35
    /// Larger defender in Pressure Response so movement is easy to see.
    private static let pressureResponseDefenderSizeRatio: CGFloat = 0.5
    
        init(selectedColors: [Color], displayMode: DisplayMode, changeInterval: Double, selectedNumbers: [Int], soundEnabled: Bool, laneSpeed: Double, numberRange: Double, selectedArrows: [String], selectedBeepInterval: BeepInterval, beepMode: BeepMode, fixedBeepInterval: Double, criticalScanDelay: Double, criticalScanDuration: Double, criticalScanResetTime: Double, teammateMovementDuration: Double, opponentMovementDuration: Double, trainingPerspective: String, selectedColorSet: ScanningColorSet, selectedActionSet: ActionSet, customActions: [CustomAction], screenProtectionEnabled: Bool, numberColor: Color, arrowColor: Color, userTeamColor: TeamColor, opponentColor: TeamColor, playerGender: PlayerGender, numberOfOpponents: Int, numberOfTeammates: Int, numberOfOpenSpaces: Int, fourGoalLeftColor: Color, fourGoalRightColor: Color, showDisplay: Binding<Bool>, profileManager: UserProfileManager) {
            self.profileManager = profileManager
        self.selectedColors = selectedColors
        self.displayMode = displayMode
        self.changeInterval = changeInterval
        self.selectedNumbers = selectedNumbers
        self.soundEnabled = soundEnabled
        self.laneSpeed = laneSpeed
        self.numberRange = numberRange
        self.selectedArrows = selectedArrows
        self.selectedBeepInterval = selectedBeepInterval
        self.beepMode = beepMode
        self.fixedBeepInterval = fixedBeepInterval
        self.criticalScanDelay = criticalScanDelay
        self.criticalScanDuration = criticalScanDuration
        self.criticalScanResetTime = criticalScanResetTime
        self.teammateMovementDuration = teammateMovementDuration
        self.opponentMovementDuration = opponentMovementDuration
        self.trainingPerspective = trainingPerspective
        self.selectedColorSet = selectedColorSet
            self.selectedActionSet = selectedActionSet
        self.customActions = customActions
            self._currentColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
            self._currentNumberColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
            self._showDisplay = showDisplay
            self.screenProtectionEnabled = screenProtectionEnabled
            self.numberColor = numberColor
            self.arrowColor = arrowColor
            self.userTeamColor = userTeamColor
            self.opponentColor = opponentColor
            self.playerGender = playerGender
            self.numberOfOpponents = numberOfOpponents
            self.numberOfTeammates = numberOfTeammates
            self.numberOfOpenSpaces = numberOfOpenSpaces
            self.fourGoalLeftColor = fourGoalLeftColor
            self.fourGoalRightColor = fourGoalRightColor
    }
    
    // MARK: - Helper Functions
    
    private func getBeepInterval() -> Double {
        switch beepMode {
        case .range:
            return Double.random(in: selectedBeepInterval.range)
        case .fixed:
            return fixedBeepInterval
        }
    }
    
    var body: some View {
        ZStack {
            // Ensure complete screen coverage
                Color.black.ignoresSafeArea()
                
            if isCountingDown {
                // Countdown screen
                VStack {
                    Text("\(countdown)")
                        .font(.system(size: 200, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(countdown > 0 ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.5), value: countdown)
                    
                    if countdown == 0 {
                        Text("GO!")
                                .font(.system(size: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.15, weight: .bold))
                            .foregroundColor(.green)
                            .scaleEffect(1.2)
                            .animation(.easeInOut(duration: 0.3), value: countdown)
                    }
                }
            } else {
                // Main activity screen
                
                if displayMode == .colors {
                    // Colors display
                    ZStack {
                    currentColor
                        .ignoresSafeArea()
                    }
                } else if displayMode == .colorsNumbers {
                    // Colors with Numbers display
                    ZStack {
                        currentColor
                            .ignoresSafeArea()
                        
                        if showNumberOrArrow {
                            VStack {
                                Text("\(currentNumber)")
                                    .font(.system(size: 300, weight: .black))
                                        .foregroundColor(numberColor)
                                    .shadow(radius: 15)
                            }
                        }
                    }
                } else if displayMode == .colorsArrows {
                    // Colors with Arrows display
                    ZStack {
                        currentColor
                            .ignoresSafeArea()
                        
                        if showNumberOrArrow {
                            VStack {
                                Image(systemName: currentArrowDirection)
                                        .font(.system(size: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.35, weight: .black))
                                        .foregroundColor(arrowColor)
                                        .shadow(radius: 10)
                            }
                        }
                    }
                } else if displayMode == .numbers {
                    // Numbers display
                    ZStack {
                        currentNumberColor
                            .ignoresSafeArea()
                        
                        VStack {
                    Text("\(currentNumber)")
                                .font(.system(size: 300, weight: .bold))
                                    .foregroundColor(numberColor)
                                .shadow(radius: 10)
                        }
                    }
                } else if displayMode == .lanes {
                    // Lanes display
                    ZStack {
                        Color.black
                            .ignoresSafeArea()
                        
                        HStack(spacing: 0) {
                            ForEach(availableLanes, id: \.self) { lane in
                                    Rectangle()
                                    .fill(laneColors[lane] ?? Color.gray)
                                        .frame(maxWidth: .infinity)
                            }
                        }
                        .offset(y: animationOffset)
                    }
                } else if displayMode == .scanningGame {
                    // Scanning Game display
                    ZStack {
                        // Background color based on phase
                        if scanningGamePhase == "NORMAL" || scanningGamePhase == "BEEP" {
                            Color.black
                                .ignoresSafeArea()
                        } else if scanningGamePhase == "SCANNING" {
                            Color.black
                                .ignoresSafeArea()
                        } else if scanningGamePhase == "RESET" {
                            Color.blue
                                .ignoresSafeArea()
                        } else {
                            Color.black
                                .ignoresSafeArea()
                        }
                        
                        VStack(spacing: 20) {
                            if scanningGamePhase == "NORMAL" || scanningGamePhase == "BEEP" {
                                // Wandering phase: defenders and teammates move subtly; trigger commits them to 4 slots
                                ZStack(alignment: .top) {
                                    Text("Check to passer — tap when ready")
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                        .padding(.top, 50)
                                    // Center marker
                                    VStack(spacing: 10) {
                                        Text("X")
                                            .font(.system(size: 80, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(radius: 5)
                                    }
                                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
                                    // Wandering players (positions from scanningGamePositions)
                                    ForEach(activePlayers) { player in
                                        let pos = scanningGamePositions[player.id] ?? getPlayerPosition(for: player.direction)
                                        PlayerView(player: player, isVisible: true)
                                            .position(pos)
                                            .animation(.easeInOut(duration: 0.6), value: scanningGamePositions[player.id]?.x ?? 0)
                                            .animation(.easeInOut(duration: 0.6), value: scanningGamePositions[player.id]?.y ?? 0)
                                    }
                                    VStack(spacing: 12) {
                                        Spacer()
                                        Button(action: triggerScanningGameCommit) {
                                            Text("Trigger defender")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 32)
                                                .padding(.vertical, 16)
                                                .background(Color.white)
                                                .cornerRadius(12)
                                        }
                                        .padding(.bottom, 60)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if scanningGamePhase == "SCANNING" {
                                // Players at slots (committed positions)
                                ZStack {
                                    VStack(spacing: 10) {
                                        Text("X")
                                            .font(.system(size: 80, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(radius: 5)
                                    }
                                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
                                    ForEach(activePlayers) { player in
                                        let pos = scanningGamePositions[player.id] ?? getPlayerPosition(for: player.direction)
                                        PlayerView(player: player, isVisible: true)
                                            .position(pos)
                                            .animation(.easeInOut(duration: 0.3), value: scanningGamePositions[player.id]?.x ?? 0)
                                            .animation(.easeInOut(duration: 0.3), value: scanningGamePositions[player.id]?.y ?? 0)
                                    }
                                }
                            } else if scanningGamePhase == "RESET" {
                                VStack(spacing: 15) {
                                    Text("RESET")
                                        .font(.system(size: 60, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 10)
                                    
                                    Text("Prepare for Next Play")
                                        .font(.system(size: 40, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                    
                                    Text("Get in position • Focus • Ready")
                                        .font(.system(size: 25, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            }
                        }
                    }
                } else if displayMode == .pressureResponse {
                    // Pressure Response display — single background color for whole activity
                    ZStack {
                        Color.black
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            if criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" {
                                // Defender wandering in upper part; you (receiver) at bottom the whole time; tap when ready
                                ZStack(alignment: .top) {
                                    Text("Check to passer — tap when ready")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                        .padding(.top, 50)
                                    // Wandering defender in upper band (larger for visibility)
                                    Image("player_\(playerGender.rawValue.lowercased())_\(opponentColor.rawValue.lowercased())_jersey")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.pressureResponseDefenderSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.pressureResponseDefenderSizeRatio)
                                        .shadow(radius: 10)
                                        .position(
                                            x: UIScreen.main.bounds.width * pressureResponseDefenderWanderX,
                                            y: UIScreen.main.bounds.height * pressureResponseDefenderWanderY
                                        )
                                        .animation(.easeInOut(duration: 0.5), value: pressureResponseDefenderWanderX)
                                        .animation(.easeInOut(duration: 0.5), value: pressureResponseDefenderWanderY)
                                    // You (receiver) at bottom — visible the whole time
                                    VStack(spacing: 10) {
                                        Image("player_\(playerGender.rawValue.lowercased())_\(userTeamColor.rawValue.lowercased())_jersey")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                            .shadow(radius: 10)
                                            .rotationEffect(.degrees(trainingPerspective == "front" ? 180 : 0))
                                    }
                                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.8)
                                    // Trigger button (for now on iPad; later iPhone will trigger)
                                    VStack(spacing: 12) {
                                        Spacer()
                                        Button(action: triggerPressureResponseDefender) {
                                            Text("Trigger defender")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 32)
                                                .padding(.vertical, 16)
                                                .background(Color.white)
                                                .cornerRadius(12)
                                        }
                                        .padding(.bottom, 60)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if criticalScanPhase == "CRITICAL" {
                                // Same layout: you at bottom, defender commits (moves or stays)
                                ZStack {
                                    // User player near bottom center (same position as prepare phase)
                                    VStack(spacing: 10) {
                                        Image("player_\(playerGender.rawValue.lowercased())_\(userTeamColor.rawValue.lowercased())_jersey")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                            .shadow(radius: 10)
                                            .rotationEffect(.degrees(trainingPerspective == "front" ? 180 : 0))
                                    }
                                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.8)
                                    
                                    // Moving opponent (or fake-step X override; or no-press = stay at wander) — larger for visibility
                                    if currentPressureDirection != nil || pressureResponseFakeStepX != nil || pressureResponseDefenderAction == .noPress {
                                        let x = pressureResponseFakeStepX ?? opponentPositionX
                                        Image("player_\(playerGender.rawValue.lowercased())_\(opponentColor.rawValue.lowercased())_jersey")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.pressureResponseDefenderSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.pressureResponseDefenderSizeRatio)
                                            .shadow(radius: 10)
                                            .position(x: x, y: opponentPositionY)
                                            .animation(.linear(duration: opponentMovementDuration), value: opponentPositionX)
                                            .animation(.linear(duration: opponentMovementDuration), value: opponentPositionY)
                                            .animation(.easeInOut(duration: 0.25), value: pressureResponseFakeStepX ?? 0)
                                    }
                                }
                            } else if criticalScanPhase == "RESET" {
                                VStack(spacing: 15) {
                                    Text("RESET")
                                        .font(.system(size: 60, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 10)
                                    
                                    Text("Prepare for Next Pressure")
                                        .font(.system(size: 40, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                    
                                    Text("Get in position • Focus • Ready")
                                        .font(.system(size: 25, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            }
                        }
                    }
                } else if displayMode == .oneTouchPassing {
                    // One-Touch Passing display (single background color)
                    ZStack {
                        Color.black
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            if criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" {
                                // Wandering phase: teammate and opponent move subtly in middle; trigger commits them to sides
                                ZStack(alignment: .top) {
                                    Text("Check to passer — tap when ready")
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                        .padding(.top, 50)
                                    // User (with ball) at bottom center
                                    VStack(spacing: 10) {
                                        Image("player_\(playerGender.rawValue.lowercased())_\(userTeamColor.rawValue.lowercased())_jersey")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                            .shadow(radius: 10)
                                            .rotationEffect(.degrees(trainingPerspective == "front" ? 180 : 0))
                                    }
                                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.8)
                                    // Teammate and opponent wandering in middle
                                    if !oneTouchTeammateImageNameForRound.isEmpty {
                                        Image(oneTouchTeammateImageNameForRound)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                            .shadow(radius: 10)
                                            .position(x: teammatePositionX, y: teammatePositionY)
                                            .animation(.easeInOut(duration: 0.6), value: teammatePositionX)
                                            .animation(.easeInOut(duration: 0.6), value: teammatePositionY)
                                    }
                                    Image("player_\(playerGender.rawValue.lowercased())_\(opponentColor.rawValue.lowercased())_jersey")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                        .shadow(radius: 10)
                                        .position(x: opponentPositionX, y: opponentPositionY)
                                        .animation(.easeInOut(duration: 0.6), value: opponentPositionX)
                                        .animation(.easeInOut(duration: 0.6), value: opponentPositionY)
                                    VStack(spacing: 12) {
                                        Spacer()
                                        Button(action: triggerOneTouchPassingCommit) {
                                            Text("Pass Made")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 32)
                                                .padding(.vertical, 16)
                                                .background(Color.white)
                                                .cornerRadius(12)
                                        }
                                        .padding(.bottom, 60)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if criticalScanPhase == "CRITICAL" {
                                // One-touch: YOU at bottom; teammate and opponent start center then move to sides. Pass to teammate's side.
                                ZStack {
                                    // User (with ball) at bottom center
                                    VStack(spacing: 10) {
                                        Image("player_\(playerGender.rawValue.lowercased())_\(userTeamColor.rawValue.lowercased())_jersey")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                            .shadow(radius: 10)
                                            .rotationEffect(.degrees(trainingPerspective == "front" ? 180 : 0))
                                    }
                                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.8)
                                    
                                    // Teammate: same team color, different face (fixed for this round)
                                    if oneTouchTeammateOnLeft != nil, !oneTouchTeammateImageNameForRound.isEmpty {
                                        Image(oneTouchTeammateImageNameForRound)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                            .shadow(radius: 10)
                                            .position(x: teammatePositionX, y: teammatePositionY)
                                            .animation(.easeInOut(duration: teammateMovementDuration), value: teammatePositionX)
                                            .animation(.easeInOut(duration: teammateMovementDuration), value: teammatePositionY)
                                    }
                                    
                                    // Opponent – moves to the other side (uses Opponent Movement Speed)
                                    if oneTouchTeammateOnLeft != nil {
                                        Image("player_\(playerGender.rawValue.lowercased())_\(opponentColor.rawValue.lowercased())_jersey")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                            .shadow(radius: 10)
                                            .position(x: opponentPositionX, y: opponentPositionY)
                                            .animation(.easeInOut(duration: opponentMovementDuration), value: opponentPositionX)
                                            .animation(.easeInOut(duration: opponentMovementDuration), value: opponentPositionY)
                                    }
                                    
                                }
                            } else if criticalScanPhase == "RESET" {
                                VStack(spacing: 15) {
                                    Text("RESET")
                                        .font(.system(size: 60, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 10)
                                    
                                    Text("Prepare for Next Pass")
                                        .font(.system(size: 40, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                    
                                    Text("Get in position • Focus • Ready")
                                        .font(.system(size: 25, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            }
                        }
                    }
                } else if displayMode == .fourGoalGame {
                    // 4-Goal Game display
                    ZStack {
                        // Background color based on phase
                        if fourGoalGamePhase == "NORMAL" || fourGoalGamePhase == "BEEP" {
                            Color.black
                                .ignoresSafeArea()
                        } else if fourGoalGamePhase == "CRITICAL" {
                            // Use the pre-selected critical scan color
                            selectedCriticalScanColor
                                .ignoresSafeArea()
                        } else if fourGoalGamePhase == "RESET" {
                            Color.blue
                                .ignoresSafeArea()
                        } else {
                            Color.black
                                .ignoresSafeArea()
                        }
                        
                        VStack(spacing: 20) {
                            if fourGoalGamePhase == "NORMAL" || fourGoalGamePhase == "BEEP" {
                                VStack(spacing: 15) {
                                    // Scanning circle (cycles through colors every second)
                                    Circle()
                                        .fill(selectedColorSet.colors[scanningColorIndex])
                                        .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.6, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.6)
                                        .background(Color.black)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                    
                                    Text("SCAN & PREPARE")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                }
                            } else if fourGoalGamePhase == "CRITICAL" {
                                // Display 4-goal game scenario
                                ZStack {
                                    // Left image (player)
                                    Image("player_\(playerGender.rawValue.lowercased())_\(opponentColor.rawValue.lowercased())_jersey")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                        .shadow(radius: 10)
                                        .position(getImagePosition(for: leftImagePosition, isLeft: true))
                                        .animation(.easeInOut(duration: opponentMovementDuration), value: leftImagePosition)
                                    
                                    // Right image (player)
                                    Image("player_\(playerGender.rawValue.lowercased())_\(opponentColor.rawValue.lowercased())_jersey")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio, height: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * Self.playerImageSizeRatio)
                                        .shadow(radius: 10)
                                        .position(getImagePosition(for: rightImagePosition, isLeft: false))
                                        .animation(.easeInOut(duration: opponentMovementDuration), value: rightImagePosition)
                                    

                                }
                            } else if fourGoalGamePhase == "RESET" {
                                VStack(spacing: 15) {
                                    Text("RESET")
                                        .font(.system(size: 60, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 10)
                                    
                                    Text("Prepare for Next Play")
                                        .font(.system(size: 40, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                    
                                    Text("Get in position • Focus • Ready")
                                        .font(.system(size: 25, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            }
                        }
                    }
                }
            }
            
            // Double tap indicator (only show after countdown)
            if !isCountingDown {
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(8)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                    
                    Text("Double tap anywhere on the screen to end training")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .onAppear {
                // Set brightness and prevent sleep based on toggle setting
                if screenProtectionEnabled {
                    UIScreen.main.brightness = 1.0
                    UIApplication.shared.isIdleTimerDisabled = true
                } else {
                    UIApplication.shared.isIdleTimerDisabled = true // Always prevent sleep during training
                }
            if displayMode == .pressureResponse || displayMode == .scanningGame || displayMode == .oneTouchPassing {
                ConnectionManager.shared.startHosting()
            }
            startCountdown()
        }
        .onDisappear {
            ConnectionManager.shared.stopHosting()
            isActive = false
            countdownTimer?.invalidate()
            countdownTimer = nil
            stopTimer()
            scanningGameWanderTimer?.invalidate()
            scanningGameWanderTimer = nil
            oneTouchWanderTimer?.invalidate()
            oneTouchWanderTimer = nil
                
                // End session tracking
                if let startTime = sessionStartTime {
                    sessionDuration = Date().timeIntervalSince(startTime)
                    endTrainingSession()
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pressureResponseTrigger)) { _ in
            if displayMode == .pressureResponse {
                triggerPressureResponseDefender()
            } else if displayMode == .scanningGame && (scanningGamePhase == "NORMAL" || scanningGamePhase == "BEEP") {
                triggerScanningGameCommit()
            } else if displayMode == .oneTouchPassing && (criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP") {
                triggerOneTouchPassingCommit()
            }
        }
        .onTapGesture(count: 2) {
            endTrainingSessionAndReturn()
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = 3
        isCountingDown = true
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            countdown -= 1
            
            if countdown < 0 {
                countdownTimer?.invalidate()
                countdownTimer = nil
                isCountingDown = false
                startActivity()
            }
        }
    }
    
    private func startActivity() {
        print("🎯 Start Activity - Display Mode: \(displayMode)")
        showNumberOrArrow = false // Reset at start
        
        // Initialize with random values for immediate display
        if displayMode == .numbers {
            if let randomNumber = selectedNumbers.randomElement() {
                currentNumber = randomNumber
            }
            if let randomColor = selectedColors.randomElement() {
                currentNumberColor = randomColor
            }
        }
        
        startTimer()
        setupAudio()
        
            // Start session tracking
            sessionStartTime = Date()
            startTrainingSession()
            
            // Start screen protection timer for outdoor use
            startScreenProtectionTimer()
        
        if displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .numbers || displayMode == .lanes {
            startBeepTimer()
        } else if displayMode != .scanningGame && displayMode != .pressureResponse && displayMode != .oneTouchPassing {
            scheduleRandomBeep()
        }
        
        if displayMode == .lanes {
            assignColorsToLanes()
            startLaneAnimation()
        } else if displayMode == .scanningGame {
            print("🎮 Starting Scanning Game Mode")
            startScanningGameSequence()
        } else if displayMode == .pressureResponse {
            print("🛡️ Starting Pressure Response Mode")
            startPressureResponseSequence()
        } else if displayMode == .oneTouchPassing {
            print("⚽ Starting One-Touch Passing Mode")
            startOneTouchPassingSequence()
        } else if displayMode == .fourGoalGame {
            print("⚽ Starting 4-Goal Game Mode")
            startFourGoalGameSequence()
        } else if displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows {
            print("🎨 Starting \(displayMode) Mode")
            // These modes use the standard timer + beep timer
        } else {
            print("🎯 Starting other mode: \(displayMode)")
        }
    }
        
        // MARK: - Session Tracking Methods
        
        private func startTrainingSession() {
            let settings = TrainingSessionSettings(
                displayMode: displayMode,
                colorsUsed: selectedColors,
                numbersUsed: selectedNumbers,
                arrowsUsed: selectedArrows,
                lanesUsed: availableLanes,
                beepInterval: selectedBeepInterval,
                numberColor: numberColor,
                arrowColor: arrowColor,
                colorSet: selectedColorSet,
                actionSet: selectedActionSet,
                customActions: customActions,
                criticalScanDelay: criticalScanDelay,
                criticalScanDuration: criticalScanDuration,
                criticalScanResetTime: criticalScanResetTime,
                screenProtectionEnabled: screenProtectionEnabled,
                soundEnabled: soundEnabled
            )
            
            profileManager.startTrainingSession(settings: settings)
        }
        
        private func endTrainingSession() {
            profileManager.endTrainingSession(duration: sessionDuration)
    }
    
    private func startLaneAnimation() {
        guard displayMode == .lanes else { return }
        
        // Randomly choose direction
        let movingUp = Bool.random()
        
        if movingUp {
            // Start from bottom of screen
            animationOffset = UIScreen.main.bounds.height
            
            withAnimation(.linear(duration: laneSpeed)) {
                // Move to top of screen
                animationOffset = -UIScreen.main.bounds.height
            }
        } else {
            // Start from top of screen
            animationOffset = -UIScreen.main.bounds.height
            
            withAnimation(.linear(duration: laneSpeed)) {
                // Move to bottom of screen
                animationOffset = UIScreen.main.bounds.height
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + laneSpeed) {
            startLaneAnimation() // Restart animation with new random direction
        }
    }
    
    private func setupAudio() {
        PBABeepSoundManager.shared.preloadCurrent()
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: changeInterval, repeats: true) { _ in
            // Avoid changing visual cues while the beep is playing.
            if isBeepLockActive { return }
            if displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows {
                currentColor = getRandomColor(excluding: currentColor, from: selectedColors)
            } else if displayMode == .numbers {
                if let randomNumber = selectedNumbers.randomElement() {
                    currentNumber = randomNumber
                    currentNumberColor = getRandomColor(excluding: currentNumberColor, from: selectedColors)
                }
            } else if displayMode == .lanes {
                assignColorsToLanes()
            }
        }
    }
    
    private func assignColorsToLanes() {
        var shuffledColors = selectedColors.shuffled()
        laneColors.removeAll()
        
        for lane in availableLanes {
            if !shuffledColors.isEmpty {
                laneColors[lane] = shuffledColors.removeFirst()
            }
        }
    }
    
    private func startBeepTimer() {
        stopBeepTimer() // Ensure any existing timers are stopped
        
        // Schedule first beep immediately
        scheduleNextBeep()
    }
    
    private func scheduleNextBeep() {
        guard isActive && (displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .numbers || displayMode == .lanes) else { return }
        
        // Prevent multiple concurrent schedules
        guard !isBeepScheduled else { return }
        isBeepScheduled = true
        
        let randomInterval = getBeepInterval()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
            guard isActive && (displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .numbers || displayMode == .lanes) else { 
                isBeepScheduled = false
                return 
            }
            
            // Play beep (PBA training beep)
            if soundEnabled {
                isBeepLockActive = true
                PBABeepSoundManager.shared.play(soundEnabled: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + beepLockDuration) {
                    isBeepLockActive = false
                }
            }
            
            // Show number or arrow for specific modes
            if displayMode == .colorsNumbers {
                if let randomNumber = selectedNumbers.randomElement() {
                    currentNumber = randomNumber
                }
                showNumberOrArrow = true
                suspendColorTimerForCue()
                
                // Hide cue after configured visibility window.
                DispatchQueue.main.asyncAfter(deadline: .now() + cueVisibleDuration) {
                    showNumberOrArrow = false
                }
            } else if displayMode == .colorsArrows {
                currentArrowDirection = selectedArrows.randomElement() ?? "arrow.up"
                showNumberOrArrow = true
                suspendColorTimerForCue()
                
                // Hide cue after configured visibility window.
                DispatchQueue.main.asyncAfter(deadline: .now() + cueVisibleDuration) {
                    showNumberOrArrow = false
                }
            }
            // For regular colors, numbers, and lanes modes, just play the beep without showing additional elements
            
            // Reset flag and schedule next beep
            isBeepScheduled = false
            scheduleNextBeep()
        }
    }
    
    private func stopBeepTimer() {
        beepTimer?.invalidate()
        beepTimer = nil
        isBeepScheduled = false
    }

    private func suspendColorTimerForCue() {
        guard displayMode == .colorsNumbers || displayMode == .colorsArrows else { return }
        timer?.invalidate()
        timer = nil
        resumeColorTimerWorkToken = UUID()
        let token = resumeColorTimerWorkToken
        DispatchQueue.main.asyncAfter(deadline: .now() + cueVisibleDuration) {
            guard self.resumeColorTimerWorkToken == token else { return }
            guard isActive else { return }
            self.startTimer()
        }
    }
    
    private func scheduleRandomBeep() {
        guard soundEnabled && isActive else { return }
        
        // Don't schedule beeps for Critical Scan modes or modes with their own beep timer
        guard displayMode != .fourGoalGame && displayMode != .colors && displayMode != .colorsNumbers && displayMode != .colorsArrows && displayMode != .numbers && displayMode != .lanes else { return }
        
        let randomInterval = Double.random(in: 10...15)
        DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
            if soundEnabled && isActive && displayMode != .fourGoalGame && displayMode != .colors && displayMode != .colorsNumbers && displayMode != .colorsArrows && displayMode != .numbers && displayMode != .lanes {
                PBABeepSoundManager.shared.play(soundEnabled: true)
                scheduleRandomBeep() // Schedule next beep
            }
        }
    }
    
    private func stopTimer() {
        resumeColorTimerWorkToken = UUID()
        countdownTimer?.invalidate()
        countdownTimer = nil
        timer?.invalidate()
        timer = nil
        stopBeepTimer()
    }
    
        private func startScreenProtectionTimer() {
            guard screenProtectionEnabled else { return }
            
            screenProtectionTimer?.invalidate()
            screenProtectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                UIScreen.main.brightness = 1.0
            }
        }
        
        private func stopScreenProtectionTimer() {
            screenProtectionTimer?.invalidate()
            screenProtectionTimer = nil
        }
        
        private func startResetPhase() {
            guard isActive else { return }
            
            print("🔵 Starting Reset Phase")
            
            // Set reset phase based on display mode
            if displayMode == .fourGoalGame {
                fourGoalGamePhase = "RESET"
                // Ensure both images are centered before the next round begins
                withTransaction(Transaction(animation: nil)) {
                    leftImagePosition = .middleLeft
                    rightImagePosition = .middleRight
                }
            } else {
            criticalScanPhase = "RESET"
            }
            
            // End reset phase after reset time
            DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanResetTime) {
                startNormalPhase()
            }
        }
        
        private func startNormalPhase() {
            guard isActive else { return }
            
            print("⚪ Starting Normal Phase")
            
            // Set normal phase based on display mode
            if displayMode == .fourGoalGame {
                fourGoalGamePhase = "NORMAL"
            } else {
            criticalScanPhase = "NORMAL"
            }
            
            // Schedule next round only for 4-Goal Game (pressure/one-touch use user trigger)
            if displayMode == .fourGoalGame {
                DispatchQueue.main.asyncAfter(deadline: .now() + getBeepInterval()) {
                    startFourGoalGamePhase()
                }
            }
        }
    
    private func getRandomColor(excluding currentColor: Color, from availableColors: [Color]) -> Color {
        let filteredColors = availableColors.filter { $0 != currentColor }
        return filteredColors.randomElement() ?? availableColors.randomElement() ?? .red
    }
    
    private func colorName(for color: Color) -> String {
        if color == Color(red: 0.8, green: 0.0, blue: 0.0) { return "Red" }
        if color == .blue { return "Blue" }
        if color == .green { return "Green" }
        if color == Color(red: 1.0, green: 0.8, blue: 0.0) { return "Yellow" }
        if color == Color(red: 0.9, green: 0.5, blue: 0.0) { return "Orange" }
        if color == .white { return "White" }
        if color == .black { return "Black" }
        if color == Color(red: 1.0, green: 0.4, blue: 0.8) { return "Pink" }
        return "Unknown"
    }
    
    private func getImagePosition(for position: ImagePosition, isLeft: Bool) -> CGPoint {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        switch position {
        case .middleLeft:
            return CGPoint(x: screenWidth * 0.25, y: screenHeight * 0.5)
        case .middleRight:
            return CGPoint(x: screenWidth * 0.75, y: screenHeight * 0.5)
        case .topLeft:
            return CGPoint(x: screenWidth * 0.2, y: screenHeight * 0.2)
        case .topRight:
            return CGPoint(x: screenWidth * 0.8, y: screenHeight * 0.2)
        case .bottomLeft:
            return CGPoint(x: screenWidth * 0.2, y: screenHeight * 0.8)
        case .bottomRight:
            return CGPoint(x: screenWidth * 0.8, y: screenHeight * 0.8)
        }
    }
    
    private func startFourGoalGameSequence() {
        print("⚽ Starting 4-Goal Game Sequence")
        
        // Start scanning circle timer
        scanningCircleTimer = Timer.scheduledTimer(withTimeInterval: changeInterval, repeats: true) { _ in
            scanningColorIndex = (scanningColorIndex + 1) % selectedColorSet.colors.count
        }
        
        // Schedule first critical scan (same as other critical scan activities)
        DispatchQueue.main.asyncAfter(deadline: .now() + getBeepInterval()) {
            startFourGoalGamePhase()
        }
    }
    
    private func playCriticalScanSound() {
        PBABeepSoundManager.shared.play(soundEnabled: true)
    }
    
    private func startFourGoalGamePhase() {
        guard isActive else { return }
        
        print("🔴 Starting 4-Goal Game Phase")
        fourGoalGamePhase = "BEEP"
        
        // Play critical scan sound immediately
        if soundEnabled {
            playCriticalScanSound()
        }
        
        // Show critical phase after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDelay) {
            guard isActive else { return }
            
            fourGoalGamePhase = "CRITICAL"
            
            // Select the critical scan color once
            selectedCriticalScanColor = Bool.random() ? fourGoalLeftColor : fourGoalRightColor
            
            // Set initial positions (middle left and right)
            withTransaction(Transaction(animation: nil)) {
                leftImagePosition = .middleLeft
                rightImagePosition = .middleRight
            }
            
            // Randomly choose target corners for each side
            let leftCorners: [GoalCorner] = [.topLeft, .bottomLeft]
            let rightCorners: [GoalCorner] = [.topRight, .bottomRight]
            
            leftImageTargetPosition = leftCorners.randomElement() ?? .topLeft
            rightImageTargetPosition = rightCorners.randomElement() ?? .bottomRight
            
            // Move images to their target positions with animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                let isLeftSelected = (selectedCriticalScanColor == fourGoalLeftColor)
                withAnimation(.easeInOut(duration: opponentMovementDuration)) {
                    if isLeftSelected {
                        leftImagePosition = leftImageTargetPosition == .topLeft ? .topLeft : .bottomLeft
                        // keep right at middle (no assignment to avoid animating it)
                    } else {
                        rightImagePosition = rightImageTargetPosition == .topRight ? .topRight : .bottomRight
                        // keep left at middle (no assignment to avoid animating it)
                    }
                }
            }
            
            // End critical phase after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDuration) {
                startResetPhase()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func endTrainingSessionAndReturn() {
        if !isCountingDown {
            isActive = false
            
            // End session tracking
            if let startTime = sessionStartTime {
                sessionDuration = Date().timeIntervalSince(startTime)
                endTrainingSession()
            }
            
            showDisplay = false
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppRouter())
        .environmentObject(MultipeerManager())
}

struct ActionListSheet: View {
    let actionNumber: Int
    let currentAction: String
    let basicActions: [String]
    let onSelect: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var customActionText: String = ""
    @State private var showingCustomInput: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Select Action for Number \(actionNumber)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top)
                
                // Custom Action Input Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Custom Action")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack {
                        TextField("Type your custom action...", text: $customActionText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onAppear {
                                customActionText = currentAction
                            }
                        
                        Button(action: {
                            if !customActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onSelect(customActionText.trimmingCharacters(in: .whitespacesAndNewlines))
                                dismiss()
                            }
                        }) {
                            Text("Save")
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        .disabled(customActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal)
                
                // Predefined Actions Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Predefined Actions")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                            ForEach(basicActions, id: \.self) { action in
                                Button(action: {
                                    onSelect(action)
                                    dismiss()
                                }) {
                                    HStack {
                                        Text(action)
                                            .font(.body)
                                            .foregroundColor(.white)
                                        Spacer()
                                        if action == currentAction {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct ActivitiesGuideView: View {
    let selectedMode: DisplayMode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                        // Header
                    Text("Training Activities Guide")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        .padding(.top)
                        
                    // Mode-specific instructions
                    Group {
                        if selectedMode == .colors {
                            colorsGuide
                        } else if selectedMode == .colorsNumbers {
                            colorsNumbersGuide
                        } else if selectedMode == .colorsArrows {
                            colorsArrowsGuide
                        } else if selectedMode == .numbers {
                            numbersGuide
                        } else if selectedMode == .lanes {
                            lanesGuide
                        } else if selectedMode == .pressureResponse {
                            pressureResponseGuide
                        } else if selectedMode == .oneTouchPassing {
                            oneTouchPassingGuide
                        } else {
                            generalGuide
                        }
                    }
                    
                    Spacer()
                            }
                            .padding()
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                                                .foregroundColor(.white)
                }
            }
        }
    }
    
    private var colorsGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Colors Training")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Focus on recognizing different colors quickly and accurately.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Colors will change randomly")
                Text("• Focus on the screen center")
                Text("• React quickly to color changes")
                Text("• Build visual recognition speed")
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.blue.opacity(0.2))
        .cornerRadius(15)
    }
    
    private var colorsNumbersGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Colors + Numbers Training")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
            Text("Combine color recognition with number identification.")
                    .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Colors change continuously")
                Text("• Numbers appear at random intervals")
                Text("• Focus on both color and number")
                Text("• Numbers will beep when they appear")
            }
            .foregroundColor(.white.opacity(0.7))
                            }
                            .padding()
        .background(Color.green.opacity(0.2))
        .cornerRadius(15)
    }
    
    private var colorsArrowsGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Colors + Arrows Training")
                .font(.title2)
                .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
            Text("Combine color recognition with directional awareness.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Colors change continuously")
                Text("• Arrows appear at random intervals")
                Text("• Focus on both color and direction")
                Text("• Arrows will beep when they appear")
            }
            .foregroundColor(.white.opacity(0.7))
                            }
                            .padding()
        .background(Color.orange.opacity(0.2))
        .cornerRadius(15)
        }
    
    private var numbersGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Numbers Training")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Focus on number recognition and quick identification.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Numbers appear on colored backgrounds")
                Text("• Focus on the number in the center")
                Text("• React quickly to number changes")
                Text("• Build number recognition speed")
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.purple.opacity(0.2))
        .cornerRadius(15)
    }
    
    private var lanesGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Lanes Training")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
            
            Text("Focus on tracking moving elements across different lanes.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Colored lanes move up and down")
                Text("• Focus on the movement patterns")
                Text("• Track multiple lanes simultaneously")
                Text("• Build peripheral vision awareness")
            }
            .foregroundColor(.white.opacity(0.7))
                                        }
                                        .padding()
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(15)
                    }
                    
    
    private var pressureResponseGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Playing Away from Pressure")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Master defensive scanning and pressure response.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Normal scanning phase (white circles)")
                Text("• Critical phase (red background + opponent)")
                Text("• Opponent appears on left or right")
                Text("• Turn AWAY from the pressure")
                Text("• Reset phase (blue background)")
                Text("• Return to normal scanning")
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.orange.opacity(0.2))
        .cornerRadius(15)
    }
    
    private var oneTouchPassingGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("One-Touch Passing")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Master one-touch passing under pressure.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Normal scanning phase (white circles)")
                Text("• Critical phase (yellow background + teammate)")
                Text("• Teammate moves in 1 of 6 directions")
                Text("• One-touch pass in teammate's direction")
                Text("• Reset phase (blue background)")
                Text("• Return to normal scanning")
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.purple.opacity(0.2))
        .cornerRadius(15)
    }
    
    private var generalGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("General Training Tips")
                .font(.title2)
                .fontWeight(.bold)
                                    .foregroundColor(.white)
            
            Text("Maximize your scanning training effectiveness.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Focus on the screen center")
                Text("• Use your peripheral vision")
                Text("• React quickly to changes")
                Text("• Stay consistent with training")
                Text("• Gradually increase difficulty")
                    }
            .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(15)
    }
}

struct CustomActionSheet: View {
    let actionNumber: Int
    let currentAction: String
    let selectedActionSet: ActionSet
    let onSave: (String) -> Void
    
    @State private var customAction: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Custom Action for Number \(actionNumber)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter your custom action:")
                        .font(.headline)
                        .foregroundColor(.white)
         
                    TextField("e.g., Turn left, Sprint forward", text: $customAction)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onAppear {
                            customAction = currentAction
                        }
                }
                .padding(.horizontal)
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(10)
                    
                    Button("Save") {
                        onSave(customAction)
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.bottom)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PlayerView: View {
    let player: GamePlayer
    let isVisible: Bool
    
    // Calculate responsive image size based on device and orientation
    private var imageSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        // More reliable iPad detection using screen size
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        
        // Determine orientation and use appropriate sizing
        let isLandscape = screenWidth > screenHeight
        
        if isIPad {
            // Use orientation-aware sizing for iPads
            if isLandscape {
                // For iPad landscape: Use height to prevent overlap
                return screenHeight * 0.30
            } else {
                // For iPad portrait: Use width for consistent sizing
                return screenWidth * 0.30
            }
        } else {
            if isLandscape {
                // For iPhone landscape: Use smaller dimension (height) to prevent overlap
                return screenHeight * 0.22
            } else {
                // For iPhone portrait: Use moderate size
                return screenWidth * 0.29
            }
        }
    }
    
    var body: some View {
        Image(player.imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: imageSize, height: imageSize)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.8), value: isVisible)
    }
}

// MARK: - Pressure Response Logic Extension
extension DisplayView {
    
    private func startPressureResponseSequence() {
        print("🛡️ Starting Pressure Response Sequence")
        criticalScanPhase = "NORMAL"
        startPressureResponseWander()
    }
    
    /// Defender moves subtly in upper part of screen until user triggers (small steps like other activities).
    private func startPressureResponseWander() {
        pressureResponseWanderTimer?.invalidate()
        pressureResponseDefenderWanderX = 0.5
        pressureResponseDefenderWanderY = 0.25
        let bandX: CGFloat = 0.04
        let bandY: CGFloat = 0.025
        pressureResponseWanderTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard displayMode == .pressureResponse, criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" else {
                pressureResponseWanderTimer?.invalidate()
                return
            }
            let newX = min(max(pressureResponseDefenderWanderX + CGFloat.random(in: -bandX...bandX), 0.25), 0.75)
            let newY = min(max(pressureResponseDefenderWanderY + CGFloat.random(in: -bandY...bandY), 0.18), 0.35)
            pressureResponseDefenderWanderX = newX
            pressureResponseDefenderWanderY = newY
        }
        RunLoop.main.add(pressureResponseWanderTimer!, forMode: .common)
    }
    
    private func stopPressureResponseWander() {
        pressureResponseWanderTimer?.invalidate()
        pressureResponseWanderTimer = nil
    }
    
    /// Duration for defender to "commit" to one side from current position before running down.
    private static let pressureResponseCommitToSideDuration: Double = 0.3
    /// Short pause with defender at current position before she reacts (removes teleport feel, reads as "decision").
    private static let pressureResponseDecisionPause: Double = 0.25

    /// Called when user taps "Trigger defender" (or later when iPhone sends trigger). Picks 1 of 4 actions and runs it.
    /// Defender always starts from her current wander position.
    private func triggerPressureResponseDefender() {
        guard isActive, displayMode == .pressureResponse else { return }
        guard criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" else { return }
        stopPressureResponseWander()
        let action = PressureResponseDefenderAction.allCases.randomElement()!
        pressureResponseDefenderAction = action
        criticalScanPhase = "CRITICAL"
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        // Start defender from her current wander position (no teleport to top)
        opponentPositionX = screenWidth * pressureResponseDefenderWanderX
        opponentPositionY = screenHeight * pressureResponseDefenderWanderY
        pressureResponseFakeStepX = nil
        pressureResponseNoPressEndWorkToken = UUID()

        switch action {
        case .fastPressOneSide:
            generatePressureDirectionAndStartMove(delay: 0)
        case .delayedPressOneSide:
            let delay = Double.random(in: 0.5...1.2)
            generatePressureDirectionAndStartMove(delay: delay)
        case .fakeStepThenDrop:
            let realDirection = PressureDirection.allCases.randomElement()!
            currentPressureDirection = realDirection
            let realX = realDirection == .left ? screenWidth * 0.25 : screenWidth * 0.75
            let fakeX = realDirection == .left ? screenWidth * 0.55 : screenWidth * 0.45
            // Decision pause at current position, then animate from here to fake then real then down
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pressureResponseDecisionPause) {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    opponentPositionX = fakeX
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pressureResponseDecisionPause + 0.25) {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    opponentPositionX = realX
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard isActive else { return }
                    startOpponentStraightDownMovement()
                    schedulePressureResponseReset()
                }
            }
        case .noPress:
            currentPressureDirection = nil
            let token = pressureResponseNoPressEndWorkToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard self.pressureResponseNoPressEndWorkToken == token else { return }
                guard isActive else { return }
                startPressureResponseResetPhase()
            }
        }

        if action != .fakeStepThenDrop && action != .noPress {
            schedulePressureResponseReset()
        }
    }

    /// Pick a side, then from current (wander) position commit to that side and run down (with optional delay).
    private func generatePressureDirectionAndStartMove(delay: Double) {
        guard let direction = PressureDirection.allCases.randomElement() else { return }
        currentPressureDirection = direction
        if delay <= 0 {
            // Let view draw defender at wander, then decision pause, then commit (no teleport)
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.pressureResponseDecisionPause) {
                    guard isActive else { return }
                    startOpponentCommitThenDown(direction: direction)
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.pressureResponseDecisionPause) {
                guard isActive else { return }
                startOpponentCommitThenDown(direction: direction)
            }
        }
    }

    /// From current position, animate defender to commit to one side (same height), then run straight down.
    private func startOpponentCommitThenDown(direction: PressureDirection) {
        let screenWidth = UIScreen.main.bounds.width
        let sideX = direction == .left ? screenWidth * 0.25 : screenWidth * 0.75
        withAnimation(.easeOut(duration: Self.pressureResponseCommitToSideDuration)) {
            opponentPositionX = sideX
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pressureResponseCommitToSideDuration) {
            guard isActive else { return }
            startOpponentStraightDownMovement()
        }
    }
    
    private func schedulePressureResponseReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDuration) {
            guard isActive else { return }
            startPressureResponseResetPhase()
        }
    }
    
    private func startPressureResponseResetPhase() {
        guard isActive else { return }
        pressureResponseNoPressEndWorkToken = UUID()
        print("🔵 Starting Pressure Response Reset Phase")
        criticalScanPhase = "RESET"
        currentPressureDirection = nil
        pressureResponseDefenderAction = nil
        pressureResponseFakeStepX = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanResetTime) {
            guard isActive else { return }
            criticalScanPhase = "NORMAL"
            startPressureResponseWander()
        }
    }
    
    private func generatePressureDirection() {
        currentPressureDirection = PressureDirection.allCases.randomElement()
        if let direction = currentPressureDirection {
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            if direction == .left {
                opponentPositionX = screenWidth * 0.25
                opponentMovingDirection = false
            } else {
                opponentPositionX = screenWidth * 0.75
                opponentMovingDirection = true
            }
            opponentPositionY = screenHeight * 0.25
            startOpponentStraightDownMovement()
        }
    }
    
    private func startOpponentStraightDownMovement() {
        let screenHeight = UIScreen.main.bounds.height
        let finalTargetPositionY: CGFloat
        if trainingPerspective == "front" {
            finalTargetPositionY = screenHeight * 0.8
        } else {
            finalTargetPositionY = screenHeight * 0.7
        }
        withAnimation(.linear(duration: opponentMovementDuration)) {
            opponentPositionY = finalTargetPositionY
        }
    }
}

// MARK: - One-Touch Passing Logic Extension
extension DisplayView {
    
    private func startOneTouchPassingSequence() {
        print("⚽ Starting One-Touch Passing Sequence (wandering phase)")
        criticalScanPhase = "NORMAL"
        oneTouchTeammateImageNameForRound = oneTouchTeammateImageName()
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let centerY = screenHeight * 0.5
        teammatePositionX = screenWidth / 2
        teammatePositionY = centerY
        opponentPositionX = screenWidth / 2
        opponentPositionY = centerY
        oneTouchTeammateOnLeft = nil
        startOneTouchWander()
    }
    
    private func startOneTouchWander() {
        oneTouchWanderTimer?.invalidate()
        oneTouchWanderTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard isActive, displayMode == .oneTouchPassing, criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" else {
                oneTouchWanderTimer?.invalidate()
                oneTouchWanderTimer = nil
                return
            }
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            let centerX = screenWidth / 2
            let centerY = screenHeight * 0.5
            let band: CGFloat = 35
            teammatePositionX = min(max(teammatePositionX + CGFloat.random(in: -band...band), centerX - 80), centerX + 80)
            teammatePositionY = min(max(teammatePositionY + CGFloat.random(in: -band...band), centerY - 60), centerY + 60)
            opponentPositionX = min(max(opponentPositionX + CGFloat.random(in: -band...band), centerX - 80), centerX + 80)
            opponentPositionY = min(max(opponentPositionY + CGFloat.random(in: -band...band), centerY - 60), centerY + 60)
        }
        RunLoop.main.add(oneTouchWanderTimer!, forMode: .common)
    }
    
    /// After passMade: wait this range before teammate and defender begin movement (receiver reads while ball is traveling).
    private static let oneTouchMovementDelayRange: ClosedRange<Double> = 0.15 ... 0.25
    
    private func triggerOneTouchPassingCommit() {
        guard isActive, displayMode == .oneTouchPassing, criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" else { return }
        oneTouchWanderTimer?.invalidate()
        oneTouchWanderTimer = nil
        criticalScanPhase = "CRITICAL"
        let movementDelay = Double.random(in: Self.oneTouchMovementDelayRange)
        DispatchQueue.main.asyncAfter(deadline: .now() + movementDelay) {
            guard self.isActive, self.displayMode == .oneTouchPassing else { return }
            self.generatePassDirection()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDuration) {
            startOneTouchPassingResetPhase()
        }
    }
    
    private func generatePassDirection() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let centerY = screenHeight * 0.5
        
        // Randomly assign teammate to left or right; defender blocks the other passing lane
        let teammateOnLeft = Bool.random()
        oneTouchTeammateOnLeft = teammateOnLeft
        currentPassDirection = teammateOnLeft ? .left : .right
        
        let leftX = screenWidth * 0.25
        let rightX = screenWidth * 0.75
        // Teammate: diagonal movement to create a passing angle (not flat horizontal)
        let diagonalOffset = screenHeight * 0.12
        let teammateTargetX = teammateOnLeft ? leftX : rightX
        let teammateTargetY = centerY + (teammateOnLeft ? -diagonalOffset : diagonalOffset)
        // Defender: steps across to block one passing lane (other side)
        let (opponentTargetX, opponentTargetY) = teammateOnLeft ? (rightX, centerY) : (leftX, centerY)
        
        // Both accelerate smoothly (easeInOut), not instant full speed
        withAnimation(.easeInOut(duration: opponentMovementDuration)) {
            opponentPositionX = opponentTargetX
            opponentPositionY = opponentTargetY
        }
        withAnimation(.easeInOut(duration: teammateMovementDuration)) {
            teammatePositionX = teammateTargetX
            teammatePositionY = teammateTargetY
        }
        
        print("⚽ One-touch: teammate on \(teammateOnLeft ? "left" : "right") (diagonal), defender blocks other lane")
    }
    
    private func getTargetPosition(for direction: PassDirection, screenWidth: CGFloat, screenHeight: CGFloat) -> (CGFloat, CGFloat) {
        let basePosition: (CGFloat, CGFloat)
        
        switch direction {
        case .upLeft:
            basePosition = (screenWidth * 0.25, screenHeight * 0.25)
        case .upRight:
            basePosition = (screenWidth * 0.75, screenHeight * 0.25)
        case .left:
            basePosition = (screenWidth * 0.25, screenHeight * 0.5)
        case .right:
            basePosition = (screenWidth * 0.75, screenHeight * 0.5)
        case .downLeft:
            basePosition = (screenWidth * 0.25, screenHeight * 0.75)
        case .downRight:
            basePosition = (screenWidth * 0.75, screenHeight * 0.75)
        }
        
        if trainingPerspective == "front" {
            return basePosition
        } else {
            return basePosition
        }
    }
    
    private func startTeammateMovement(targetX: CGFloat, targetY: CGFloat) {
        withAnimation(.linear(duration: teammateMovementDuration)) {
            teammatePositionX = targetX
            teammatePositionY = targetY
        }
    }
    
    /// Teammate jersey color: different from YOU (user) and from opponent.
    private func oneTouchTeammateJerseyColor() -> TeamColor {
        TeamColor.allCases.first { $0 != userTeamColor && $0 != opponentColor } ?? .white
    }
    
    /// Teammate image: same team color as the player (userTeamColor), different face (_2, _3, _4 at random).
    private func oneTouchTeammateImageName() -> String {
        let base = "player_\(playerGender.rawValue.lowercased())_\(userTeamColor.rawValue.lowercased())_jersey"
        let remainingFaces = ["_2", "_3", "_4"]
        let available = remainingFaces.filter { UIImage(named: base + $0) != nil }
        if let suffix = available.randomElement() { return base + suffix }
        return base
    }
    
    private func startOneTouchPassingResetPhase() {
        guard isActive else { return }
        
        print("🔵 Starting One-Touch Passing Reset Phase")
        criticalScanPhase = "RESET"
        currentPassDirection = nil
        oneTouchTeammateOnLeft = nil
        oneTouchTeammateImageNameForRound = ""
        
        // Return to wandering phase after reset time
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanResetTime) {
            guard isActive else { return }
            criticalScanPhase = "NORMAL"
            oneTouchTeammateImageNameForRound = oneTouchTeammateImageName()
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            let centerY = screenHeight * 0.5
            teammatePositionX = screenWidth / 2
            teammatePositionY = centerY
            opponentPositionX = screenWidth / 2
            opponentPositionY = centerY
            oneTouchTeammateOnLeft = nil
            startOneTouchWander()
        }
    }
    
    /// Position for "middle behind the center player" (one defender can stay here ~20% of the time).
    private func getScanningGameMiddlePosition() -> CGPoint {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        // Slightly above center (behind the passer)
        return CGPoint(x: screenWidth / 2, y: screenHeight / 2 - 60)
    }
}

// MARK: - Scanning Game Logic Extension
extension DisplayView {
    
    private func startScanningGameSequence() {
        print("🎮 Starting Scanning Game Sequence (wandering phase)")
        scanningGamePhase = "NORMAL"
        generatePlayers()
        scanningGamePositions = initialWanderPositions()
        playersVisible = true
        startScanningGameWander()
    }
    
    /// Random positions in a band away from center for wandering.
    private func initialWanderPositions() -> [UUID: CGPoint] {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let cx = screenWidth / 2
        let cy = screenHeight / 2
        let margin: CGFloat = 80
        var out: [UUID: CGPoint] = [:]
        for p in activePlayers {
            // Random point in annulus / band (avoid center)
            let angle = CGFloat.random(in: 0 ..< .pi * 2)
            let r = CGFloat.random(in: 120 ... 220)
            let x = cx + cos(angle) * r
            let y = cy + sin(angle) * r
            let clampedX = min(max(x, margin), screenWidth - margin)
            let clampedY = min(max(y, margin), screenHeight - margin)
            out[p.id] = CGPoint(x: clampedX, y: clampedY)
        }
        return out
    }
    
    private func startScanningGameWander() {
        scanningGameWanderTimer?.invalidate()
        scanningGameWanderTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard isActive, displayMode == .scanningGame, scanningGamePhase == "NORMAL" else {
                scanningGameWanderTimer?.invalidate()
                scanningGameWanderTimer = nil
                return
            }
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            let margin: CGFloat = 80
            var next = scanningGamePositions
            for p in activePlayers {
                guard var pt = next[p.id] else { continue }
                pt.x += CGFloat.random(in: -18 ... 18)
                pt.y += CGFloat.random(in: -18 ... 18)
                pt.x = min(max(pt.x, margin), screenWidth - margin)
                pt.y = min(max(pt.y, margin), screenHeight - margin)
                next[p.id] = pt
            }
            scanningGamePositions = next
        }
        RunLoop.main.add(scanningGameWanderTimer!, forMode: .common)
    }
    
    private func triggerScanningGameCommit() {
        guard isActive, displayMode == .scanningGame, scanningGamePhase == "NORMAL" || scanningGamePhase == "BEEP" else { return }
        scanningGameWanderTimer?.invalidate()
        scanningGameWanderTimer = nil
        
        let slotTop = getPlayerPosition(for: .top)
        let slotBottom = getPlayerPosition(for: .bottom)
        let slotLeft = getPlayerPosition(for: .left)
        let slotRight = getPlayerPosition(for: .right)
        let middlePos = getScanningGameMiddlePosition()
        let slots: [Direction] = [.top, .bottom, .left, .right]
        let slotPositions: [Direction: CGPoint] = [.top: slotTop, .bottom: slotBottom, .left: slotLeft, .right: slotRight]
        
        var defenders = activePlayers.filter { !$0.isTeammate }
        let teammates = activePlayers.filter { $0.isTeammate }
        defenders.shuffle()
        
        let oneDefenderToMiddle = defenders.count > 0 && Double.random(in: 0..<1) < 0.20
        var slotAssignments: [GamePlayer] = []
        var middlePlayer: GamePlayer?
        if oneDefenderToMiddle {
            middlePlayer = defenders.removeFirst()
        }
        slotAssignments = defenders + teammates
        let shuffledSlots = slots.shuffled()
        
        var targetPositions: [UUID: CGPoint] = [:]
        for (idx, player) in slotAssignments.enumerated() {
            if idx < shuffledSlots.count {
                targetPositions[player.id] = slotPositions[shuffledSlots[idx]]!
            }
        }
        if let mid = middlePlayer {
            targetPositions[mid.id] = middlePos
        }
        
        scanningGamePhase = "SCANNING"
        let scanningDuration = max(criticalScanDuration, 3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + scanningDuration) {
            startScanningGameResetPhase()
        }
        // Unified timing: defenders use Opponent Movement Speed; teammates follow after a short delay (same logic across activities)
        let defenderCommitDuration = Self.dribblePassDefenderCommitScale * (opponentMovementDuration / Self.dribblePassMediumOpponentDuration)
        var defenderTargets = scanningGamePositions
        for p in activePlayers where !p.isTeammate {
            if let pos = targetPositions[p.id] {
                defenderTargets[p.id] = pos
            }
        }
        withAnimation(.easeInOut(duration: defenderCommitDuration)) {
            scanningGamePositions = defenderTargets
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dribblePassTeammateCommitDelay) {
            guard isActive else { return }
            var withTeammates = scanningGamePositions
            for p in activePlayers where p.isTeammate {
                if let pos = targetPositions[p.id] {
                    withTeammates[p.id] = pos
                }
            }
            withAnimation(.easeInOut(duration: Self.dribblePassTeammateCommitDuration)) {
                scanningGamePositions = withTeammates
            }
        }
    }
    
    /// Dribble or Pass: defender commit duration = scale * (opponentMovementDuration / medium baseline).
    private static let dribblePassDefenderCommitScale: Double = 0.25
    private static let dribblePassMediumOpponentDuration: Double = 1.5
    /// Teammates start moving this many seconds after trigger (defenders-first stagger).
    private static let dribblePassTeammateCommitDelay: Double = 0.2
    private static let dribblePassTeammateCommitDuration: Double = 0.3
    
    private func generatePlayers() {
        activePlayers.removeAll()
        
        // All four directions
        let allDirections = Direction.allCases
        
        // Use the configurable team composition settings
        let totalPlayers = numberOfOpponents + numberOfTeammates
        let totalPositions = totalPlayers + numberOfOpenSpaces
        
        // Validate that we have exactly 4 positions
        guard totalPositions == 4 else {
            print("⚠️ Invalid team composition: \(totalPositions) positions (must be 4)")
            return
        }
        
        // Create team assignments based on user settings
        var teamAssignments: [Bool] = []
        
        // Add opponents (false = opponent)
        for _ in 0..<numberOfOpponents {
            teamAssignments.append(false)
        }
        
        // Add teammates (true = teammate)
        for _ in 0..<numberOfTeammates {
            teamAssignments.append(true)
        }
        
        // Shuffle the assignments to randomize positions
        teamAssignments.shuffle()
        
        // Randomly select which directions get players (remaining will be empty)
        let playerDirections = allDirections.shuffled().prefix(totalPlayers)
        
        // Create players
        for (index, direction) in playerDirections.enumerated() {
            let isTeammate = teamAssignments[index]
            let teamColor = isTeammate ? userTeamColor : opponentColor
            
            let player = GamePlayer(
                teamColor: teamColor,
                direction: direction,
                isTeammate: isTeammate,
                gender: playerGender
            )
            
            activePlayers.append(player)
        }
        
        print("🎮 Generated \(activePlayers.count) players: \(numberOfOpponents) opponents, \(numberOfTeammates) teammates, \(numberOfOpenSpaces) open spaces")
    }
    
    private func slideInPlayers() {
        playersVisible = false
        
        // Make players visible immediately
        withAnimation(.easeInOut(duration: 0.8)) {
            playersVisible = true
        }
    }
    
    private func startScanningGameResetPhase() {
        guard isActive else { return }
        
        print("🔵 Starting Scanning Game Reset Phase")
        scanningGamePhase = "RESET"
        playersVisible = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanResetTime) {
            startScanningGameNormalPhase()
        }
    }
    
    private func startScanningGameNormalPhase() {
        guard isActive else { return }
        
        print("⚪ Starting Scanning Game Normal Phase (wandering)")
        scanningGamePhase = "NORMAL"
        generatePlayers()
        scanningGamePositions = initialWanderPositions()
        playersVisible = true
        startScanningGameWander()
    }
    
    // Calculate responsive image size based on device and orientation
    private func getResponsiveImageSize() -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        // More reliable iPad detection using screen size
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        
        // Determine orientation and use appropriate sizing
        let isLandscape = screenWidth > screenHeight
        
        if isIPad {
            // Use orientation-aware sizing for iPads
            if isLandscape {
                // For iPad landscape: Use height to prevent overlap
                return screenHeight * 0.30
            } else {
                // For iPad portrait: Use width for consistent sizing
                return screenWidth * 0.30
            }
        } else {
            if isLandscape {
                // For iPhone landscape: Use smaller dimension (height) to prevent overlap
                return screenHeight * 0.20
            } else {
                // For iPhone portrait: Use moderate size
                return screenWidth * 0.29
            }
        }
    }
    
    private func getPlayerPosition(for direction: Direction) -> CGPoint {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        // Get safe area insets to avoid status bar, notch, and Dynamic Island (iOS 15+ compatible)
        let safeAreaTop: CGFloat
        let safeAreaBottom: CGFloat
        let safeAreaLeft: CGFloat
        let safeAreaRight: CGFloat
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            safeAreaTop = window.safeAreaInsets.top
            safeAreaBottom = window.safeAreaInsets.bottom
            safeAreaLeft = window.safeAreaInsets.left
            safeAreaRight = window.safeAreaInsets.right
        } else {
            safeAreaTop = 0
            safeAreaBottom = 0
            safeAreaLeft = 0
            safeAreaRight = 0
        }
        
        // Calculate responsive image size
        let imageSize = getResponsiveImageSize()
        let halfImageSize = imageSize / 2
        
        // Determine orientation
        let isLandscape = screenWidth > screenHeight
        
        switch direction {
        case .top:
            return CGPoint(x: screenWidth / 2, y: safeAreaTop + halfImageSize + 20) // Top with image fully visible
        case .bottom:
            return CGPoint(x: screenWidth / 2, y: screenHeight - safeAreaBottom - halfImageSize - 20) // Bottom with image fully visible
        case .left:
            if isLandscape {
                // In landscape, account for Dynamic Island on the left
                let leftPosition = max(safeAreaLeft + halfImageSize + 20, halfImageSize + 40)
                return CGPoint(x: leftPosition, y: screenHeight / 2)
            } else {
                return CGPoint(x: halfImageSize + 20, y: screenHeight / 2) // Left with image fully visible
            }
        case .right:
            if isLandscape {
                // In landscape, account for any right-side safe areas
                let rightPosition = min(screenWidth - safeAreaRight - halfImageSize - 20, screenWidth - halfImageSize - 20)
                return CGPoint(x: rightPosition, y: screenHeight / 2)
            } else {
                return CGPoint(x: screenWidth - halfImageSize - 20, y: screenHeight / 2) // Right with image fully visible
            }
        }
    }
}


