//
//  AnalyticsManager.swift
//  FootballScanningAI
//
//  Logs product analytics events to Supabase "events" table. Queues locally when offline and flushes when online.
//  Does not affect session recording, Supabase session sync, coach remote, or offline training.
//
//  Supabase table (run in SQL editor if not exists):
//  create table if not exists events (
//    id uuid primary key default gen_random_uuid(),
//    event_name text not null,
//    user_id uuid,
//    player_id uuid,
//    created_at timestamptz not null default now()
//  );
//  -- Optional: enable RLS and allow anon insert for app
//  alter table events enable row level security;
//  create policy "Allow anon insert" on events for insert to anon with check (true);
//

import Foundation
import UIKit
import Supabase

/// Event names for product analytics (onboarding funnel and training usage).
enum AnalyticsEventName: String {
    case appOpened = "app_opened"
    case introScreenViewed = "intro_screen_viewed"
    case twoMinuteTestStarted = "two_minute_test_started"
    case twoMinuteTestCompleted = "two_minute_test_completed"
    case accountCreated = "account_created"
    case playerCreated = "player_created"
    case trainingSessionStarted = "training_session_started"
    case trainingSessionCompleted = "training_session_completed"
}

/// One row for the Supabase `events` table. Stored in queue when offline.
private struct AnalyticsEventRow: Codable, Equatable {
    let id: String
    let event_name: String
    let user_id: String?
    let player_id: String?
    let session_id: String?
    let session_activity_id: String?
    let created_at: String

    static func make(eventName: String, userId: UUID?, playerId: UUID?, sessionId: UUID?, sessionActivityId: UUID?) -> AnalyticsEventRow {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return AnalyticsEventRow(
            id: UUID().uuidString.lowercased(),
            event_name: eventName,
            user_id: userId?.uuidString.lowercased(),
            player_id: playerId?.uuidString.lowercased(),
            session_id: sessionId?.uuidString.lowercased(),
            session_activity_id: sessionActivityId?.uuidString.lowercased(),
            created_at: iso.string(from: Date())
        )
    }
}

/// Payload for Supabase insert (snake_case for DB). Contains event_name, user_id, session_id, session_activity_id (optional), created_at.
private struct SupabaseEventRow: Encodable {
    let event_name: String
    let user_id: String?
    let session_id: String?
    let session_activity_id: String?
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case event_name, user_id, session_id, session_activity_id, created_at
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(event_name, forKey: .event_name)
        try c.encodeIfPresent(user_id, forKey: .user_id)
        try c.encodeIfPresent(session_id, forKey: .session_id)
        try c.encodeIfPresent(session_activity_id, forKey: .session_activity_id)
        try c.encodeIfPresent(created_at, forKey: .created_at)
    }
}

final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private let queueKey = "analytics_events_queue"
    private let queueLock = NSLock()

    init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushIfNeeded()
        }
    }

    // MARK: - Public API

    /// Log an event. Queues locally if offline; uploads when Supabase is configured and network is available.
    /// session_id and session_activity_id are resolved from CurrentSessionStore (display device). Coach device does not send session-linked events.
    func track(_ eventName: AnalyticsEventName, userId: UUID? = nil, playerId: UUID? = nil, sessionId: UUID? = nil, sessionActivityId: UUID? = nil) {
        let userIdResolved = userId ?? AuthManager.shared.currentUserId
        let sessionIdResolved = sessionId ?? CurrentSessionStore.shared.sessionId
        let sessionActivityIdResolved = sessionActivityId ?? CurrentSessionStore.shared.currentSessionActivityId
        let row = AnalyticsEventRow.make(
            eventName: eventName.rawValue,
            userId: userIdResolved,
            playerId: playerId,
            sessionId: sessionIdResolved,
            sessionActivityId: sessionActivityIdResolved
        )
        enqueue(row)
        flushIfNeeded()
    }

    /// Call on app launch and when network becomes available to upload queued events. Runs on host (display device) only.
    func flushIfNeeded() {
        let isHost = ConnectionManager.shared.isHost
        guard isHost, Config.isSupabaseConfigured else { return }
        let batch = peekQueue()
        guard !batch.isEmpty else { return }
        upload(batch) { [weak self] success in
            if success { self?.removeFromQueue(ids: Set(batch.map(\.id))) }
        }
    }

    // MARK: - Queue (UserDefaults)

    private func enqueue(_ row: AnalyticsEventRow) {
        queueLock.lock()
        defer { queueLock.unlock() }
        var list = loadQueue()
        list.append(row)
        saveQueue(list)
    }

    private func peekQueue() -> [AnalyticsEventRow] {
        queueLock.lock()
        defer { queueLock.unlock() }
        return loadQueue()
    }

    private func removeFromQueue(ids: Set<String>) {
        queueLock.lock()
        defer { queueLock.unlock() }
        var list = loadQueue()
        list.removeAll { ids.contains($0.id) }
        saveQueue(list)
    }

    private func loadQueue() -> [AnalyticsEventRow] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let decoded = try? JSONDecoder().decode([AnalyticsEventRow].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveQueue(_ list: [AnalyticsEventRow]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: queueKey)
        } else {
            UserDefaults.standard.removeObject(forKey: queueKey)
        }
    }

    // MARK: - Upload

    private func upload(_ rows: [AnalyticsEventRow], onComplete: @escaping (Bool) -> Void) {
        let client = SupabaseClientManager.client
        Task {
            let userIdString: String? = (try? await client.auth.session)?.user.id.uuidString.lowercased()
            do {
                let payloads = rows.map { row in
                    SupabaseEventRow(
                        event_name: row.event_name,
                        user_id: row.user_id ?? userIdString,
                        session_id: row.session_id,
                        session_activity_id: row.session_activity_id,
                        created_at: row.created_at
                    )
                }
                try await client.from("events").insert(payloads).execute()
                await MainActor.run { onComplete(true) }
            } catch {
                print("[Analytics] Upload failed (\(rows.count) event(s)): \(error)")
                await MainActor.run { onComplete(false) }
            }
        }
    }
}
