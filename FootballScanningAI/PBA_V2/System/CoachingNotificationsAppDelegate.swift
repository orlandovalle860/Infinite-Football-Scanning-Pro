//
//  CoachingNotificationsAppDelegate.swift
//  FootballScanningAI
//
//  Registers UNUserNotificationCenter delegate for coaching nudges (delivery tracking).
//

import UIKit
import UserNotifications

/// Handles presentation + tap so we can rate-limit to one coaching notification per calendar day when possible.
final class CoachingNotificationsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        CoachingTrainingNotificationScheduler.noteDeliveryForRateLimiting(notification)
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        CoachingTrainingNotificationScheduler.noteDeliveryForRateLimiting(response.notification)
        completionHandler()
    }
}
