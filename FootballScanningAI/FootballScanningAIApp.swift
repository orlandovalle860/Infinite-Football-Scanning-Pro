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
    @UIApplicationDelegateAdaptor(CoachingNotificationsAppDelegate.self) private var coachingNotificationsAppDelegate
    @StateObject private var router = AppRouter()

    init() {
        // Prevent screen from dimming and lock screen from appearing while app is running
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Preload PBA training beep for low-latency playback
        PBABeepSoundManager.shared.preloadCurrent()

        #if DEBUG
        ThresholdAuditDebug.logAuditSummaryOnce()
        #endif
        
        // Additional protection for outdoor use
        setupScreenProtection()
    }
    
    private func setupScreenProtection() {
        // Set screen brightness to maximum for outdoor visibility
        UIScreen.main.brightness = 1.0
        
        // Request to keep the device awake
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Set up notification observers to re-enable protection if needed
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Re-enable protection when app becomes active
            UIApplication.shared.isIdleTimerDisabled = true
            UIScreen.main.brightness = 1.0
        }
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreen()
                .environmentObject(ConnectionManager.shared)
                .environmentObject(MultipeerManager())
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Ensure protection is active when app appears
                    UIApplication.shared.isIdleTimerDisabled = true
                    UIScreen.main.brightness = 1.0
                }
        }
    }
}
