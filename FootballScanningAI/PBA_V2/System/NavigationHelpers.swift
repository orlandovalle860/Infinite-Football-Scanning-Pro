//
//  NavigationHelpers.swift
//  FootballScanningAI
//
//  PBA V2 — Pop to root from deep in the training stack (one-tap Home).
//

import SwiftUI
import Combine

/// When set to true, the top view dismisses. That view’s parent appears and also sees the flag, so it dismisses too—cascading back to root. Root clears the flag in onAppear.
final class PopToRootTrigger: ObservableObject {
    @Published var request = false
}

/// Call from a view that has `@Environment(\.dismiss)` and `@EnvironmentObject var popToRootTrigger`. Sets the trigger so each level dismisses in turn until root.
func popToRoot(trigger: PopToRootTrigger, dismiss: DismissAction) {
    trigger.request = true
    dismiss()
}

/// Attach to any pushed view so that when pop-to-root was requested, this view dismisses when it appears (e.g. after the view above it dismissed).
func onAppearPopToRootIfRequested(trigger: PopToRootTrigger, dismiss: DismissAction) {
    if trigger.request {
        dismiss()
    }
}
