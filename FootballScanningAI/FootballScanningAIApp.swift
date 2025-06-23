//
//  FootballScanningAIApp.swift
//  FootballScanningAI
//
//  Created by Valle Family Mac Mini on 6/15/25.
//

import SwiftUI
import UIKit

@main
struct FootballScanningAIApp: App {
    init() {
        // Prevent screen from dimming and lock screen from appearing while app is running
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreen()
                .preferredColorScheme(.dark)
        }
    }
}
