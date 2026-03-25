//
//  CoachingTrainingNotificationScheduler.swift
//  FootballScanningAI
//
//  Local notifications: max one scheduled delivery window per day, coaching copy, priority handled in planner.
//

import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when coaching nudge settings change or app should reschedule (e.g. after session).
    static let coachingTrainingNudgesShouldRefresh = Notification.Name("coachingTrainingNudgesShouldRefresh")
}

enum CoachingTrainingNotificationScheduler {

    static let requestIdentifier = "com.infinitefootballscanning.coaching.daily"

    private enum Keys {
        static let lastScheduledBody = "coachingNudge.lastScheduledBody"
        static let deliveredCalendarDay = "coachingNudge.deliveredCalendarDay"
    }

    /// Call when a coaching notification is shown or opened (rate limiting).
    static func noteDeliveryForRateLimiting(_ notification: UNNotification) {
        guard notification.request.identifier == requestIdentifier else { return }
        UserDefaults.standard.set(Self.calendarDayString(Date()), forKey: Keys.deliveredCalendarDay)
    }

    /// Recomputes copy and schedules a single pending local notification (cancels prior coaching requests).
    static func refresh(
        enabled: Bool,
        playerId: UUID?,
        profile: UserProfile?,
        progressStore: ProgressStore
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

        guard enabled else { return }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            guard let plan = CoachingTrainingNotificationPlanner.makePlan(
                playerId: playerId,
                profile: profile,
                progressStore: progressStore
            ) else { return }

            let body = Self.resolvedBody(for: plan)
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = body
            content.sound = .default

            guard let trigger = Self.nextCalendarTrigger(
                progressStore: progressStore,
                playerId: playerId
            ) else { return }

            let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
            center.add(request, withCompletionHandler: nil)
            UserDefaults.standard.set(body, forKey: Keys.lastScheduledBody)
        }
    }

    static func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(true) }
            case .denied:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - Copy / variation

    /// Flow messages ship formatted bodies from the planner; performance + inactivity pick here with anti-repeat.
    private static func resolvedBody(for plan: CoachingTrainingNudgePlan) -> String {
        if !plan.body.isEmpty {
            return plan.body
        }
        let options = CoachingTrainingNotificationCopy.bodies(for: plan.kind)
        guard !options.isEmpty else { return "" }
        guard options.count > 1 else { return options[0] }
        let last = UserDefaults.standard.string(forKey: Keys.lastScheduledBody)
        let pool = options.filter { $0 != last }
        let pickFrom = pool.isEmpty ? options : pool
        let daySalt = calendarDayString(Date()).hashValue
        let idx = abs(daySalt ^ plan.kind.rawValue.hashValue) % pickFrom.count
        return pickFrom[idx]
    }

    // MARK: - When to fire (≤ 1 meaningful ping per calendar day in practice)

    private static func nextCalendarTrigger(
        progressStore: ProgressStore,
        playerId: UUID?
    ) -> UNCalendarNotificationTrigger? {
        let cal = Calendar.current
        let now = Date()
        let todayKey = calendarDayString(now)

        let deliveredDay = UserDefaults.standard.string(forKey: Keys.deliveredCalendarDay)
        let trainedToday: Bool = {
            guard let pid = playerId else { return false }
            return progressStore.sessions.contains { r in
                r.playerId == pid &&
                (r.activity == .twoMinuteTest || [.awayFromPressure, .dribbleOrPass, .oneTouchPassing].contains(r.activity)) &&
                cal.isDateInToday(r.date)
            }
        }()

        var fireDate: Date
        if deliveredDay == todayKey {
            fireDate = nextWeekdaySlot(after: now, hour: 18, minute: 30, minimumDaysAhead: 1, calendar: cal)
        } else if trainedToday {
            fireDate = nextWeekdaySlot(after: now, hour: 18, minute: 30, minimumDaysAhead: 1, calendar: cal)
        } else if let todaySlot = cal.date(bySettingHour: 18, minute: 30, second: 0, of: now), todaySlot > now {
            fireDate = todaySlot
        } else {
            fireDate = nextWeekdaySlot(after: now, hour: 18, minute: 30, minimumDaysAhead: 1, calendar: cal)
        }

        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private static func nextWeekdaySlot(
        after date: Date,
        hour: Int,
        minute: Int,
        minimumDaysAhead: Int,
        calendar: Calendar
    ) -> Date {
        var dayOffset = minimumDaysAhead
        while dayOffset < 14 {
            if let d = calendar.date(byAdding: .day, value: dayOffset, to: date),
               let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d) {
                return slot
            }
            dayOffset += 1
        }
        return date.addingTimeInterval(Double(minimumDaysAhead) * 86400)
    }

    private static func calendarDayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
