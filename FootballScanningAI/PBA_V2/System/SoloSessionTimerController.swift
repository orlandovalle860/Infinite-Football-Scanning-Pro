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
        stop()
        self.choice = choice
        sessionStartDate = Date()
        pendingEndAfterCurrentRep = false
        isVisible = true

        if let duration = choice.durationSeconds {
            countdownEndDate = sessionStartDate!.addingTimeInterval(duration)
        } else {
            countdownEndDate = nil
        }
        refreshDisplay()
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
