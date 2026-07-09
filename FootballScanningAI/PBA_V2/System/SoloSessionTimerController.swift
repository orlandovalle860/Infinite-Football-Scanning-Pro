//
//  SoloSessionTimerController.swift
//  FootballScanningAI
//
//  Countdown (timed) or elapsed (free) solo session clock — subtle, non-urgent.
//

import Combine
import Foundation

@MainActor
final class SoloSessionTimerController: ObservableObject {
    @Published private(set) var displayText: String = ""
    @Published private(set) var isVisible = false
    @Published private(set) var pendingEndAfterCurrentRep = false

    private var tickTimer: Timer?
    private var choice: SoloSessionDurationChoice?
    private var countdownEndDate: Date?
    private var sessionStartDate: Date?

    func start(choice: SoloSessionDurationChoice) {
        let startedAt = SoloTimeBasedSession.sessionStartedAt ?? Date()
        resume(choice: choice, sessionStartedAt: startedAt)
        pendingEndAfterCurrentRep = false
    }

    /// Continue an in-progress session clock (e.g. after switching activities).
    func resume(choice: SoloSessionDurationChoice, sessionStartedAt: Date) {
        tickTimer?.invalidate()
        tickTimer = nil
        self.choice = choice
        self.sessionStartDate = sessionStartedAt
        isVisible = true

        if let duration = choice.durationSeconds {
            countdownEndDate = sessionStartedAt.addingTimeInterval(duration)
            if Date() >= countdownEndDate! {
                pendingEndAfterCurrentRep = true
            }
        } else {
            countdownEndDate = nil
        }
        refreshDisplay()
        guard tickTimer == nil, !pendingEndAfterCurrentRep else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        choice = nil
        countdownEndDate = nil
        sessionStartDate = nil
        isVisible = false
        displayText = ""
    }

    func elapsedSeconds(now: Date = Date()) -> TimeInterval {
        guard let sessionStartDate else { return SoloTimeBasedSession.elapsedSeconds(now: now) }
        return max(0, now.timeIntervalSince(sessionStartDate))
    }

    /// Seconds left on a timed countdown; `nil` for free-play elapsed mode.
    var remainingTime: TimeInterval? {
        guard let choice, choice.isTimed, let countdownEndDate else { return nil }
        return max(0, countdownEndDate.timeIntervalSinceNow)
    }

    /// Remaining countdown for timed sessions; elapsed time for free play.
    var presentationText: String {
        guard let choice else { return displayText }
        if choice.isTimed, let remaining = remainingTime {
            return SoloSessionTimeFormat.mmss(remaining)
        }
        return SoloSessionTimeFormat.mmss(elapsedSeconds())
    }

    var sessionStartTime: Date? { sessionStartDate }

    private func tick() {
        refreshDisplay()
        guard let choice, choice.isTimed, let countdownEndDate else { return }
        if Date() >= countdownEndDate {
            pendingEndAfterCurrentRep = true
            tickTimer?.invalidate()
            tickTimer = nil
            displayText = SoloSessionTimeFormat.mmss(0)
        }
    }

    private func refreshDisplay() {
        guard let choice else {
            displayText = ""
            return
        }
        if choice.isTimed, let countdownEndDate {
            let remaining = max(0, countdownEndDate.timeIntervalSinceNow)
            displayText = SoloSessionTimeFormat.mmss(remaining)
        } else if let sessionStartDate {
            displayText = SoloSessionTimeFormat.mmss(Date().timeIntervalSince(sessionStartDate))
        }
    }
}
