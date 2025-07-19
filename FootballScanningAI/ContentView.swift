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
    @State private var isActive = false
    
    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                Image("SplashLogo") // Change this to match your renamed image set
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
    
    var body: some View {
        Group {
            if profileManager.isProfileCreated {
                // User has profiles - show main app with tabs
                MainAppView(profileManager: profileManager, settingsViewModel: settingsViewModel)
            } else {
                // No profiles - show profile creation
                ProfileCreationView(profileManager: profileManager)
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.sizeCategory, .large) // Force consistent sizing
        .environment(\.colorScheme, .dark) // Force dark mode for consistency
    }
}

struct MainAppView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Training Tab
            NavigationStack {
                IntroView(profileManager: profileManager, settingsViewModel: settingsViewModel)
            }
            .tabItem {
                Image(systemName: "figure.soccer")
                Text("Training")
            }
            .tag(0)
            
            // Profile Tab
            ProfileView(profileManager: profileManager)
            .tabItem {
                Image(systemName: "person.circle")
                Text("Profile")
            }
            .tag(1)
        }
        .accentColor(.blue)
    }
}

struct IntroView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @State private var navigateToMain = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                Text("Infinite Football Scanning Pro")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    
                    if profileManager.hasMultipleProfiles(), let currentProfile = profileManager.currentProfile {
                        Text("Training as: \(currentProfile.name)")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(20)
                    }
                }
                    .padding(.top, 40)
                
                // What is Scanning Section
                VStack(alignment: .leading, spacing: 15) {
                    Text("What is Scanning?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Scanning is the crucial skill of constantly checking your surroundings during a game. It's like having eyes in the back of your head - you're always aware of where your teammates, opponents, and the ball are.")
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(4)
                }
                .padding()
                .frame(maxWidth: 800)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                
                // Why Scan Section
                VStack(alignment: .leading, spacing: 15) {
                    Text("Why Should You Scan?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        BenefitRow(icon: "eye.fill", text: "Better Decision Making")
                        BenefitRow(icon: "brain.head.profile", text: "Improved Spatial Awareness")
                        BenefitRow(icon: "figure.soccer", text: "Enhanced Game Intelligence")
                        BenefitRow(icon: "bolt.fill", text: "Faster Decision Making")
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                
                // Two Types of Scanning Training
                VStack(alignment: .leading, spacing: 15) {
                    Text("Two Types of Scanning Training")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Normal Scanning Modes
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "eye.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            
                            Text("Normal Scanning Modes")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        Text("Build your foundation with continuous scanning practice. Develop the habit of constantly checking your surroundings and recognizing visual cues.")
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            BenefitRow(icon: "arrow.clockwise", text: "Continuous awareness building")
                            BenefitRow(icon: "eye", text: "Visual recognition training")
                            BenefitRow(icon: "waveform.path", text: "Pattern recognition")
                            BenefitRow(icon: "brain.head.profile", text: "Foundation scanning skills")
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Critical Scanning Modes
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                            
                            Text("Critical Scanning Modes")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        Text("Master decision-making under pressure. Train in high-stakes scenarios where you must scan, decide, and execute actions in split seconds.")
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            BenefitRow(icon: "brain.head.profile", text: "Decision-making under pressure")
                            BenefitRow(icon: "bolt.fill", text: "Action execution training")
                            BenefitRow(icon: "figure.soccer", text: "Game simulation scenarios")
                            BenefitRow(icon: "star.fill", text: "Advanced scanning mastery")
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                
                // Pro Examples
                VStack(alignment: .leading, spacing: 15) {
                    Text("Pro Players Who Mastered Scanning")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Xavi Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Xavi")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Known for his constant scanning, Xavi could make 360° turns while receiving the ball, always knowing where his teammates were.")
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                        
                        Link(destination: URL(string: "https://www.youtube.com/watch?v=CNQGMukcsWQ")!) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Watch Example")
                            }
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Ødegaard Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Martin Ødegaard")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Ødegaard's exceptional scanning ability allows him to create space and find passing lanes even in tight situations, making him one of the most creative midfielders in the game.")
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                        
                        Link(destination: URL(string: "https://www.youtube.com/shorts/TdP7hr4-k_g")!) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Watch Example")
                            }
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    
                    // De Bruyne Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kevin De Bruyne")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("De Bruyne's scanning skills enable him to execute perfect through balls and crosses, often without even looking at his target.")
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                        
                        Link(destination: URL(string: "https://www.youtube.com/watch?v=8j8BxM0ZqXY")!) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Watch Example")
                            }
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                
                // Start Training Button
                NavigationLink(destination: MainView(settingsViewModel: settingsViewModel, profileManager: profileManager)) {
                    HStack {
                        Image(systemName: "figure.soccer")
                        if profileManager.hasMultipleProfiles(), let currentProfile = profileManager.currentProfile {
                            Text("Start Training - \(currentProfile.name)")
                        } else {
                            Text("Start Training")
                        }
                    }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                    .background(Color.blue)
                    .cornerRadius(15)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 40)
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
    @State private var numberRange: Double = 2.0 // 1-2 range for Colors + Numbers mode
    @State private var selectedArrows: Set<String> = [] // Selected arrows for Colors + Arrows mode
    @State private var selectedBeepInterval: BeepInterval = .medium // Default to medium
    // Critical scan settings now managed by ViewModel
    @State private var selectedColorSet: ScanningColorSet = .standard // Default to standard colors
    @State private var selectedActionSet: ActionSet = .basic // Default to basic actions
    // Custom actions now managed by SettingsViewModel
    @State private var showingCustomActionSheet = false
    @State private var editingActionNumber: Int = 1
    @State private var showingActionList = false
    @State private var selectedActionForNumber: Int = 1
    @State private var selectedCriticalScanNumbers: Set<Int> = [1] // Default to only number 1
    
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
    
    // Critical Scan state variables
    @State private var criticalScanPhase: String = "NORMAL"
    @State private var currentActionNumber: Int = 1
    @State private var criticalScanTimer: Timer?
    
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
                criticalScanDelay: settingsViewModel.criticalScanDelay,
                criticalScanDuration: settingsViewModel.criticalScanDuration,
                criticalScanResetTime: settingsViewModel.criticalScanResetTime,
                selectedColorSet: selectedColorSet,
                selectedActionSet: selectedActionSet,
                customActions: settingsViewModel.customActions,
                selectedCriticalScanNumbers: Array(selectedCriticalScanNumbers).sorted(),
                screenProtectionEnabled: settingsViewModel.screenProtectionEnabled,
                numberColor: numberColor,
                arrowColor: arrowColor,
                userTeamColor: selectedUserTeamColor,
                opponentColor: selectedOpponentColor,
                playerGender: selectedPlayerGender,
                numberOfOpponents: numberOfOpponents,
                numberOfTeammates: numberOfTeammates,
                numberOfOpenSpaces: numberOfOpenSpaces,
                showDisplay: $showDisplay,
                profileManager: profileManager
            )
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
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
                        
                            // Mode Selection
                            VStack(alignment: .leading, spacing: 10) {
                            Text("Scanning Activities")
                                    .font(.headline)
                        .foregroundColor(.white)
                                    .environment(\.sizeCategory, .large) // Force consistent size
                                
                            // Normal Scan Activities
                                VStack(alignment: .leading, spacing: 8) {
                                 Text("Normal Scan Activities")
                                     .font(.subheadline)
                                     .foregroundColor(.white.opacity(0.8))
                                     .padding(.horizontal, 4)
                                     .environment(\.sizeCategory, .large) // Force consistent size
                                
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                        Button(action: {
                                            displayMode = .colors
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedBeepInterval = .medium
                                            // Keep selectedColors and selectedArrows for session persistence
                                        }) {
                                            Text("Colors")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(displayMode == .colors ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 6)
                                                .frame(maxWidth: .infinity)
                                                .environment(\.sizeCategory, .large) // Force consistent size
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .colors, color: .blue))
                                        
                                        Button(action: {
                                            displayMode = .numbers
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedBeepInterval = .medium
                                            // Keep selectedColors and selectedArrows for session persistence
                                        }) {
                                            Text("Numbers")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(displayMode == .numbers ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 4)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .numbers, color: .blue))
                                        
                                        Button(action: {
                                            displayMode = .lanes
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedColors.removeAll()
                                            selectedBeepInterval = .medium
                                            // Keep selectedArrows for session persistence, but clear colors for independent lane selection
                                        }) {
                                            Text("Lanes")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(displayMode == .lanes ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 6)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .lanes, color: .blue))
                                    }
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                        Button(action: {
                                            displayMode = .colorsArrows
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedBeepInterval = .medium
                                            // Keep selectedArrows for shared arrow selection between arrow activities
                                        }) {
                                            Text("Colors + Arrows")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(displayMode == .colorsArrows ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 4)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .colorsArrows, color: .blue))
                                        
                                        Button(action: {
                                            displayMode = .colorsNumbers
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedBeepInterval = .medium
                                            // Keep selectedColors and selectedArrows for session persistence
                                        }) {
                                            Text("Colors + Numbers")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(displayMode == .colorsNumbers ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 4)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .colorsNumbers, color: .blue))
                                    }
                                
                                
                                // Critical Scan Modes
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Critical Scan Activities")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 4)
                                        .environment(\.sizeCategory, .large) // Force consistent size
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                        Button(action: {
                                            displayMode = .criticalScan
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedBeepInterval = .medium
                                            // Keep selectedArrows for session persistence
                                        }) {
                                            Text("Critical Scan Numbers")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(displayMode == .criticalScan ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 8)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .criticalScan, color: .red))
                                        
                                        Button(action: {
                                            displayMode = .criticalScanArrows
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedBeepInterval = .medium
                                            // Keep selectedArrows for shared arrow selection between arrow activities
                                        }) {
                                            Text("Critical Scan Arrows")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(displayMode == .criticalScanArrows ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 8)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .criticalScanArrows, color: .red))
                                    }
                                    
                                    // Scanning Game Mode
                                    Button(action: {
                                        displayMode = .scanningGame
                                        selectedNumbers.removeAll()
                                        selectedLanes.removeAll()
                                        selectedBeepInterval = .medium
                                    }) {
                                        Text("Dribble or Pass")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(displayMode == .scanningGame ? .white : .white.opacity(0.7))
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 8)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .scanningGame, color: .green))
                                }
                            }
                                .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.7)
                            }
                            .padding(.horizontal)
                            .environment(\.sizeCategory, .large) // Force consistent sizing across devices
                            
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
                            
                            // Number Color Selection (for modes that use numbers)
                            if displayMode == .numbers || displayMode == .colorsNumbers || displayMode == .criticalScan {
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
                            if displayMode == .colorsArrows || displayMode == .criticalScanArrows {
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
                            
                            // Beep Interval Selection (for Colors, Colors + Numbers, Colors + Arrows, Numbers, Lanes, Critical Scan modes, and Scanning Game)
                            if displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .numbers || displayMode == .lanes || displayMode == .criticalScan || displayMode == .criticalScanArrows || displayMode == .scanningGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Beep Interval")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Controls how often beep sounds occur during training to signal actions")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                    
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
                            if displayMode != .criticalScan && displayMode != .criticalScanArrows && displayMode != .scanningGame {
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
                            
                            // Scanning Circle Time Interval (only for Critical Scan modes and Scanning Game)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows || displayMode == .scanningGame {
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
                            
                            // Critical Scan Delay Slider (only for Critical Scan mode and Scanning Game)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows || displayMode == .scanningGame {
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
                            
                            // Critical Scan Duration Slider (only for Critical Scan mode and Scanning Game)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows || displayMode == .scanningGame {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Critical Scan Duration: \(String(format: "%.1f", settingsViewModel.criticalScanDuration))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("How long the red screen and the action stay visible on screen during the critical scan")
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
                            
                            // Critical Scan Reset Time Slider (only for Critical Scan mode and Scanning Game)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows || displayMode == .scanningGame {
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
                            
                            // Scanning Circle Colors (only for Critical Scan mode and Scanning Game)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows || displayMode == .scanningGame {
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
                            
                            // Number Selection (only for Critical Scan mode)
                            if displayMode == .criticalScan {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Numbers (1-8)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                                        ForEach(1...8, id: \.self) { number in
                                            Button(action: {
                                                if selectedCriticalScanNumbers.contains(number) {
                                                    selectedCriticalScanNumbers.remove(number)
                                                } else {
                                                    selectedCriticalScanNumbers.insert(number)
                                                }
                                            }) {
                                                Text("\(number)")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 40, height: 40)
                                            }
                                            .buttonStyle(SquareButtonStyle(isSelected: selectedCriticalScanNumbers.contains(number), color: .blue))
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
                            
                            // Arrow Selection (only for Critical Scan Arrows mode)
                            if displayMode == .criticalScanArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Select Arrows")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
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
                            
                            // Custom Actions (only for Critical Scan mode)
                            if displayMode == .criticalScan {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Number Actions (\(selectedCriticalScanNumbers.count) selected)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    VStack(spacing: 8) {
                                        ForEach(settingsViewModel.customActions.filter { selectedCriticalScanNumbers.contains($0.number) }, id: \.number) { customAction in
                                            Button(action: {
                                                selectedActionForNumber = customAction.number
                                                showingActionList = true
                                            }) {
                                                HStack {
                                                    Text("\(customAction.number)")
                                                        .font(.system(size: 18, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .frame(width: 30)
                                                    
                                                    Text(customAction.action)
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.white.opacity(0.9))
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)
                                                    
                                                    Spacer()
                                                    
                                                    Image(systemName: "chevron.right")
                                                        .foregroundColor(.blue)
                                                        .font(.system(size: 14))
                                                }
                                                .padding(.vertical, 8)
                                                .padding(.horizontal, 12)
                                            }
                                            .buttonStyle(ActionButtonStyle())
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
                            
                            // Scanning Game Controls (only for Scanning Game mode)
                            if displayMode == .scanningGame {
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
        case .criticalScan:
            // Critical scan numbers mode works with default values
            return true
        case .criticalScanArrows:
            // Require at least one arrow direction
            return !selectedArrows.isEmpty
        case .scanningGame:
            // Require different team colors and valid team composition
            let totalPositions = numberOfOpponents + numberOfTeammates + numberOfOpenSpaces
            return selectedUserTeamColor != selectedOpponentColor && totalPositions == 4
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
        case .criticalScan:
            return "" // Critical scan numbers mode works with defaults
        case .criticalScanArrows:
            if selectedArrows.isEmpty {
                return "Please select at least one arrow direction"
            }
        case .scanningGame:
            if selectedUserTeamColor == selectedOpponentColor {
                return "Please select different colors for your team and opponent"
            }
            let totalPositions = numberOfOpponents + numberOfTeammates + numberOfOpenSpaces
            if totalPositions != 4 {
                return "Team composition must equal exactly 4 positions (currently \(totalPositions))"
            }
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
    let criticalScanDelay: Double
    let criticalScanDuration: Double
        let criticalScanResetTime: Double
    let selectedColorSet: ScanningColorSet
        let selectedActionSet: ActionSet
    let customActions: [CustomAction]
    let selectedCriticalScanNumbers: [Int]
        let screenProtectionEnabled: Bool
        let numberColor: Color
        let arrowColor: Color
    let userTeamColor: TeamColor
    let opponentColor: TeamColor
    let playerGender: PlayerGender
    let numberOfOpponents: Int
    let numberOfTeammates: Int
    let numberOfOpenSpaces: Int
        @Binding var showDisplay: Bool
        @ObservedObject var profileManager: UserProfileManager
    
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
    @State private var currentActionNumber: Int = 1
    @State private var criticalScanTimer: Timer?
    
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
    @State private var scanningGamePhase: String = "NORMAL"
    @State private var activePlayers: [GamePlayer] = []
    @State private var playersVisible: Bool = false
    @State private var scanningGameTimer: Timer?
    

    
    let availableLanes = ["Left", "Center", "Right"]
    
        init(selectedColors: [Color], displayMode: DisplayMode, changeInterval: Double, selectedNumbers: [Int], soundEnabled: Bool, laneSpeed: Double, numberRange: Double, selectedArrows: [String], selectedBeepInterval: BeepInterval, criticalScanDelay: Double, criticalScanDuration: Double, criticalScanResetTime: Double, selectedColorSet: ScanningColorSet, selectedActionSet: ActionSet, customActions: [CustomAction], selectedCriticalScanNumbers: [Int], screenProtectionEnabled: Bool, numberColor: Color, arrowColor: Color, userTeamColor: TeamColor, opponentColor: TeamColor, playerGender: PlayerGender, numberOfOpponents: Int, numberOfTeammates: Int, numberOfOpenSpaces: Int, showDisplay: Binding<Bool>, profileManager: UserProfileManager) {
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
        self.criticalScanDelay = criticalScanDelay
        self.criticalScanDuration = criticalScanDuration
            self.criticalScanResetTime = criticalScanResetTime
        self.selectedColorSet = selectedColorSet
            self.selectedActionSet = selectedActionSet
        self.customActions = customActions
        self.selectedCriticalScanNumbers = selectedCriticalScanNumbers
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
                } else if displayMode == .criticalScan {
                    // Critical Scan display
                    ZStack {
                        // Background color based on phase
                        if criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" {
                            Color.black
                                .ignoresSafeArea()
                        } else if criticalScanPhase == "CRITICAL" {
                            Color.red
                                .ignoresSafeArea()
                        } else if criticalScanPhase == "RESET" {
                            Color.blue
                                .ignoresSafeArea()
                        } else {
                            Color.black
                                .ignoresSafeArea()
                        }
                        
                        VStack(spacing: 20) {
                            if criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" {
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
                                    
                                    Text("SCAN & IDENTIFY")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                }
                            } else if criticalScanPhase == "CRITICAL" {
                                VStack(spacing: 15) {
                                    Text("\(currentActionNumber)")
                                            .font(.system(size: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.4, weight: .bold))
                                            .foregroundColor(numberColor)
                                        .shadow(radius: 10)
                                    
                                    Text("CRITICAL SCAN")
                                        .font(.system(size: 50, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                    
                                    Text(customActions.first { $0.number == currentActionNumber }?.action ?? "")
                                            .font(.system(size: 60, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            } else if criticalScanPhase == "RESET" {
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
                } else if displayMode == .criticalScanArrows {
                    // Critical Scan Arrows display
                    ZStack {
                        // Background color based on phase
                        if criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" {
                            Color.black
                                .ignoresSafeArea()
                        } else if criticalScanPhase == "CRITICAL" {
                            Color.red
                                .ignoresSafeArea()
                        } else if criticalScanPhase == "RESET" {
                            Color.blue
                                .ignoresSafeArea()
                        } else {
                            Color.black
                                .ignoresSafeArea()
                        }
                        
                        VStack(spacing: 20) {
                            if criticalScanPhase == "NORMAL" || criticalScanPhase == "BEEP" {
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
                                    
                                    Text("SCAN & IDENTIFY")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                }
                            } else if criticalScanPhase == "CRITICAL" {
                                VStack(spacing: 15) {
                                    Image(systemName: currentArrowDirection)
                                            .font(.system(size: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.35, weight: .black))
                                            .foregroundColor(arrowColor)
                                        .shadow(radius: 10)
                                    
                                    Text("CRITICAL SCAN")
                                        .font(.system(size: 50, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                }
                            } else if criticalScanPhase == "RESET" {
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
                                    
                                    Text("SCAN & IDENTIFY")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                }
                            } else if scanningGamePhase == "SCANNING" {
                                // Display sliding players
                                ZStack {
                                    // Sliding players positioned at different screen locations
                                    ForEach(activePlayers) { player in
                                        PlayerView(player: player, isVisible: playersVisible)
                                            .position(getPlayerPosition(for: player.direction))
                                            .onAppear {
                                                print("🎮 PlayerView ForEach appeared for: \(player.imageName) at \(player.direction.rawValue)")
                                            }
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
                
            startCountdown()
        }
        .onDisappear {
            isActive = false
            stopTimer()
                
                // End session tracking
                if let startTime = sessionStartTime {
                    sessionDuration = Date().timeIntervalSince(startTime)
                    endTrainingSession()
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
        countdown = 3
        isCountingDown = true
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            countdown -= 1
            
            if countdown < 0 {
                timer.invalidate()
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
        } else if displayMode != .criticalScan && displayMode != .criticalScanArrows && displayMode != .scanningGame {
            scheduleRandomBeep()
        }
        
        if displayMode == .lanes {
            assignColorsToLanes()
            startLaneAnimation()
        } else if displayMode == .criticalScan {
            print("🔍 Starting Critical Scan Mode")
            startCriticalScanSequence()
        } else if displayMode == .criticalScanArrows {
            print("🔍 Starting Critical Scan Arrows Mode")
            startCriticalScanArrowsSequence()
        } else if displayMode == .scanningGame {
            print("🎮 Starting Scanning Game Mode")
            startScanningGameSequence()
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
        beepTimer?.invalidate()
        
        // Schedule first beep immediately
        scheduleNextBeep()
    }
    
    private func scheduleNextBeep() {
        guard isActive && (displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .numbers || displayMode == .lanes) else { return }
        
        let randomInterval = Double.random(in: selectedBeepInterval.range)
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
            guard isActive && (displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows || displayMode == .numbers || displayMode == .lanes) else { return }
            
            // Play beep
            if soundEnabled {
                audioPlayer?.play()
            }
            
            // Show number or arrow for specific modes
            if displayMode == .colorsNumbers {
                currentNumber = Int.random(in: 1...Int(numberRange))
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
            
            // Schedule next beep
            scheduleNextBeep()
        }
    }
    
    private func stopBeepTimer() {
        beepTimer?.invalidate()
        beepTimer = nil
    }
    
    private func scheduleRandomBeep() {
        guard soundEnabled && isActive else { return }
        
        // Don't schedule beeps for Critical Scan modes or modes with their own beep timer
        guard displayMode != .criticalScan && displayMode != .criticalScanArrows && displayMode != .colors && displayMode != .colorsNumbers && displayMode != .colorsArrows && displayMode != .numbers && displayMode != .lanes else { return }
        
        let randomInterval = Double.random(in: 10...15)
        DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
            if soundEnabled && isActive && displayMode != .criticalScan && displayMode != .criticalScanArrows && displayMode != .colors && displayMode != .colorsNumbers && displayMode != .colorsArrows && displayMode != .numbers && displayMode != .lanes {
                audioPlayer?.play()
                scheduleRandomBeep() // Schedule next beep
            }
        }
    }
    
    private func stopTimer() {
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
        
        private func startCriticalScanSequence() {
            print("🔍 Starting Critical Scan Sequence")
            
            // Start scanning circle timer
            scanningCircleTimer = Timer.scheduledTimer(withTimeInterval: changeInterval, repeats: true) { _ in
                scanningColorIndex = (scanningColorIndex + 1) % selectedColorSet.colors.count
            }
            
            // Schedule first critical scan
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: selectedBeepInterval.range)) {
                startCriticalScanPhase()
            }
        }
        
        private func startCriticalScanPhase() {
            guard isActive else { return }
            
            print("🔴 Starting Critical Scan Phase")
            criticalScanPhase = "BEEP"
            
            // Play critical scan sound immediately
            if soundEnabled {
                playCriticalScanSound()
            }
            
            // Show critical phase after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDelay) {
                guard isActive else { return }
                
                criticalScanPhase = "CRITICAL"
                
                // Select random action number
                currentActionNumber = selectedCriticalScanNumbers.randomElement() ?? 1
                
                // End critical phase after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDuration) {
                    startResetPhase()
                }
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
        
        private func startCriticalScanArrowsSequence() {
            print("🔍 Starting Critical Scan Arrows Sequence")
            
            // Start scanning circle timer
            scanningCircleTimer = Timer.scheduledTimer(withTimeInterval: changeInterval, repeats: true) { _ in
                scanningColorIndex = (scanningColorIndex + 1) % selectedColorSet.colors.count
            }
            
            // Schedule first critical scan
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: selectedBeepInterval.range)) {
                startCriticalScanArrowsPhase()
            }
        }
        
        private func startCriticalScanArrowsPhase() {
            guard isActive else { return }
            
            print("🔴 Starting Critical Scan Arrows Phase")
            criticalScanPhase = "BEEP"
            
            // Play critical scan sound immediately
            if soundEnabled {
                playCriticalScanSound()
            }
            
            // Show critical phase after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDelay) {
                guard isActive else { return }
                
                criticalScanPhase = "CRITICAL"
                
                // Select random arrow
                currentArrowDirection = selectedArrows.randomElement() ?? "arrow.up"
                
                // End critical phase after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDuration) {
                    startResetPhase()
                }
            }
        }
        
        private func startResetPhase() {
            guard isActive else { return }
            
            print("🔵 Starting Reset Phase")
            criticalScanPhase = "RESET"
            
            // End reset phase after reset time
            DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanResetTime) {
                startNormalPhase()
            }
        }
        
        private func startNormalPhase() {
            guard isActive else { return }
            
            print("⚪ Starting Normal Phase")
            criticalScanPhase = "NORMAL"
            
            // Schedule next critical scan based on display mode
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: selectedBeepInterval.range)) {
                if displayMode == .criticalScanArrows {
                    startCriticalScanArrowsPhase()
                } else {
                    startCriticalScanPhase()
                }
            }
        }
    
    private func getRandomColor(excluding currentColor: Color, from availableColors: [Color]) -> Color {
        let filteredColors = availableColors.filter { $0 != currentColor }
        return filteredColors.randomElement() ?? availableColors.randomElement() ?? .red
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
                        } else if selectedMode == .criticalScan {
                            criticalScanGuide
                        } else if selectedMode == .criticalScanArrows {
                            criticalScanArrowsGuide
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
                    
    private var criticalScanGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Critical Scan Numbers Training")
                .font(.title2)
                .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
            Text("High-intensity decision-making under pressure.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Normal scanning phase (white circles)")
                Text("• Critical phase (red background + number)")
                Text("• Execute the action for that number")
                Text("• Reset phase (blue background)")
                Text("• Return to normal scanning")
                            }
            .foregroundColor(.white.opacity(0.7))
        }
                            .padding()
        .background(Color.red.opacity(0.2))
        .cornerRadius(15)
    }
    
    private var criticalScanArrowsGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Critical Scan Arrows Training")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("High-intensity directional decision-making under pressure.")
                .foregroundColor(.white.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Normal scanning phase (white circles)")
                Text("• Critical phase (red background + arrow)")
                Text("• Move in the direction shown")
                Text("• Reset phase (blue background)")
                Text("• Return to normal scanning")
                    }
            .foregroundColor(.white.opacity(0.7))
                            }
                            .padding()
        .background(Color.red.opacity(0.2))
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
        ZStack {
            // Try to load the image, fallback to colored circle if not found
            Image(player.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: imageSize, height: imageSize)
                .opacity(isVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: isVisible)

            
            // Fallback colored circle
            Circle()
                .fill(player.teamColor.color)
                .frame(width: imageSize, height: imageSize)
                .opacity(isVisible ? 0.3 : 0)
                .animation(.easeInOut(duration: 0.8), value: isVisible)
        }
    }
}

// MARK: - Scanning Game Logic Extension
extension DisplayView {
    
    private func startScanningGameSequence() {
        print("🎮 Starting Scanning Game Sequence")
        
        // Start scanning circle timer
        scanningCircleTimer = Timer.scheduledTimer(withTimeInterval: changeInterval, repeats: true) { _ in
            scanningColorIndex = (scanningColorIndex + 1) % selectedColorSet.colors.count
        }
        
        // Schedule first scanning round
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: selectedBeepInterval.range)) {
            startScanningGameRound()
        }
    }
    
    private func startScanningGameRound() {
        guard isActive else { return }
        
        print("🔴 Starting Scanning Game Round")
        scanningGamePhase = "BEEP"
        
        // Play beep sound
        if soundEnabled {
            playCriticalScanSound()
        }
        
        // Show scanning phase after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDelay) {
            guard isActive else { return }
            
            scanningGamePhase = "SCANNING"
            generatePlayers()
            slideInPlayers()
            
            // End scanning phase after duration (give more time for scanning game)
            let scanningDuration = displayMode == .scanningGame ? max(criticalScanDuration, 3.0) : criticalScanDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + scanningDuration) {
                startScanningGameResetPhase()
            }
        }
    }
    
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
        
        // End reset phase after reset time
        DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanResetTime) {
            startScanningGameNormalPhase()
        }
    }
    
    private func startScanningGameNormalPhase() {
        guard isActive else { return }
        
        print("⚪ Starting Scanning Game Normal Phase")
        scanningGamePhase = "NORMAL"
        
        // Schedule next scanning round
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: selectedBeepInterval.range)) {
            startScanningGameRound()
        }
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


