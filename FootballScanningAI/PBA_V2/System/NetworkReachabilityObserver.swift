//
//  NetworkReachabilityObserver.swift
//  FootballScanningAI
//
//  Observes network path; when connectivity becomes available, publishes so the app can retry Supabase sync.
//

import Foundation
import Network
import Combine

/// Publishes when the network path becomes .satisfied. Subscribe on main queue to retry sync / relay reconnect.
final class NetworkReachabilityObserver: ObservableObject {
    static let shared = NetworkReachabilityObserver()

    /// Sends () when the path becomes .satisfied (including unsatisfied → satisfied).
    let reachableSubject = PassthroughSubject<Void, Never>()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkReachabilityObserver")
    private var lastStatus: NWPath.Status?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let previous = self.lastStatus
            self.lastStatus = path.status
            // Fire on every satisfied update after a non-satisfied state, and on first satisfied.
            // Hotspot rejoin often flaps; we want an immediate poke as soon as the radio is usable again.
            let becameSatisfied = path.status == .satisfied && previous != .satisfied
            if becameSatisfied {
                DispatchQueue.main.async { self.reachableSubject.send(()) }
            }
        }
        monitor.start(queue: queue)
    }
}
