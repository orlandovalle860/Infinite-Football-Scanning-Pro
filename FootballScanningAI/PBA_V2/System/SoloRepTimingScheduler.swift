//
//  SoloRepTimingScheduler.swift
//  FootballScanningAI
//
//  Schedules solo decision-window open and synthetic pass after beep; generation-based cancel.
//

import Foundation

@MainActor
final class SoloRepTimingScheduler {
    private var generation = UUID()

    func cancelAll() {
        generation = UUID()
    }

    func scheduleRep(
        timing: SoloRepTiming,
        repIndex: Int,
        onDecisionOpen: @escaping (Int) -> Void,
        onSyntheticPass: @escaping (Int) -> Void
    ) {
        let currentGen = generation

        DispatchQueue.main.asyncAfter(deadline: .now() + timing.decisionStart) { [weak self] in
            guard let self else { return }
            guard currentGen == self.generation else { return }
            onDecisionOpen(repIndex)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timing.returnTime) { [weak self] in
            guard let self else { return }
            guard currentGen == self.generation else { return }
            onSyntheticPass(repIndex)
        }
    }
}
