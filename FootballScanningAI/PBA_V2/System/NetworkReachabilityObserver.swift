//
//  NetworkReachabilityObserver.swift
//  FootballScanningAI
//
//  Observes network path; when connectivity becomes available, publishes so the app can retry Supabase sync.
//

import Foundation
import Network
import Combine

/// Publishes when the network path becomes satisfied (connectivity available). Used to retry uploading unsynced sessions.
final class NetworkReachabilityObserver: ObservableObject {
    static let shared = NetworkReachabilityObserver()

    /// Sends () when the path becomes .satisfied. Subscribe on main queue to retry sync.
    let reachableSubject = PassthroughSubject<Void, Never>()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkReachabilityObserver")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                DispatchQueue.main.async { self?.reachableSubject.send(()) }
            }
        }
        monitor.start(queue: queue)
    }
}
