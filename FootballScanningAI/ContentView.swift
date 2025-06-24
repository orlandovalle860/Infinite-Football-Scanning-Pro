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

enum BeepInterval: String, CaseIterable {
    case fast = "Fast (2-4s)"
    case medium = "Medium (4-6s)" 
    case slow = "Slow (8-10s)"
    
    var range: ClosedRange<Double> {
        switch self {
        case .fast: return 2.0...4.0
        case .medium: return 4.0...6.0
        case .slow: return 8.0...10.0
        }
    }
}

enum ScanningColorSet: String, CaseIterable {
    case standard = "Standard (White/Black/Red)"
    case highContrast = "High Contrast (Yellow/Blue/White)"
    case vibrant = "Vibrant (Orange/Green/Purple)"
    
    var colors: [Color] {
        switch self {
        case .standard:
            return [.white, .black, .red]
        case .highContrast:
            return [.yellow, .blue, .white]
        case .vibrant:
            return [.orange, .green, .purple]
        }
    }
}

enum ActionSet: String, CaseIterable {
    case basic = "Basic Actions"
    case advanced = "Advanced Actions"
    case defensive = "Defensive Actions"
    case custom = "Custom Actions"
    
    var actions: [String] {
        switch self {
        case .basic:
            return ["Dribble forward", "Dribble left", "Dribble right", "Dribble back", "Pass left", "Pass right", "Pass forward", "Pass back", "Shoot"]
        case .advanced:
            return ["Turn left", "Turn right", "Cross to far post", "Through ball", "Long shot", "One-touch pass"]
        case .defensive:
            return ["Tackle", "Intercept", "Mark player", "Clear ball", "Close down", "Cover space"]
        case .custom:
            return ["Custom Action 1", "Custom Action 2", "Custom Action 3", "Custom Action 4"]
        }
    }
}

struct CustomAction {
    let number: Int
    var action: String
    var isCustom: Bool
}

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
    var body: some View {
        NavigationStack {
            IntroView()
        }
        .navigationViewStyle(.stack)
        .environment(\.sizeCategory, .large) // Force consistent sizing
        .environment(\.colorScheme, .dark) // Force dark mode for consistency
    }
}

struct IntroView: View {
    @State private var navigateToMain = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                Text("The Art of Scanning")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
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
                        BenefitRow(icon: "bolt.fill", text: "Faster Reaction Time")
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
                    
