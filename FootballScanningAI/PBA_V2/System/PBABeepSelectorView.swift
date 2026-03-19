//
//  PBABeepSelectorView.swift
//  FootballScanningAI
//
//  Reusable A/B test selector for PBA training beep: pick A/B/C/D, Test Beep, and testing checklist.
//

import SwiftUI
import AVFoundation

struct PBABeepSelectorView: View {
    @AppStorage(PBABeepSoundManager.selectedBeepStorageKey) private var selectedBeepSound: String = "A"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                } header: {
                    Text("Sound")
                }
                Section {
                    Text("Test each beep during real training. Choose the one that: makes players react fastest, is easiest to hear outdoors, and does not become annoying after repetition.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Testing note")
                }
            }
            .navigationTitle("Training Beep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                PBABeepSoundManager.shared.preloadCurrent()
            }
        }
    }
}
