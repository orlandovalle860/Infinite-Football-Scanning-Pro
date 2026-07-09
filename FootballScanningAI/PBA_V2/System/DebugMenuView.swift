//
//  DebugMenuView.swift
//  FootballScanningAI
//
//  Tester Tools: DEBUG-only. Route from Home toolbar; includes PBA beep A/B selector. Stripped from Release/TestFlight.
//

#if DEBUG

import SwiftUI
import Combine
import AVFoundation

struct DebugMenuView: View {
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @AppStorage(PBABeepSoundManager.selectedBeepStorageKey) private var selectedBeepSound: String = PBABeepSoundManager.defaultSelectedBeepRawValue

    var body: some View {
        List {
            Section {
                Button("Go to Home") {
                    router.popToRoot()
                }
            } header: {
                Text("Debug")
            }

            Section {
                Button("Reset to First-Time User", role: .destructive) {
                    DebugFirstTimeUserReset.resetToFirstTimeUser(
                        profileManager: profileManager,
                        playerStore: playerStore,
                        progressStore: progressStore,
                        router: router
                    )
                }
            } footer: {
                Text("Clears local onboarding, sessions, calibration, streaks, and profiles. DEBUG only.")
            }

            Section {
                Picker("Beep sound", selection: $selectedBeepSound) {
                    ForEach(PBABeepVariant.allCases, id: \.rawValue) { variant in
                        Text(variant.label).tag(variant.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedBeepSound) { _, newValue in
                    if let v = PBABeepVariant(rawValue: newValue) {
                        PBABeepSoundManager.shared.preload(variant: v)
                    }
                }
                Button("Test Beep") {
                    PBABeepSoundManager.shared.activateSessionIfNeeded()
                    PBABeepSoundManager.shared.play(soundEnabled: true)
                }
                Text("Test each beep during real training. Choose the one that: makes players react fastest, is easiest to hear outdoors, and does not become annoying after repetition.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Training beep (A/B test)")
            } footer: {
                Text("Temporary testing. Selection saved; switch without rebuilding.")
            }
        }
        .navigationTitle("Tester Mode")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.sizeCategory, .large)
        .environment(\.colorScheme, .dark)
        .onAppear {
            PBABeepSoundManager.shared.preloadCurrent()
        }
    }
}

#endif
