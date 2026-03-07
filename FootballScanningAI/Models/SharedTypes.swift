import Foundation
import SwiftUI

// MARK: - Shared Types

enum BeepMode: String, Codable, CaseIterable {
    case range = "Range"
    case fixed = "Fixed"
}

enum BeepInterval: String, Codable, CaseIterable {
    case fast = "Fast (2-4s)"
    case medium = "Medium (5-7s)" 
    case slow = "Slow (8-10s)"
    
    var range: ClosedRange<Double> {
        switch self {
        case .fast: return 2.0...4.0
        case .medium: return 5.0...7.0
        case .slow: return 8.0...10.0
        }
    }
}

enum ScanningColorSet: String, Codable, CaseIterable {
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

enum ActionSet: String, Codable, CaseIterable {
    case basic = "Basic Ball Actions"
    case intermediate = "Intermediate Ball Actions"
    case advanced = "Advanced Ball Actions"
    case defensive = "Defensive Ball Actions"
    case attacking = "Attacking Ball Actions"
    case midfield = "Midfield Ball Actions"
    case custom = "Custom Actions"
    
    var actions: [String] {
        switch self {
        case .basic:
            return ["Dribble forward", "Dribble left", "Dribble right", "Dribble back", "Pass left", "Pass right", "Pass forward", "Pass back", "Shoot", "First touch left", "First touch right", "First touch forward", "First touch backward", "Control ball"]
        case .intermediate:
            return ["Turn left", "Turn right", "Turn", "Man on", "Cross to far post", "Through ball", "Long shot", "One-touch pass", "Lay-off pass", "Wall pass", "Overlap run", "Cut inside"]
        case .advanced:
            return ["Elastico", "Step-over", "Cruyff turn", "Maradona turn", "Scissor"]
        case .defensive:
            return ["Tackle", "Intercept", "Mark player", "Clear ball", "Close down", "Cover space", "Block shot", "Clear header"]
        case .attacking:
            return ["Shoot near post", "Shoot far post", "Chip goalkeeper", "Power shot", "Finesse shot", "Header goal", "Tap-in", "Breakaway", "1v1 finish", "Backheel shot", "Bicycle kick", "Volley finish"]
        case .midfield:
            return ["Switch play", "Through ball", "Cross-field pass", "Long diagonal", "Short triangle", "Give and go", "Overlap", "Underlap", "Box-to-box run", "Deep-lying playmaker", "Regista pass", "Trequartista"]
        case .custom:
            return ["Custom Action 1", "Custom Action 2", "Custom Action 3", "Custom Action 4"]
        }
    }
}

struct CustomAction: Codable, Identifiable {
    let id: UUID
    let number: Int
    var action: String
    var isCustom: Bool
    
    init(number: Int, action: String, isCustom: Bool) {
        self.id = UUID()
        self.number = number
        self.action = action
        self.isCustom = isCustom
    }
}

enum DisplayMode: String, Codable, CaseIterable, Hashable {
    case colors = "Colors"
    case colorsNumbers = "Colors & Numbers"
    case colorsArrows = "Colors & Arrows"
    case numbers = "Numbers"
    case lanes = "Lanes"
    case scanningGame = "Dribble or Pass"
    case pressureResponse = "Playing Away from Pressure"
    case oneTouchPassing = "One-Touch Passing"
    case fourGoalGame = "4-Goal Game"
}

// MARK: - Color Conversion Helpers
extension Color {
    static func fromHex(_ hex: String) -> Color {
        var hex = hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let intVal = Int(hex, radix: 16) else { return .white }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb = (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
        return String(format: "#%06X", rgb)
    }
}

// MARK: - Scanning Game Types

enum PlayerGender: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
}

enum TeamColor: String, Codable, CaseIterable {
    case red = "Red"
    case blue = "Blue"
    case green = "Green"
    case white = "White"
    case black = "Black"
    
    var color: Color {
        switch self {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .white: return .white
        case .black: return .black
        }
    }
}

enum Direction: String, Codable, CaseIterable {
    case top = "Top"
    case bottom = "Bottom"
    case left = "Left"
    case right = "Right"
}

enum GoalCorner: String, Codable, CaseIterable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
}

enum ImagePosition: String, Codable {
    case middleLeft = "Middle Left"
    case middleRight = "Middle Right"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
}

enum Action: String, Codable {
    case pass = "Pass"
    case dribble = "Dribble"
}

struct GamePlayer: Identifiable, Codable {
    let id: UUID
    let teamColor: TeamColor
    let direction: Direction
    let isTeammate: Bool
    let gender: PlayerGender
    
    var imageName: String {
        return "player_\(gender.rawValue.lowercased())_\(teamColor.rawValue.lowercased())_jersey"
    }
    
    init(teamColor: TeamColor, direction: Direction, isTeammate: Bool, gender: PlayerGender) {
        self.id = UUID()
        self.teamColor = teamColor
        self.direction = direction
        self.isTeammate = isTeammate
        self.gender = gender
    }
}

struct GamePosition: Identifiable, Codable {
    let id: UUID
    let direction: Direction
    let hasPlayer: Bool
    let player: GamePlayer?
    
    init(direction: Direction, player: GamePlayer? = nil) {
        self.id = UUID()
        self.direction = direction
        self.hasPlayer = player != nil
        self.player = player
    }
}

// MARK: - Pressure Response Activity Types

/// Defender behavior when receiver triggers (checks to passer).
enum PressureResponseDefenderAction: String, CaseIterable {
    case fastPressOneSide = "Fast press one side"
    case delayedPressOneSide = "Delay press one side"
    case fakeStepThenDrop = "Fake step then drop"
    case noPress = "No press"
}

enum PressureDirection: String, Codable, CaseIterable {
    case left = "Left"
    case right = "Right"
    
    var oppositeDirection: PressureDirection {
        switch self {
        case .left: return .right
        case .right: return .left
        }
    }
}

struct PressureResponsePlayer: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let teamColor: TeamColor
    let gender: PlayerGender
    let position: PressureDirection?
    
    var imageName: String {
        return "player_\(gender.rawValue.lowercased())_\(teamColor.rawValue.lowercased())_jersey"
    }
    
    init(isUser: Bool, teamColor: TeamColor, gender: PlayerGender, position: PressureDirection? = nil) {
        self.id = UUID()
        self.isUser = isUser
        self.teamColor = teamColor
        self.gender = gender
        self.position = position
    }
}

// MARK: - One-Touch Passing Activity Types

enum PassDirection: String, Codable, CaseIterable {
    case upLeft = "Up Left"
    case upRight = "Up Right"
    case left = "Left"
    case right = "Right"
    case downLeft = "Down Left"
    case downRight = "Down Right"
    
    var description: String {
        switch self {
        case .upLeft: return "Up and to the left"
        case .upRight: return "Up and to the right"
        case .left: return "Direct movement to the left"
        case .right: return "Direct movement to the right"
        case .downLeft: return "Down and to the left"
        case .downRight: return "Down and to the right"
        }
    }
}

struct OneTouchPlayer: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let isTeammate: Bool
    let teamColor: TeamColor
    let gender: PlayerGender
    
    var imageName: String {
        return "player_\(gender.rawValue.lowercased())_\(teamColor.rawValue.lowercased())_jersey"
    }
    
    init(isUser: Bool, isTeammate: Bool, teamColor: TeamColor, gender: PlayerGender) {
        self.id = UUID()
        self.isUser = isUser
        self.isTeammate = isTeammate
        self.teamColor = teamColor
        self.gender = gender
    }
} 