                    // Kroos Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Toni Kroos")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Kroos scans the field before receiving the ball, enabling him to make perfect first-time passes.")
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                        
                        Link(destination: URL(string: "https://www.youtube.com/shorts/cUZnfkri6yw")!) {
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
                
                // Start Practice Button
                Button(action: { navigateToMain = true }) {
                    Text("Start Practice")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(StartButtonStyle(isEnabled: true))
                .padding(.horizontal)
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
        .navigationDestination(isPresented: $navigateToMain) {
            MainView()
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

struct MainView: View {
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
    @State private var soundEnabled: Bool = true
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
    @State private var criticalScanDelay: Double = 1.5 // Delay time for critical scan (0.5-3.0 seconds)
    @State private var criticalScanDuration: Double = 1.0 // How long critical scan stays on screen (0.5-2.0 seconds)
    @State private var selectedColorSet: ScanningColorSet = .standard // Default to standard colors
    @State private var selectedActionSet: ActionSet = .basic // Default to basic actions
    @State private var customActions: [CustomAction] = [
        CustomAction(number: 1, action: "Action", isCustom: false),
        CustomAction(number: 2, action: "Action", isCustom: false),
        CustomAction(number: 3, action: "Action", isCustom: false),
        CustomAction(number: 4, action: "Action", isCustom: false),
        CustomAction(number: 5, action: "Action", isCustom: false),
        CustomAction(number: 6, action: "Action", isCustom: false),
        CustomAction(number: 7, action: "Action", isCustom: false),
        CustomAction(number: 8, action: "Action", isCustom: false)
    ]
    @State private var showingCustomActionSheet = false
    @State private var editingActionNumber: Int = 1
    @State private var showingActionList = false
    @State private var selectedActionForNumber: Int = 1
    @State private var selectedCriticalScanNumbers: Set<Int> = [1] // Default to only number 1
    
    
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
    
    let availableLanes = ["Left", "Center", "Right"]
    
    init(selectedColors: [Color] = [], displayMode: DisplayMode = .colors, changeInterval: Double = 1.5, selectedNumbers: Set<Int> = [], soundEnabled: Bool = true) {
        self.selectedColors = selectedColors
        self.displayMode = displayMode
        self.changeInterval = changeInterval
        self.selectedNumbers = selectedNumbers
        self.soundEnabled = soundEnabled
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
                soundEnabled: soundEnabled,
                laneSpeed: laneSpeed,
                numberRange: numberRange,
                selectedArrows: Array(selectedArrows),
                selectedBeepInterval: selectedBeepInterval,
                criticalScanDelay: criticalScanDelay,
                criticalScanDuration: criticalScanDuration,
                selectedColorSet: selectedColorSet,
                customActions: customActions,
                selectedCriticalScanNumbers: Array(selectedCriticalScanNumbers).sorted(),
                showDisplay: $showDisplay
            )
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        } else {
            // Configuration View
            NavigationView {
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
                            // Mode Selection
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Display Mode")
                                    .font(.headline)
                        .foregroundColor(.white)
                                    .environment(\.sizeCategory, .large) // Force consistent size
                                
                                // Normal Scan Modes
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Normal Scan Modes")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 4)
                                        .environment(\.sizeCategory, .large) // Force consistent size
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                        Button(action: {
                                            displayMode = .colors
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedColors.removeAll()
                                            selectedArrows.removeAll()
                                            selectedBeepInterval = .medium
                                            criticalScanDelay = 1.5
                                            criticalScanDuration = 1.0
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
                                            displayMode = .colorsNumbers
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedColors.removeAll()
                                            selectedArrows.removeAll()
                                            selectedBeepInterval = .medium
                                            criticalScanDelay = 1.5
                                            criticalScanDuration = 1.0
                                        }) {
                                            Text("Colors + Nums")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(displayMode == .colorsNumbers ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 6)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .colorsNumbers, color: .blue))
                                        
                                        Button(action: {
                                            displayMode = .colorsArrows
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedColors.removeAll()
                                            selectedArrows.removeAll()
                                            selectedBeepInterval = .medium
                                            criticalScanDelay = 1.5
                                            criticalScanDuration = 1.0
                                        }) {
                                            Text("Colors + Arrows")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(displayMode == .colorsArrows ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 6)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .colorsArrows, color: .blue))
                                        
                                        Button(action: {
                                            displayMode = .numbers
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedColors.removeAll()
                                            selectedArrows.removeAll()
                                            selectedBeepInterval = .medium
                                            criticalScanDelay = 1.5
                                            criticalScanDuration = 1.0
                                        }) {
                                            Text("Nums")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(displayMode == .numbers ? .white : .white.opacity(0.7))
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 6)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(DisplayModeButtonStyle(isSelected: displayMode == .numbers, color: .blue))
                                        
                                        Button(action: {
                                            displayMode = .lanes
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedColors.removeAll()
                                            selectedArrows.removeAll()
                                            selectedBeepInterval = .medium
                                            criticalScanDelay = 1.5
                                            criticalScanDuration = 1.0
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
                                }
                                
                                // Critical Scan Modes
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Critical Scan Modes")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 4)
                                        .environment(\.sizeCategory, .large) // Force consistent size
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                        Button(action: {
                                            displayMode = .criticalScan
                                            selectedNumbers.removeAll()
                                            selectedLanes.removeAll()
                                            selectedColors.removeAll()
                                            selectedArrows.removeAll()
                                            selectedBeepInterval = .medium
                                            criticalScanDelay = 1.5
                                            criticalScanDuration = 1.0
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
                                            selectedColors.removeAll()
                                            selectedArrows.removeAll()
                                            selectedBeepInterval = .medium
                                            criticalScanDelay = 1.5
                                            criticalScanDuration = 1.0
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
                                    
                                    Toggle("", isOn: $soundEnabled)
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
                            
                            // Beep Interval Selection (only for Colors + Numbers and Colors + Arrows modes)
                            if displayMode == .colorsNumbers || displayMode == .colorsArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Beep Interval")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
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
                                    Text("Select Colors (\(selectedLanes.count) colors max)")
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
                            
                            // Number Range Slider (only for Colors + Numbers mode)
                            if displayMode == .colorsNumbers {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Number Range: 1-\(Int(numberRange))")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Slider(value: $numberRange, in: 1...10, step: 1)
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
                            if displayMode != .criticalScan && displayMode != .criticalScanArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(displayMode == .colors || displayMode == .colorsNumbers || displayMode == .colorsArrows ? "Color Changing Time Interval: \(String(format: "%.1f", changeInterval))s" : displayMode == .numbers ? "Color and Number Changing Time Interval: \(String(format: "%.1f", changeInterval))s" : "Time Interval: \(String(format: "%.1f", changeInterval))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
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
                            
                            // Scanning Circle Time Interval (only for Critical Scan modes)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Scanning Circle Time Interval: \(String(format: "%.1f", changeInterval))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
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
                            
                            // Critical Scan Delay Slider (only for Critical Scan mode)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Critical Scan Delay: \(String(format: "%.1f", criticalScanDelay))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Slider(value: $criticalScanDelay, in: 0.5...3.0, step: 0.1)
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
                            
                            // Critical Scan Duration Slider (only for Critical Scan mode)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Critical Scan Duration: \(String(format: "%.1f", criticalScanDuration))s")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Slider(value: $criticalScanDuration, in: 0.5...2.0, step: 0.1)
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
                            
                            // Scanning Circle Colors (only for Critical Scan mode)
                            if displayMode == .criticalScan || displayMode == .criticalScanArrows {
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
                                    .onChange(of: selectedActionSet) { _, newValue in
                                        updateCustomActions()
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
                                        ForEach(customActions.filter { selectedCriticalScanNumbers.contains($0.number) }, id: \.number) { customAction in
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
                        currentAction: customActions.first { $0.number == editingActionNumber }?.action ?? "",
                        selectedActionSet: selectedActionSet,
                        onSave: { newAction in
                            if let index = customActions.firstIndex(where: { $0.number == editingActionNumber }) {
                                customActions[index].action = newAction
                                customActions[index].isCustom = true
                            }
                        }
                    )
                }
                .sheet(isPresented: $showingActionList) {
                    ActionListSheet(
                        actionNumber: selectedActionForNumber,
                        currentAction: customActions.first { $0.number == selectedActionForNumber }?.action ?? "",
                        basicActions: ActionSet.basic.actions,
                        onSelect: { selectedAction in
                            if let index = customActions.firstIndex(where: { $0.number == selectedActionForNumber }) {
                                customActions[index].action = selectedAction
                                customActions[index].isCustom = !ActionSet.basic.actions.contains(selectedAction)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var isStartEnabled: Bool {
        if displayMode == .colors {
            return !selectedColors.isEmpty
        } else if displayMode == .colorsNumbers {
            return !selectedColors.isEmpty
        } else if displayMode == .colorsArrows {
            return !selectedColors.isEmpty && !selectedArrows.isEmpty
        } else if displayMode == .numbers {
            return !selectedColors.isEmpty && !selectedNumbers.isEmpty
        } else if displayMode == .lanes {
            return !selectedColors.isEmpty && !selectedLanes.isEmpty
        } else if displayMode == .criticalScan {
            return true // Critical Scan mode doesn't need any selections
        } else if displayMode == .criticalScanArrows {
            return !selectedArrows.isEmpty // Need at least one arrow selected
        }
        return false
    }
    
    private let availableColors: [Color] = [
        Color(red: 0.8, green: 0.0, blue: 0.0), // Darker red
        .blue,
        .green,
        Color(red: 1.0, green: 0.8, blue: 0.0), // Bright yellow
        Color(red: 0.9, green: 0.5, blue: 0.0), // Darker orange
        .white,
        Color(red: 1.0, green: 0.4, blue: 0.8)
    ]
    
    private func updateCustomActions() {
        let actions = selectedActionSet.actions
        // Update existing actions and add new ones if needed
        for i in 0..<actions.count {
            if i < customActions.count {
                customActions[i].action = actions[i]
                customActions[i].isCustom = false
            } else {
                customActions.append(CustomAction(number: i + 1, action: actions[i], isCustom: false))
            }
        }
    }
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

enum DisplayMode {
    case colors
    case colorsNumbers
    case colorsArrows
    case numbers
    case lanes
    case criticalScan
    case criticalScanArrows
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
    let selectedColorSet: ScanningColorSet
    let customActions: [CustomAction]
    let selectedCriticalScanNumbers: [Int]
    @Binding var showDisplay: Bool
    
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
    
    let availableLanes = ["Left", "Center", "Right"]
    
    init(selectedColors: [Color], displayMode: DisplayMode, changeInterval: Double, selectedNumbers: [Int], soundEnabled: Bool, laneSpeed: Double, numberRange: Double, selectedArrows: [String], selectedBeepInterval: BeepInterval, criticalScanDelay: Double, criticalScanDuration: Double, selectedColorSet: ScanningColorSet, customActions: [CustomAction], selectedCriticalScanNumbers: [Int], showDisplay: Binding<Bool>) {
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
        self.selectedColorSet = selectedColorSet
        self.customActions = customActions
        self.selectedCriticalScanNumbers = selectedCriticalScanNumbers
        self._currentColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
        self._currentNumberColor = State(initialValue: selectedColors.first ?? selectedColors.randomElement() ?? .red)
        self._showDisplay = showDisplay
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
                            .font(.system(size: 150, weight: .bold))
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
                                    .foregroundColor(.white)
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
                                    .font(.system(size: 200, weight: .black))
                                    .foregroundColor(.white)
                                    .shadow(radius: 15)
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
                                .font(.system(size: 120, weight: .bold))
                                .foregroundColor(.white)
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
                        if criticalScanPhase == "NORMAL" {
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
                            if criticalScanPhase == "NORMAL" {
                                VStack(spacing: 15) {
                                    // Scanning circle (cycles through colors every second)
                                    Circle()
                                        .fill(selectedColorSet.colors[scanningColorIndex])
                                        .frame(width: 300, height: 300)
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
                                        .font(.system(size: 120, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 10)
                                    
                                    Text("CRITICAL SCAN")
                                        .font(.system(size: 50, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 5)
                                    
                                    Text(customActions.first { $0.number == currentActionNumber }?.action ?? "")
                                        .font(.system(size: 30, weight: .medium))
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
                        if criticalScanPhase == "NORMAL" {
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
                            if criticalScanPhase == "NORMAL" {
                                VStack(spacing: 15) {
                                    // Scanning circle (cycles through colors every second)
                                    Circle()
                                        .fill(selectedColorSet.colors[scanningColorIndex])
                                        .frame(width: 300, height: 300)
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
                                        .font(.system(size: 120, weight: .bold))
                                        .foregroundColor(.white)
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
                }
            }
            
            // Double tap indicator (only show after countdown)
            if !isCountingDown {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(8)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                            .padding()
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            isActive = false
            stopTimer()
        }
        .onTapGesture(count: 2) {
            if !isCountingDown {
                isActive = false
                showDisplay = false
            }
        }
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
        startTimer()
        setupAudio()
        
        if displayMode == .colorsNumbers || displayMode == .colorsArrows {
            startBeepTimer()
        } else if displayMode != .criticalScan && displayMode != .criticalScanArrows {
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
        } else if displayMode == .colorsNumbers || displayMode == .colorsArrows {
            print("🎨 Starting \(displayMode) Mode")
            // These modes use the standard timer + beep timer
        } else {
            print("🎯 Starting other mode: \(displayMode)")
        }
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
                if let randomColor = selectedColors.randomElement() {
                    currentColor = randomColor
                }
            } else if displayMode == .numbers {
                if let randomNumber = selectedNumbers.randomElement() {
                    currentNumber = randomNumber
                    if let randomColor = selectedColors.randomElement() {
                        currentNumberColor = randomColor
                    }
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
        guard isActive && (displayMode == .colorsNumbers || displayMode == .colorsArrows) else { return }
        
        let randomInterval = Double.random(in: selectedBeepInterval.range)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
            guard isActive && (displayMode == .colorsNumbers || displayMode == .colorsArrows) else { return }
            
            // Play beep and show number/arrow
            if soundEnabled {
                audioPlayer?.play()
            }
            
            // Show number or arrow
            if displayMode == .colorsNumbers {
                currentNumber = Int.random(in: 1...Int(numberRange))
            } else if displayMode == .colorsArrows {
                currentArrowDirection = selectedArrows.randomElement() ?? "arrow.up"
            }
            
            showNumberOrArrow = true
            
            // Hide after 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showNumberOrArrow = false
            }
            
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
        
        // Don't schedule beeps for Critical Scan modes - they have their own timing
        guard displayMode != .criticalScan && displayMode != .criticalScanArrows && displayMode != .colorsNumbers && displayMode != .colorsArrows else { return }
        
        let randomInterval = Double.random(in: 10...15)
        DispatchQueue.main.asyncAfter(deadline: .now() + randomInterval) {
            if soundEnabled && isActive && displayMode != .criticalScan && displayMode != .criticalScanArrows && displayMode != .colorsNumbers && displayMode != .colorsArrows {
                audioPlayer?.play()
                scheduleRandomBeep() // Schedule next beep
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        stopBeepTimer()
        stopScanningCircleTimer()
    }
    
    private func startCriticalScanSequence() {
        print("🔍 Critical Scan Sequence Started")
        
        // Stop any existing critical scan timer
        criticalScanTimer?.invalidate()
        
        // Don't start if app is not active
        guard isActive else { return }
        
        // Phase 1: Normal Scan (Green background, 5-7 seconds)
        criticalScanPhase = "NORMAL"
        print("📖 Phase: NORMAL SCAN")
        
        // Start scanning circle timer (changes every second)
        startScanningCircleTimer()
        
        // Phase 2: Critical Scan (Red background, custom delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 5.0...7.0)) {
            // Check if still active before proceeding
            guard isActive else { return }
            
            // Stop scanning circle timer
            stopScanningCircleTimer()
            
            // Play single beep to alert passer to play the ball
            if soundEnabled {
                playCriticalScanSound()
            }
            
            // Show critical scan screen after custom delay (time for passer to react and play ball)
            DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDelay) {
                guard isActive else { return }
                
                criticalScanPhase = "CRITICAL"
                currentActionNumber = selectedCriticalScanNumbers.randomElement() ?? 1
                print("🚨 Phase: CRITICAL SCAN - Action \(currentActionNumber)")
                
                // Phase 3: Execution (custom duration to receive and decide)
                DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDuration) {
                    guard isActive && displayMode == .criticalScan else { return }
                    
                    // Phase 4: Reset Period (immediate for action 1, 10 seconds for others)
                    criticalScanPhase = "RESET"
                    print("🔄 Phase: RESET - Preparing for next play")
                    
                    // Determine reset duration based on action performed
                    let resetDuration: Double = currentActionNumber == 1 ? 0.0 : 10.0
                    print("⏱️ Reset duration: \(resetDuration) seconds (Action: \(currentActionNumber))")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + resetDuration) {
                        // Check if still active and still in critical scan mode
                        guard isActive && displayMode == .criticalScan else { return }
                        
                        print("🔄 Restarting Critical Scan Sequence")
                        startCriticalScanSequence() // Restart the sequence
                    }
                }
            }
        }
    }
    
    private func playCriticalScanSound() {
        // Only play sound if app is still active
        guard isActive else { return }
        
        // Use the critical scan beep file
        if criticalScanAudioPlayer == nil {
            guard let soundURL = Bundle.main.url(forResource: "critical scan beep", withExtension: "wav") else {
                print("Could not find critical scan sound file")
                return
            }
            
            do {
                criticalScanAudioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                criticalScanAudioPlayer?.volume = 1.0 // Maximum volume
                criticalScanAudioPlayer?.prepareToPlay()
            } catch {
                print("Could not create critical scan audio player: \(error)")
                return
            }
        }
        
        criticalScanAudioPlayer?.play()
    }
    
    private func startScanningCircleTimer() {
        scanningCircleTimer?.invalidate()
        scanningCircleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isActive && criticalScanPhase == "NORMAL" {
                // Randomly select a color from the selected color set
                scanningColorIndex = Int.random(in: 0..<selectedColorSet.colors.count)
            }
        }
    }
    
    private func stopScanningCircleTimer() {
        scanningCircleTimer?.invalidate()
        scanningCircleTimer = nil
    }
    
    private func startCriticalScanArrowsSequence() {
        print("🔍 Critical Scan Arrows Sequence Started")
        
        // Stop any existing critical scan timer
        criticalScanTimer?.invalidate()
        
        // Don't start if app is not active
        guard isActive else { return }
        
        // Phase 1: Normal Scan (Black background, 5-7 seconds)
        criticalScanPhase = "NORMAL"
        print("📖 Phase: NORMAL SCAN")
        
        // Start scanning circle timer (changes every second)
        startScanningCircleTimer()
        
        // Phase 2: Critical Scan (Red background, custom delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 5.0...7.0)) {
            // Check if still active before proceeding
            guard isActive else { return }
            
            // Stop scanning circle timer
            stopScanningCircleTimer()
            
            // Play single beep to alert passer to play the ball
            if soundEnabled {
                playCriticalScanSound()
            }
            
            // Show critical scan screen after custom delay (time for passer to react and play ball)
            DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDelay) {
                guard isActive else { return }
                
                criticalScanPhase = "CRITICAL"
                currentArrowDirection = selectedArrows.randomElement() ?? "arrow.up"
                print("🚨 Phase: CRITICAL SCAN - Arrow \(currentArrowDirection)")
                
                // Phase 3: Execution (custom duration to receive and decide)
                DispatchQueue.main.asyncAfter(deadline: .now() + criticalScanDuration) {
                    guard isActive && displayMode == .criticalScanArrows else { return }
                    
                    // Phase 4: Reset Period (10 seconds)
                    criticalScanPhase = "RESET"
                    print("🔄 Phase: RESET - Preparing for next play")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        // Check if still active and still in critical scan arrows mode
                        guard isActive && displayMode == .criticalScanArrows else { return }
                        
                        print("🔄 Restarting Critical Scan Arrows Sequence")
                        startCriticalScanArrowsSequence() // Restart the sequence
                    }
                }
            }
        }
    }
}

struct Activity {
    let title: String
    let description: String
    let setup: String
    let progression: String
    let duration: String
    let focus: String
}

struct DetailRow: View {
    let label: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
                .frame(width: 70, alignment: .leading)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.leading)
        }
    }
}

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 16))
            
            Text(text)
                                                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct ActivitiesGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let selectedMode: DisplayMode
    
    var body: some View {
        NavigationView {
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
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 10) {
                            Text("\(modeTitle) Activities")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(modeSubtitle)
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top)
                        
                        // Activities for selected mode
                        ActivitySection(
                            title: "\(modeTitle) Activities",
                            subtitle: modeSubtitle,
                            activities: selectedActivities
                        )
                        
                        // General Tips
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Training Tips")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                TipRow(text: "Position iPad behind players for realistic shoulder checking")
                                TipRow(text: "Start with longer intervals and gradually increase speed")
                                TipRow(text: "Focus on technique before speed")
                                TipRow(text: "Take regular breaks to prevent fatigue")
                                TipRow(text: "Practice consistently for best results")
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
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Activities Guide")
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
    
    // Computed properties for mode-specific content
    private var modeTitle: String {
        switch selectedMode {
        case .colors:
            return "Colors Mode"
        case .numbers:
            return "Numbers Mode"
        case .lanes:
            return "Lanes Mode"
        case .criticalScan:
            return "Critical Scan Numbers"
        case .colorsNumbers:
            return "Colors and Numbers Mode"
        case .colorsArrows:
            return "Colors and Arrows Mode"
        case .criticalScanArrows:
            return "Critical Scan Arrows"
        }
    }
    
    private var modeSubtitle: String {
        switch selectedMode {
        case .colors:
            return "Basic scanning and color recognition"
        case .numbers:
            return "Number recognition and pattern awareness"
        case .lanes:
            return "Spatial awareness and zone scanning"
        case .criticalScan:
            return "Advanced decision making under pressure"
        case .colorsNumbers:
            return "Color and number recognition"
        case .colorsArrows:
            return "Color and arrow recognition"
        case .criticalScanArrows:
            return "Color and arrow recognition"
        }
    }
    
    private var selectedActivities: [Activity] {
        switch selectedMode {
        case .colors:
            return colorsActivities
        case .numbers:
            return numbersActivities
        case .lanes:
            return lanesActivities
        case .criticalScan:
            return criticalScanActivities
        case .colorsNumbers:
            return colorsNumbersActivities
        case .colorsArrows:
            return colorsArrowsActivities
        case .criticalScanArrows:
            return criticalScanArrowsActivities
        }
    }
    
    // Activity data
    private let colorsActivities = [
        Activity(
            title: "Shoulder Check Color ID",
            description: "Check shoulders and identify the current color",
            setup: "2-3 colors, 2-second intervals, iPad behind players",
            progression: "Start with 2 colors, add more, increase speed",
            duration: "10-15 minutes",
            focus: "Basic color recognition and shoulder checking"
        ),
        Activity(
            title: "Color Memory Challenge",
            description: "Remember the last 3-4 color changes",
            setup: "3-4 colors, 1.5-second intervals",
            progression: "Increase number of colors to remember",
            duration: "10-15 minutes",
            focus: "Visual memory and recall"
        ),
        Activity(
            title: "Alternating Shoulder Scan",
            description: "Check right shoulder, then left shoulder, alternating",
            setup: "2-3 colors, 2-second intervals",
            progression: "Increase speed, add more colors",
            duration: "10-15 minutes",
            focus: "Balanced scanning on both sides"
        ),
        Activity(
            title: "Color Pattern Recognition",
            description: "Identify color patterns (red-blue-green, etc.)",
            setup: "4-5 colors, 1.5-second intervals",
            progression: "More complex patterns, faster sequences",
            duration: "15-20 minutes",
            focus: "Pattern recognition and scanning intelligence"
        ),
        Activity(
            title: "Speed Color Scanning",
            description: "Rapid shoulder checking to identify color changes",
            setup: "3-4 colors, fast intervals (0.5-1.0 seconds)",
            progression: "Start slow, gradually increase speed",
            duration: "15-20 minutes",
            focus: "Scanning speed and reaction time"
        )
    ]
    
    private let numbersActivities = [
        Activity(
            title: "Number Recognition",
            description: "Check shoulders and identify numbers quickly",
            setup: "Numbers 1-4, bright colors, 1.5-second intervals",
            progression: "Add more numbers, increase speed",
            duration: "10-15 minutes",
            focus: "Quick number identification"
        ),
        Activity(
            title: "Number Pattern Recognition",
            description: "Identify number sequences and patterns",
            setup: "Numbers 1-4, 1.5-second intervals",
            progression: "More complex patterns, faster sequences",
            duration: "15-20 minutes",
            focus: "Pattern recognition and scanning intelligence"
        ),
        Activity(
            title: "Peripheral Vision Training",
            description: "Scan without directly looking at the screen",
            setup: "Large numbers, 2-second intervals",
            progression: "Smaller numbers, faster intervals",
            duration: "10-15 minutes",
            focus: "Peripheral vision development"
        ),
        Activity(
            title: "Number Communication",
            description: "Call out numbers to teammates while scanning",
            setup: "Numbers 1-4, 1.5-second intervals",
            progression: "More complex communication sequences",
            duration: "15-20 minutes",
            focus: "Communication while scanning"
        )
    ]
    
    private let lanesActivities = [
        Activity(
            title: "Lane Awareness Building",
            description: "Practice scanning across different zones",
            setup: "2 lanes, 2-3 colors, medium speed",
            progression: "Add more lanes, increase speed",
            duration: "15-20 minutes",
            focus: "Spatial awareness and zone recognition"
        ),
        Activity(
            title: "Multi-Zone Scanning",
            description: "Develop awareness of multiple areas",
            setup: "3 lanes, 3-4 colors, 1.5-second intervals",
            progression: "Faster scanning between zones",
            duration: "20-25 minutes",
            focus: "Multi-zone awareness"
        ),
        Activity(
            title: "Position-Specific Lanes",
            description: "Focus on lanes relevant to your position",
            setup: "2-3 lanes, position-specific colors",
            progression: "More complex zone combinations",
            duration: "15-20 minutes",
            focus: "Position-specific awareness"
        )
    ]
    
    private let criticalScanActivities = [
        Activity(
            title: "Decision Making Under Pressure",
            description: "Practice quick decisions based on action numbers",
            setup: "Critical Scan mode, iPad behind players",
            progression: "Faster decision making, more complex scenarios",
            duration: "20-25 minutes",
            focus: "Quick decision making under pressure"
        ),
        Activity(
            title: "Scanning Circle Identification",
            description: "Identify circle colors during normal scan phase",
            setup: "Critical Scan mode, focus on normal phase",
            progression: "Faster circle changes, more colors",
            duration: "15-20 minutes",
            focus: "Multi-tasking and visual processing"
        ),
        Activity(
            title: "Position-Specific Training",
            description: "Focus on actions relevant to your position",
            setup: "Critical Scan mode, position-specific focus",
            progression: "More complex scenarios, faster execution",
            duration: "25-30 minutes",
            focus: "Position-specific decision making"
        ),
        Activity(
            title: "Endurance Training",
            description: "Extended Critical Scan practice sessions",
            setup: "Critical Scan mode, longer sessions",
            progression: "Longer sessions, faster intervals",
            duration: "30-45 minutes",
            focus: "Scanning stamina and consistency"
        ),
        Activity(
            title: "Pressure Training",
            description: "Add physical movement while scanning",
            setup: "Critical Scan mode, add jogging or ball work",
            progression: "More intense physical activity",
            duration: "20-25 minutes",
            focus: "Scanning under physical stress"
        )
    ]
    
    private let colorsNumbersActivities = [
        Activity(
            title: "Color and Number Recognition",
            description: "Identify colors and numbers simultaneously",
            setup: "2-3 colors, 2-second intervals, iPad behind players",
            progression: "Start with 2 colors and 1 number, add more, increase speed",
            duration: "10-15 minutes",
            focus: "Combined color and number recognition"
        ),
        Activity(
            title: "Color Memory Challenge",
            description: "Remember the last 3-4 color changes",
            setup: "3-4 colors, 1.5-second intervals",
            progression: "Increase number of colors to remember",
            duration: "10-15 minutes",
            focus: "Visual memory and recall"
        ),
        Activity(
            title: "Alternating Shoulder Scan",
            description: "Check right shoulder, then left shoulder, alternating",
            setup: "2-3 colors, 2-second intervals",
            progression: "Increase speed, add more colors",
            duration: "10-15 minutes",
            focus: "Balanced scanning on both sides"
        ),
        Activity(
            title: "Color Pattern Recognition",
            description: "Identify color patterns (red-blue-green, etc.)",
            setup: "4-5 colors, 1.5-second intervals",
            progression: "More complex patterns, faster sequences",
            duration: "15-20 minutes",
            focus: "Pattern recognition and scanning intelligence"
        ),
        Activity(
            title: "Speed Color Scanning",
            description: "Rapid shoulder checking to identify color changes",
            setup: "3-4 colors, fast intervals (0.5-1.0 seconds)",
            progression: "Start slow, gradually increase speed",
            duration: "15-20 minutes",
            focus: "Scanning speed and reaction time"
        )
    ]
    
    private let colorsArrowsActivities = [
        Activity(
            title: "Color and Arrow Recognition",
            description: "Identify colors and arrows simultaneously",
            setup: "2-3 colors, 2-second intervals, iPad behind players",
            progression: "Start with 2 colors and 1 arrow, add more, increase speed",
            duration: "10-15 minutes",
            focus: "Combined color and arrow recognition"
        ),
        Activity(
            title: "Color Memory Challenge",
            description: "Remember the last 3-4 color changes",
            setup: "3-4 colors, 1.5-second intervals",
            progression: "Increase number of colors to remember",
            duration: "10-15 minutes",
            focus: "Visual memory and recall"
        ),
        Activity(
            title: "Alternating Shoulder Scan",
            description: "Check right shoulder, then left shoulder, alternating",
            setup: "2-3 colors, 2-second intervals",
            progression: "Increase speed, add more colors",
            duration: "10-15 minutes",
            focus: "Balanced scanning on both sides"
        ),
        Activity(
            title: "Color Pattern Recognition",
            description: "Identify color patterns (red-blue-green, etc.)",
            setup: "4-5 colors, 1.5-second intervals",
            progression: "More complex patterns, faster sequences",
            duration: "15-20 minutes",
            focus: "Pattern recognition and scanning intelligence"
        ),
        Activity(
            title: "Speed Color Scanning",
            description: "Rapid shoulder checking to identify color changes",
            setup: "3-4 colors, fast intervals (0.5-1.0 seconds)",
            progression: "Start slow, gradually increase speed",
            duration: "15-20 minutes",
            focus: "Scanning speed and reaction time"
        )
    ]
    
    private let criticalScanArrowsActivities = [
        Activity(
            title: "Directional Decision Making",
            description: "Practice quick directional decisions based on arrow prompts",
            setup: "Critical Scan Arrows mode, iPad behind players",
            progression: "Faster decision making, more complex arrow combinations",
            duration: "20-25 minutes",
            focus: "Quick directional decision making under pressure"
        ),
        Activity(
            title: "Scanning Circle Identification",
            description: "Identify circle colors during normal scan phase",
            setup: "Critical Scan Arrows mode, focus on normal phase",
            progression: "Faster circle changes, more colors",
            duration: "15-20 minutes",
            focus: "Multi-tasking and visual processing"
        ),
        Activity(
            title: "Arrow Recognition Training",
            description: "Focus on recognizing and responding to arrow directions",
            setup: "Critical Scan Arrows mode, select specific arrows",
            progression: "More complex arrow combinations, faster execution",
            duration: "25-30 minutes",
            focus: "Arrow recognition and response"
        ),
        Activity(
            title: "Endurance Training",
            description: "Extended Critical Scan Arrows practice sessions",
            setup: "Critical Scan Arrows mode, longer sessions",
            progression: "Longer sessions, faster intervals",
            duration: "30-45 minutes",
            focus: "Scanning stamina and consistency"
        ),
        Activity(
            title: "Pressure Training",
            description: "Add physical movement while scanning arrows",
            setup: "Critical Scan Arrows mode, add jogging or ball work",
            progression: "More intense physical activity",
            duration: "20-25 minutes",
            focus: "Arrow scanning under physical stress"
        )
    ]
}

struct ActivitySection: View {
    let title: String
    let subtitle: String
    let activities: [Activity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            VStack(spacing: 12) {
                ForEach(activities, id: \.title) { activity in
                    ActivityCard(activity: activity)
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

struct ActivityCard: View {
    let activity: Activity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(activity.title)
                                    .font(.headline)
                .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
            Text(activity.description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(label: "Setup:", text: activity.setup)
                DetailRow(label: "Progression:", text: activity.progression)
                DetailRow(label: "Duration:", text: activity.duration)
                DetailRow(label: "Focus:", text: activity.focus)
            }
                            }
                            .padding()
                            .background {
            RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                .opacity(0.5)
        }
    }
}

struct CustomActionSheet: View {
    let actionNumber: Int
    let currentAction: String
    let selectedActionSet: ActionSet
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAction: String
    @State private var customText: String = ""
    @State private var isCustom: Bool = false
    
    init(actionNumber: Int, currentAction: String, selectedActionSet: ActionSet, onSave: @escaping (String) -> Void) {
        self.actionNumber = actionNumber
        self.currentAction = currentAction
        self.selectedActionSet = selectedActionSet
        self.onSave = onSave
        self._selectedAction = State(initialValue: currentAction)
        self._customText = State(initialValue: currentAction)
    }
    
    var body: some View {
        NavigationView {
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
                
                VStack(spacing: 20) {
                    Text("Action for Number \(actionNumber)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top)
                    
                    // Preset Actions
                            VStack(alignment: .leading, spacing: 10) {
                        Text("Preset Actions")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(selectedActionSet.actions, id: \.self) { action in
                                        Button(action: {
                                        selectedAction = action
                                        isCustom = false
                                    }) {
                                        HStack {
                                            Text(action)
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.leading)
                                            
                                            Spacer()
                                            
                                            if selectedAction == action && !isCustom {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding()
                                    }
                                    .buttonStyle(PresetActionButtonStyle(isSelected: selectedAction == action && !isCustom))
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    
                    // Custom Action
                            VStack(alignment: .leading, spacing: 10) {
                        Text("Custom Action")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                        TextField("Enter custom action...", text: $customText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: customText) { _, newValue in
                                if !newValue.isEmpty {
                                    selectedAction = newValue
                                    isCustom = true
                                }
                            }
                        
                        Button(action: {
                            selectedAction = customText
                            isCustom = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Use Custom Action")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CustomActionButtonStyle(isActive: isCustom, isEmpty: customText.isEmpty))
                        .disabled(customText.isEmpty)
                    }
                    
                    Spacer()
                            }
                            .padding()
            }
            .navigationTitle("Edit Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(selectedAction)
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .disabled(selectedAction.isEmpty)
                }
            }
        }
    }
}

struct ActionListSheet: View {
    let actionNumber: Int
    let currentAction: String
    let basicActions: [String]
    let onSelect: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var customText: String = ""
    
    var body: some View {
        NavigationView {
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
                
                VStack(spacing: 20) {
                    Text("Select Action for Number \(actionNumber)")
                        .font(.title2)
                        .fontWeight(.bold)
                                    .foregroundColor(.white)
                        .padding(.top)
                    
                    // Current Action
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Action:")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(currentAction)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.2))
                        }
                    }
                        
                    // Custom Action
                            VStack(alignment: .leading, spacing: 10) {
                        Text("Custom Action:")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                        TextField("Type your own action...", text: $customText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .foregroundColor(.black)
                        
                        Button(action: {
                            if !customText.isEmpty {
                                onSelect(customText)
                                dismiss()
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Use Custom Action")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CustomActionButtonStyle(isActive: !customText.isEmpty, isEmpty: customText.isEmpty))
                        .disabled(customText.isEmpty)
                        }
                        
                    // Preset Actions
                        VStack(alignment: .leading, spacing: 10) {
                        Text("Preset Actions:")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(basicActions, id: \.self) { action in
                        Button(action: {
                                        onSelect(action)
                                        dismiss()
                                    }) {
                                        HStack {
                                            Text(action)
                                .foregroundColor(.white)
                                                .multilineTextAlignment(.leading)
                                            
                                            Spacer()
                                            
                                            if currentAction == action {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding()
                                    }
                                    .buttonStyle(PresetActionButtonStyle(isSelected: currentAction == action))
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Select Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                .foregroundColor(.white)
        }
    }
}
    }
}
#Preview {
        ContentView()
}
