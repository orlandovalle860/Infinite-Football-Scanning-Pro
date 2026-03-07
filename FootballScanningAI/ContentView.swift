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
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @State private var isActive = false

    var body: some View {
        if isActive {
            ContentView()
                .environmentObject(multipeerManager)
        } else {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
                    .padding()
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isActive = true
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var profileManager = UserProfileManager()
    @StateObject private var router = AppRouter()
    /// Injected at root so any screen (including navigation destinations) can use @EnvironmentObject.
    @StateObject private var progressStore = ProgressStore()
    @StateObject private var playerStore = PlayerStore()
    @StateObject private var popToRootTrigger = PopToRootTrigger()
    @AppStorage("hasCompletedInitialTest") private var hasCompletedInitialTest = false
    /// When this changes, MainAppView’s navigation stack is recreated so Home/Leave actually pops to root.
    var body: some View {
        Group {
            if profileManager.isProfileCreated {
                MainAppView(profileManager: profileManager, settingsViewModel: settingsViewModel, router: router)
            } else if !hasCompletedInitialTest {
                MainAppView(profileManager: profileManager, settingsViewModel: settingsViewModel, router: router)
            } else {
                ProfileCreationView(profileManager: profileManager)
            }
        }
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
        .navigationViewStyle(.stack)
        .environment(\.sizeCategory, .large)
        .environment(\.colorScheme, .dark)
    }
}

private let coachDeviceShownHomeKey = "coachDeviceShownHome"

struct MainAppView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var router: AppRouter
    @EnvironmentObject private var multipeerManager: MultipeerManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @State private var showsTopToggle: Bool = true
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false
    @AppStorage(coachDeviceShownHomeKey) private var coachDeviceShownHome = false

    @ViewBuilder
    private var rootView: some View {
        Group {
            if hasCompletedInitialTest || coachDeviceShownHome {
                HomeDashboardView(
                    profileManager: profileManager,
                    settingsViewModel: settingsViewModel,
                    showsTopToggle: $showsTopToggle
                )
            } else {
                IntroOnboardingView(
                    settingsViewModel: settingsViewModel,
                    profileManager: profileManager
                )
            }
        }
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
    }

    var body: some View {
        Group {
            NavigationStack(path: router.pathBinding) {
                rootView
                    .navigationDestination(for: AppRoute.self) { route in
                        routeView(for: route)
                    }
            }
        }
        .environmentObject(multipeerManager)
        .environmentObject(progressStore)
        .environmentObject(playerStore)
        .environmentObject(popToRootTrigger)
        .environmentObject(router)
        .onAppear {
            progressStore.load()
            playerStore.load()
            playerStore.createDefaultIfNeeded()
        }
    }

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
        case .twoMinuteCoachRemote:
            TwoMinuteCoachRemoteView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
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
            PlayerDashboardView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .warmup(let mode):
            MainView(settingsViewModel: settingsViewModel, profileManager: profileManager, displayMode: mode)
        case .trainingModeSelection(let activityTitle):
            TrainingModeSelectionView(activityTitle: activityTitle, onSelectMode: { mode in
                router.push(.twoMinuteSetup(mode: mode))
            }) { _ in EmptyView() }
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .twoMinuteSetup(let mode):
            TwoMinuteTestSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .twoMinuteGetReady(let mode, let difficulty):
            TwoMinuteGetReadyView(mode: mode, config: TwoMinuteTestConfig.config(for: difficulty), settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .awayFromPressureRoleSelection:
            AwayFromPressureRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .awayFromPressureTrainingModeSelection:
            TrainingModeSelectionView(activityTitle: "Playing Away From Pressure", onSelectMode: { mode in
                router.push(.awayFromPressureSetup(mode: mode))
            }) { _ in EmptyView() }
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .awayFromPressureSetup(let mode):
            AwayFromPressureSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .dribbleOrPassRoleSelection:
            DribbleOrPassRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .dribbleOrPassTrainingModeSelection:
            TrainingModeSelectionView(activityTitle: "Dribble or Pass", onSelectMode: { mode in
                router.push(.dribbleOrPassSetup(mode: mode))
            }) { _ in EmptyView() }
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .dribbleOrPassSetup(let mode):
            DribbleOrPassSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .oneTouchPassingRoleSelection:
            OneTouchPassingRoleSelectionView(settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .oneTouchPassingTrainingModeSelection:
            TrainingModeSelectionView(activityTitle: "One-Touch Passing", onSelectMode: { mode in
                router.push(.oneTouchPassingSetup(mode: mode))
            }) { _ in EmptyView() }
            .environmentObject(progressStore)
            .environmentObject(playerStore)
            .environmentObject(popToRootTrigger)
            .environmentObject(router)
        case .oneTouchPassingSetup(let mode):
            OneTouchPassingSetupView(mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        case .debugMenu:
            DebugMenuView(profileManager: profileManager, settingsViewModel: settingsViewModel)
                .environmentObject(router)
        }
    }
}

/// SCREEN 1 — INTRO ONBOARDING. Shown when hasCompletedInitialTest == false.
struct IntroOnboardingView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @State private var showHowItWorks = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)
                Text("Do you know what you're going to do before the ball reaches you?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("Elite players do.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                Text("No sign-up. Just start.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("You only need:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("• a ball")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                    Text("• a partner (or a wall)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                Spacer(minLength: 24)
                Button {
                    router.push(.twoMinuteRoleSelection)
                } label: {
                    Text("Start 2-Minute Test")
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
                Button {
                    UserDefaults.standard.set(true, forKey: coachDeviceShownHomeKey)
                } label: {
                    Text("I'm the coach — open Coach Remote")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 8)
                Spacer(minLength: 32)
                Button {
                    showHowItWorks = true
                } label: {
                    Text("How it works")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                Spacer(minLength: 48)
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
        .sheet(isPresented: $showHowItWorks) {
            HowItWorksView()
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
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @State private var showHowItWorks = false
    @State private var showStatusUpgrade = false
    @State private var upgradedStatus: PlayerStatus?
    @State private var showPlayersSheet = false
    @AppStorage(hasSeenPlayerSwitcherTooltipKey) private var hasSeenPlayerSwitcherTooltip = false
    // Programmatic navigation so buttons reliably push (NavigationLink in ScrollView can miss taps).
    @State private var isStartTrainingPressed = false
    @State private var warmupDisplayMode: DisplayMode = .colors
    @State private var snapshotMetricInfoToShow: (title: String, message: String)?

    private var playerId: UUID? { playerStore.selectedPlayerId }
    private var last5: [SessionRecord] { progressStore.last5TrainingBlocks(playerId: playerId) }
    private var consistencyLabel: ConsistencyLabel { DashboardConsistency.label(from: last5) }
    private var decisionScore: Int { DashboardDecisionScore.score(from: last5) }
    private var status: PlayerStatus { DashboardDecisionScore.status(score: decisionScore, consistencyLabel: consistencyLabel) }
    private var dailyCompleted: Int { DailyTargetState.completedBlocksToday(playerId: playerId) }
    private var dailyTarget: Int { DailyTargetState.targetBlocksPerDay }
    private var hasAnyBlock: Bool { !last5.isEmpty }
    private var trainingStreakDays: Int { profileManager.trainingStreakDays() }
    private var streakLabel: String {
        let count = trainingStreakDays
        let dayWord = (count == 0 || count == 1) ? "Day" : "Days"
        return "🔥 \(count) \(dayWord) Training Streak"
    }
    @AppStorage(hasCompletedInitialTestKey) private var hasCompletedInitialTest = false

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

    /// Trend for decision speed: "↑ Faster" if recent avg < older avg.
    private var snapshotDecisionSpeedTrend: String {
        let times = recentSessionsForSnapshot.compactMap { $0.avgDecisionTime }
        guard times.count >= 2 else { return "" }
        let recent = times.prefix(2)
        let newer = recent.first!, older = recent.dropFirst().first!
        return newer < older ? "↑ Faster" : ""
    }

    /// First touch accuracy % from most recent session that has firstTouchMatchCount. Nil if none.
    private var snapshotFirstTouchPercent: Int? {
        guard let s = recentSessionsForSnapshot.first(where: { $0.firstTouchMatchCount != nil && $0.totalReps > 0 }) else { return nil }
        return Int(round(Double(s.firstTouchMatchCount!) / Double(s.totalReps) * 100))
    }

    /// Trend for first touch: "↑ Improving" if we have 2+ sessions with data and latest > previous.
    private var snapshotFirstTouchTrend: String {
        let withData = recentSessionsForSnapshot.filter { $0.firstTouchMatchCount != nil && $0.totalReps > 0 }
        guard withData.count >= 2 else { return "" }
        let pct1 = Double(withData[0].firstTouchMatchCount!) / Double(withData[0].totalReps) * 100
        let pct0 = Double(withData[1].firstTouchMatchCount!) / Double(withData[1].totalReps) * 100
        return pct1 > pct0 ? "↑ Improving" : ""
    }

    /// Trend for correct decisions from consistency label.
    private var snapshotCorrectTrend: String {
        switch consistencyLabel {
        case .steady: return "↑ Stable"
        case .improving: return "↑ Improving"
        case .streaky: return "↑ Variable"
        }
    }
    /// Automatic recommendation by player level with overrides for timing, bias, consistency. Updates when level/timing/bias/consistency change.
    private var trainingRecommendation: TrainingRecommendationResult {
        TrainingRecommendation.recommend(progressStore: progressStore, playerId: playerId, last5: last5, hasCompletedInitialTest: hasCompletedInitialTest, lastAFPSessionResult: lastAFPSessionResult)
    }

    /// Pinned row never promotes "Take Test" after the initial test; 2-Minute Test remains in the scroll.
    private var pinnedActivity: ActivityKind { trainingRecommendation.activity }

    /// Activity shown in the yellow card. Never 2-Minute Test; when recommendation is test, show first training activity so the card is always visible.
    private var continueTrainingCardActivity: ActivityKind {
        if pinnedActivity == .twoMinuteTest { return .awayFromPressure }
        return pinnedActivity
    }

    /// Route for the first screen of this activity’s flow (role selection). Train Now uses this so the whole flow stays on the path-based stack.
    private func routeForTrainNowActivity(_ activity: ActivityKind) -> AppRoute {
        switch activity {
        case .twoMinuteTest: return .twoMinuteRoleSelection
        case .awayFromPressure: return .awayFromPressureRoleSelection
        case .dribbleOrPass: return .dribbleOrPassRoleSelection
        case .oneTouchPassing: return .oneTouchPassingRoleSelection
        }
    }

    /// Focus line for pinned Train Now card (from recommendation engine).
    private var focusText: String { trainingRecommendation.focusLine }
    private var coachTipText: String { trainingRecommendation.coachTip }

    /// Stage position for Next Training card (perception path order: AFP=1, DOP=2, OTP=3).
    private var nextTrainingStageLabel: String {
        switch continueTrainingCardActivity {
        case .awayFromPressure: return "Stage 1 of 3"
        case .dribbleOrPass: return "Stage 2 of 3"
        case .oneTouchPassing: return "Stage 3 of 3"
        case .twoMinuteTest: return "Stage 1 of 3"
        }
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
            continueTrainingPinnedCard
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .background(Rectangle().fill(.black.opacity(0.4)))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    Color.clear.frame(height: 12)

                    playerSnapshotCard
                        .modifier(StartPageCardStyle())

                    curriculumPreviewCard
                        .modifier(StartPageCardStyle())

                    twoMinuteTestCard
                        .modifier(StartPageCardStyle())

                    progressCard
                        .modifier(StartPageCardStyle())

                    scanWarmupsCard
                        .modifier(StartPageCardStyle())

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AppConfig.testerMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Tester Tools") {
                        router.push(.debugMenu)
                    }
                    .foregroundColor(.white.opacity(0.9))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        hasSeenPlayerSwitcherTooltip = true
                        showPlayersSheet = true
                    } label: {
                        Label("Switch Player", systemImage: "person.circle")
                    }
                    Button {
                        router.push(.coachRemote)
                    } label: {
                        Label("Coach Remote", systemImage: "hand.raised")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Coach & Player")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white.opacity(0.95))
                }
                .accessibilityLabel("Coach and Player options")
                .accessibilityHint("Double tap for Coach Remote and Switch Player.")
            }
        }
        .overlay(alignment: .topTrailing) {
            if !hasSeenPlayerSwitcherTooltip {
                Text("Tap here to switch players.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                    .padding(.top, 56)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
            }
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
        }
        .sheet(isPresented: $showHowItWorks) { HowItWorksView() }
        .overlay {
            if showStatusUpgrade, let s = upgradedStatus {
                statusUpgradeToast(status: s)
            }
        }
        .onAppear {
            showsTopToggle = false
            checkStatusUpgrade()
            popToRootTrigger.request = false
        }
        .onDisappear { showsTopToggle = true }
    }

    private var playerSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Snapshot")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            if last5.count >= 2 {
                snapshotMetricRow(label: "Decision Speed", value: snapshotDecisionSpeedSeconds.map { String(format: "%.2fs", $0) } ?? "—", trend: snapshotDecisionSpeedTrend)
                snapshotMetricRow(label: "First Touch Accuracy", value: snapshotFirstTouchPercent.map { "\($0)%" } ?? "—", trend: snapshotFirstTouchTrend)
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
                Text(streakLabel)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Text(trainingStreakDays == 0 ? "Keep it going today" : "Keep it alive today")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
    }

    private func snapshotMetricRow(label: String, value: String, trend: String) -> some View {
        HStack {
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

    /// Pinned at top: current training session card (recommendation + today's goal + Start Training).
    private var continueTrainingPinnedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT TRAINING")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.black.opacity(0.7))
                    Text(nextTrainingStageLabel)
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.7))
                }

                Text(RecommendationEngine.activityTitle(continueTrainingCardActivity))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Focus: \(focusText)")
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text("Coach Tip: \(coachTipText)")
                    .font(.footnote)
                    .foregroundColor(.black.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(.top, 8)

                Text("Today's Goal")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.black.opacity(0.7))
                    .padding(.top, 2)

                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.15))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.5))
                            .frame(width: max(0, g.size.width * CGFloat(min(dailyCompleted, dailyTarget)) / CGFloat(max(1, dailyTarget))), height: 10)
                    }
                }
                .frame(height: 10)

                Text("\(min(dailyCompleted, dailyTarget)) / \(dailyTarget) blocks complete")
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.8))
                Text(todayGoalEncouragement)
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.7))
                    .padding(.top, 2)

                Button {
                    isStartTrainingPressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        isStartTrainingPressed = false
                        router.push(routeForTrainNowActivity(continueTrainingCardActivity))
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Start Training")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isStartTrainingPressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isStartTrainingPressed)
                .accessibilityLabel("Start training. \(RecommendationEngine.activityTitle(continueTrainingCardActivity)). Focus: \(focusText). Coach Tip: \(coachTipText).")
                .accessibilityHint("Double tap to start training.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.yellow)
        .cornerRadius(16)
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

    private var personalBestsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Personal Bests")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            let bests = profileManager.currentProfile?.personalBests ?? [:]
            if bests.isEmpty {
                Text("Complete a block or test to set your first best.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                personalBestRow("Playing Away From Pressure", best: bests[.awayFromPressure])
                personalBestRow("Dribble or Pass", best: bests[.dribbleOrPass])
                personalBestRow("One-Touch Passing", best: bests[.oneTouchPassing])
                personalBestRow("2-Minute Test", best: bests[.twoMinuteTest])
            }
        }
    }

    private func personalBestRow(_ title: String, best: ActivityBest?) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            if let b = best {
                Text("Best: \(b.bestCorrect) / \(b.bestTotal)")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.yellow.opacity(0.95))
            } else {
                Text("—")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
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
            warmupDisplayMode = mode
            router.push(.warmup(warmupDisplayMode))
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
            Text("2-Minute Test")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Benchmark your decision speed.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
            Button {
                router.push(.twoMinuteRoleSelection)
            } label: {
                Text("Run Test")
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
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            Text("2-Minute Test")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text("Use this device as:")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal)

            Text("Choose one. The other device should choose the other role.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(spacing: 16) {
                Button {
                    router.push(.trainingModeSelection(activityTitle: "2-Minute Test"))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "tv")
                            Text("Display")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        Text("This device shows the grid and star. Place it behind the player.")
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
                    router.push(.twoMinuteCoachRemote)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "hand.raised")
                            Text("Coach remote")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        Text("This device starts each rep and logs exit direction. Tap Connect to Display first.")
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
    @AppStorage("hasSeenTwoMinuteOnboarding") private var hasSeenTwoMinuteOnboarding = false
    @State private var showOnboarding = false
    @State private var difficulty: TestDifficulty = TestDifficulty.loadFromUserDefaults()

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
                Text("• Player stays inside the square.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                if mode == .partner {
                    Text("• Coach stands 5–7 yards in front with the ball.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.top, 4)

            Text("Difficulty")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 12)
            Picker("Difficulty", selection: $difficulty) {
                Text("Beginner").tag(TestDifficulty.beginner)
                Text("Standard").tag(TestDifficulty.standard)
                Text("Advanced").tag(TestDifficulty.advanced)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 28)
            .onChange(of: difficulty) { _, newValue in
                newValue.saveToUserDefaults()
            }

            Spacer(minLength: 8)

            Button {
                router.push(.twoMinuteGetReady(mode: mode, difficulty: difficulty))
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear {
            if !hasSeenTwoMinuteOnboarding { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            TwoMinuteOnboardingView {
                hasSeenTwoMinuteOnboarding = true
                showOnboarding = false
            }
        }
    }
}

struct TwoMinuteGetReadyView: View {
    let mode: TrainingMode
    let config: TwoMinuteTestConfig
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showLeaveAlert = false
    @State private var countdown: Int? = nil
    @State private var countdownTimer: Timer?
    @State private var showInstruction = false
    @State private var navigateToTest = false
    /// Prevents startCountdown from running again when we pop back from the instruction screen (so "Start" goes to session, not back to instructions).
    @State private var countdownHasStarted = false

    private var isPartner: Bool { mode == .partner }
    private var activity: ActivityKind { .twoMinuteTest }

    var body: some View {
        VStack(spacing: 24) {
            if let n = countdown, n > 0 {
                Text("\(n)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            } else if countdown == 0 {
                Text("Go")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
                Spacer()
            } else {
                Spacer(minLength: 20)
                Text("Get ready")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Player instructions (the whole time):")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.95))
                    Text("• Keep moving inside the square.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Text("• Check both shoulders often.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Text("• When you receive, your first touch must take you out through the correct side.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    Text("Don't stand still — shuffle, open your hips, check shoulders.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.75))
                        .italic()
                }
                .padding(.horizontal, 28)
                .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 16) {
                    if isPartner {
                        Text("Passer: hold the phone. When the screen says ready, play the pass and tap PASS (or press volume) when the ball leaves your foot.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    } else if mode == .solo {
                        Text("Trigger each rep with a screen tap or volume button. Tap your exit direction after each rep.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text("Trigger each rep with the volume button when the ball bounces back. Tap your exit direction after each rep.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .multilineTextAlignment(.leading)

                Spacer()
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
        .navigationDestination(isPresented: $showInstruction) {
            ActivityInstructionView(activity: activity) {
                showInstruction = false
                navigateToTest = true
            }
        }
        .navigationDestination(isPresented: $navigateToTest) {
            TwoMinuteCriticalScanSessionView(config: config, mode: mode, settingsViewModel: settingsViewModel, profileManager: profileManager)
                .environmentObject(progressStore)
                .environmentObject(playerStore)
                .environmentObject(popToRootTrigger)
                .environmentObject(router)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLeaveAlert = true
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .alert("Leave training?", isPresented: $showLeaveAlert) {
            Button("Stay", role: .cancel) {}
            Button("Leave", role: .destructive) {
                router.popToRoot()
            }
        } message: {
            Text("Your current block will not be saved.")
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
            guard !countdownHasStarted else { return }
            countdownHasStarted = true
            startCountdown()
        }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = 3
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                guard let n = countdown else { timer.invalidate(); return }
                if n <= 1 {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                    countdown = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if ActivityInstructionContent.shouldShowInstructions(for: activity) {
                            showInstruction = true
                        } else {
                            navigateToTest = true
                        }
                    }
                } else {
                    countdown = n - 1
                }
            }
        }
    }
}

/// Simple explanation sheet for "How it works" link.
private struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("It's about when you decide, not how you touch. Know your first touch before the ball reaches you.")
                        .foregroundColor(.primary)

                    Text("Use the training activities to practice scanning and deciding early.")
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

struct MainView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    
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
    
    init(settingsViewModel: SettingsViewModel, profileManager: UserProfileManager, selectedColors: [Color] = [], displayMode: DisplayMode = .colors, changeInterval: Double = 1.5, selectedNumbers: Set<Int> = []) {
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        self.selectedColors = selectedColors
        self.displayMode = displayMode
        self.changeInterval = changeInterval
        self.selectedNumbers = selectedNumbers
        _currentColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
        _currentNumberColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
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
                        
                        // Mode Selection
                        ScanningActivitiesSectionView(
                            displayMode: $displayMode,
                            selectedNumbers: $selectedNumbers,
                            selectedLanes: $selectedLanes,
                            selectedColors: $selectedColors,
                            selectedBeepInterval: $selectedBeepInterval
                        )
                            
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
                .navigationTitle("Select Your Options")
                .navigationBarTitleDisplayMode(.large)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.clear, for: .navigationBar)
                .foregroundColor(.white)
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
    @State private var pressureResponseNoPressEndWorkItem: DispatchWorkItem?
    
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
                multipeerManager.startAdvertising()
            }
            startCountdown()
        }
        .onDisappear {
            multipeerManager.stopAdvertising()
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
        guard let soundURL = Bundle.main.url(forResource: "short-beep-351721", withExtension: "mp3") else {
            print("Could not find sound file")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.prepareToPlay()
        } catch {
            print("Could not create audio player: \(error)")
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: changeInterval, repeats: true) { _ in
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
            
            // Play beep
            if soundEnabled {
                audioPlayer?.play()
            }
            
            // Show number or arrow for specific modes
            if displayMode == .colorsNumbers {
                if let randomNumber = selectedNumbers.randomElement() {
                    currentNumber = randomNumber
                }
                showNumberOrArrow = true
                
                // Hide after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showNumberOrArrow = false
                }
            } else if displayMode == .colorsArrows {
                currentArrowDirection = selectedArrows.randomElement() ?? "arrow.up"
                showNumberOrArrow = true
                
                // Hide after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
    
    private func scheduleRandomBeep() {
        guard soundEnabled && isActive else { return }
        
        // Don't schedule beeps for Critical Scan modes or modes with their own beep timer
        guard displayMode != .fourGoalGame && displayMode != .colors && displayMode != .colorsNumbers && displayMode != .colorsArrows && displayMode != .numbers && displayMode != .lanes else { return }
        
        let randomInterval = Double.random(in: 10...15)
        DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
            if soundEnabled && isActive && displayMode != .fourGoalGame && displayMode != .colors && displayMode != .colorsNumbers && displayMode != .colorsArrows && displayMode != .numbers && displayMode != .lanes {
                audioPlayer?.play()
                scheduleRandomBeep() // Schedule next beep
            }
        }
    }
    
    private func stopTimer() {
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
        guard let soundURL = Bundle.main.url(forResource: "critical scan beep", withExtension: "wav") else {
            print("Could not find critical scan sound file")
            return
        }
        do {
            criticalScanAudioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            criticalScanAudioPlayer?.play()
        } catch {
            print("Could not create critical scan audio player: \(error)")
        }
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
        pressureResponseNoPressEndWorkItem?.cancel()

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
            let work = DispatchWorkItem { [self] in
                guard isActive else { return }
                startPressureResponseResetPhase()
            }
            pressureResponseNoPressEndWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
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
        pressureResponseNoPressEndWorkItem?.cancel()
        pressureResponseNoPressEndWorkItem = nil
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


