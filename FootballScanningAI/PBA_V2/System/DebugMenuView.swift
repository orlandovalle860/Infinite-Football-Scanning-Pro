//
//  DebugMenuView.swift
//  FootballScanningAI
//
//  Tester mode: shown as a route from Home (toolbar "Tester Tools" button). Not the app root.
//

import SwiftUI
import Combine

struct DebugMenuView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            Section {
                Button("Go to Home") {
                    router.popToRoot()
                }
            } header: {
                Text("Debug")
            }
        }
        .navigationTitle("Tester Mode")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.sizeCategory, .large)
        .environment(\.colorScheme, .dark)
    }
}
