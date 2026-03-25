//
//  HomeToolbarButton.swift
//  FootballScanningAI
//
//  Shared Home toolbar action for deep PBA flows.
//

import SwiftUI

struct PBAHomeToolbarModifier: ViewModifier {
    @ObservedObject var router: AppRouter

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.popToRoot()
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .accessibilityLabel("Home")
                }
            }
    }
}

extension View {
    func pbaHomeToolbar(router: AppRouter) -> some View {
        modifier(PBAHomeToolbarModifier(router: router))
    }
}
