//
//  DebugMenuView.swift
//  FootballScanningAI
//
//  Shown when AppConfig.testerMode is true. Entry point for testers before the main app.
//

import SwiftUI
import Combine

struct DebugMenuView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @StateObject private var router = AppRouter()
    @State private var mainStackId = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Go to App") {
                        MainAppView(profileManager: profileManager, settingsViewModel: settingsViewModel, stackId: $mainStackId, onPopToRoot: { DispatchQueue.main.async { mainStackId = UUID() } }, router: router)
                            .id(mainStackId)
                    }
                } header: {
                    Text("Debug")
                }
            }
            .navigationTitle("Tester Mode")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.sizeCategory, .large)
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .requestPopToRoot).receive(on: RunLoop.main)) { _ in
            mainStackId = UUID()
        }
    }
}
