//
//  CoachRepFlowDecoupling.swift
//  FootballScanningAI
//
//  Coach-driven rep progression: next rep is triggered only by coach tap,
//  not by swipe / direction logging. Logging remains optional and non-blocking.
//

import Foundation

enum CoachRepFlowDecoupling {
    /// Coach may send `nextRep` without waiting for swipe logging to finish.
    static func maySendNextRep(blockComplete: Bool) -> Bool {
        !blockComplete
    }

    /// Rep index to attach to an optional late direction log after PASS.
    static func pendingLogRepIndex(afterPassFor repIndex: Int) -> Int {
        repIndex
    }

    static func mayLogDirectionForRep(pendingLogRepIndex: Int?, loggingRepIndex: Int?, repIndex: Int) -> Bool {
        pendingLogRepIndex == repIndex || loggingRepIndex == repIndex
    }
}

// MARK: - Coach tap input guard (survives CoachSessionView `.id` resets)

/// Debounces coach **start-rep** taps. Stored outside SwiftUI `@State` so
/// `resetCoachSessionInput()` does not clear the cooldown after PASS.
enum CoachTapInputGuard {
    static let minimumStartRepInterval: TimeInterval = 0.65

    private static var lastPassTapAt: Date = .distantPast
    private static var lastAcceptedStartRepTapAt: Date = .distantPast

    /// Block starting the next rep too soon after PASS or accidental double-start.
    static func mayStartNextRep(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastPassTapAt) > minimumStartRepInterval
            && now.timeIntervalSince(lastAcceptedStartRepTapAt) > minimumStartRepInterval
    }

    static func recordPassTap(at now: Date = Date()) {
        lastPassTapAt = now
    }

    static func recordAcceptedStartRepTap(at now: Date = Date()) {
        lastAcceptedStartRepTapAt = now
    }
}

extension RepStateController {
    /// Accept coach `nextRep` even when UI rep state is mid-cycle (coach owns flow).
    func acceptIncomingNextRepAllowingCoachOverride() -> Bool {
        if state != .idle {
            completeRepCycleEnd()
        }
        return acceptIncomingNextRep()
    }
}
