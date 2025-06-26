import Foundation
import SwiftUI

// MARK: - Shared Types

enum BeepInterval: String, Codable, CaseIterable {
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
    case basic = "Basic Actions"
    case advanced = "Advanced Actions"
    case defensive = "Defensive Actions"
    case custom = "Custom Actions"
    
    var actions: [String] {
        switch self {
        case .basic:
            return ["Dribble forward", "Dribble left", "Dribble right", "Dribble back", "Pass left", "Pass right", "Pass forward", "Pass back", "Shoot"]
        case .advanced:
            return ["Turn left", "Turn right", "Turn", "Man on", "Cross to far post", "Through ball", "Long shot", "One-touch pass"]
        case .defensive:
            return ["Tackle", "Intercept", "Mark player", "Clear ball", "Close down", "Cover space"]
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

enum DisplayMode: String, Codable, CaseIterable {
    case colors = "Colors"
    case colorsNumbers = "Colors & Numbers"
    case colorsArrows = "Colors & Arrows"
    case numbers = "Numbers"
    case lanes = "Lanes"
    case criticalScan = "Critical Scan"
    case criticalScanArrows = "Critical Scan Arrows"
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