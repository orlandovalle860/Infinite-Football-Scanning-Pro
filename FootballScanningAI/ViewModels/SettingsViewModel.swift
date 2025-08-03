import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    @AppStorage("criticalScanDelay") var criticalScanDelay: Double = 0.5
    @AppStorage("criticalScanDuration") var criticalScanDuration: Double = 1.0
    @AppStorage("criticalScanResetTime") var criticalScanResetTime: Double = 5.0
    @AppStorage("teammateSpeedLevel") var teammateSpeedLevel: String = "medium"
    @AppStorage("opponentSpeedLevel") var opponentSpeedLevel: String = "medium"
    @AppStorage("trainingPerspective") var trainingPerspective: String = "back"
    @AppStorage("screenProtectionEnabled") var screenProtectionEnabled: Bool = true
    @AppStorage("soundEnabled") var soundEnabled: Bool = true
    @AppStorage("selectedActionSet") var selectedActionSetRaw: String = "basic"
    @AppStorage("selectedColorSet") var selectedColorSetRaw: String = "standard"
    
    // Computed property to get the actual duration based on speed level
    var teammateMovementDuration: Double {
        switch teammateSpeedLevel {
        case "slow":
            return 1.5 // Current speed (slower)
        case "fast":
            return 0.75 // Faster than medium
        default: // medium
            return 1.0 // Current speed
        }
    }
    
    // Computed property to get the opponent movement duration based on speed level
    var opponentMovementDuration: Double {
        switch opponentSpeedLevel {
        case "slow":
            return 2.0 // Slower movement
        case "fast":
            return 1.0 // Faster movement
        default: // medium
            return 1.5 // Current speed
        }
    }
    
    var selectedActionSet: ActionSet {
        get { ActionSet(rawValue: selectedActionSetRaw) ?? .basic }
        set { 
            selectedActionSetRaw = newValue.rawValue
            objectWillChange.send()
        }
    }
    
    var selectedColorSet: ScanningColorSet {
        get { ScanningColorSet(rawValue: selectedColorSetRaw) ?? .standard }
        set { 
            selectedColorSetRaw = newValue.rawValue
            objectWillChange.send()
        }
    }
    
    @Published var customActions: [CustomAction] = [
        CustomAction(number: 1, action: "Action", isCustom: false),
        CustomAction(number: 2, action: "Action", isCustom: false),
        CustomAction(number: 3, action: "Action", isCustom: false),
        CustomAction(number: 4, action: "Action", isCustom: false),
        CustomAction(number: 5, action: "Action", isCustom: false),
        CustomAction(number: 6, action: "Action", isCustom: false),
        CustomAction(number: 7, action: "Action", isCustom: false),
        CustomAction(number: 8, action: "Action", isCustom: false)
    ]
    
    init() {
        loadCustomActions()
    }
    
    // MARK: - Custom Actions Management
    
    func updateCustomAction(number: Int, action: String, isCustom: Bool) {
        if let index = customActions.firstIndex(where: { $0.number == number }) {
            customActions[index].action = action
            customActions[index].isCustom = isCustom
            saveCustomActions()
        }
    }
    
    private func loadCustomActions() {
        for i in 1...8 {
            let action = UserDefaults.standard.string(forKey: "customAction_\(i)") ?? "Action"
            let isCustom = UserDefaults.standard.bool(forKey: "customAction_\(i)_isCustom")
            
            if let index = customActions.firstIndex(where: { $0.number == i }) {
                customActions[index].action = action
                customActions[index].isCustom = isCustom
            }
        }
    }
    
    private func saveCustomActions() {
        for action in customActions {
            UserDefaults.standard.set(action.action, forKey: "customAction_\(action.number)")
            UserDefaults.standard.set(action.isCustom, forKey: "customAction_\(action.number)_isCustom")
        }
    }
    
    func resetToDefaults() {
        criticalScanDelay = 0.5
        criticalScanDuration = 1.0
        criticalScanResetTime = 5.0
        teammateSpeedLevel = "medium"
        opponentSpeedLevel = "medium"
        screenProtectionEnabled = true
        soundEnabled = true
        selectedActionSet = .basic
        selectedColorSet = .standard
        
        customActions = [
            CustomAction(number: 1, action: "Action", isCustom: false),
            CustomAction(number: 2, action: "Action", isCustom: false),
            CustomAction(number: 3, action: "Action", isCustom: false),
            CustomAction(number: 4, action: "Action", isCustom: false),
            CustomAction(number: 5, action: "Action", isCustom: false),
            CustomAction(number: 6, action: "Action", isCustom: false),
            CustomAction(number: 7, action: "Action", isCustom: false),
            CustomAction(number: 8, action: "Action", isCustom: false)
        ]
        
        saveCustomActions()
    }
} 