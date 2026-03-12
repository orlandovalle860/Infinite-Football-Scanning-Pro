//
//  TwoMinuteRepPlanner.swift
//  FootballScanningAI
//
//  PBA V2 — 10 reps: Up 4, Left 3, Right 2, Down 1. Shuffled, no 3-in-a-row.
//

import Foundation

enum TwoMinuteRepPlanner {
    static func generatePlan() -> [RepPlan] {
        let counts: [Gate: Int] = [
            .up: 4,
            .left: 3,
            .right: 2,
            .down: 1
        ]
        var pool: [Gate] = []
        for (gate, count) in counts {
            pool.append(contentsOf: Array(repeating: gate, count: count))
        }
        assert(pool.count == 10)

        var result: [Gate] = []
        var attempts = 0
        let maxAttempts = 500

        func shuffleValid() -> Bool {
            result = pool.shuffled()
            for i in 0..<(result.count - 2) {
                let a = result[i], b = result[i + 1], c = result[i + 2]
                if a == b && b == c { return false }
            }
            return true
        }

        while !shuffleValid() && attempts < maxAttempts { attempts += 1 }
        if attempts >= maxAttempts { result = pool.shuffled() }

        return result.enumerated().map { RepPlan(repIndex: $0.offset, ballGate: $0.element) }
    }
}
