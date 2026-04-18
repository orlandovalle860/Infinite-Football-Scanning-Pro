//
//  TwoMinuteRepPlanner.swift
//  FootballScanningAI
//
//  PBA V2 — 10 reps: Up 4, Left 3, Right 2, Down 1. Shuffled, no 3-in-a-row.
//

import Foundation

enum TwoMinuteRepPlanner {
    /// When `repCount == 10`, uses the canonical Up 4 / Left 3 / Right 2 / Down 1 composition; otherwise a balanced gate sequence with no three identical gates in a row.
    static func generatePlan(forBlockSize repCount: Int) -> [RepPlan] {
        guard repCount > 0 else { return [] }
        if repCount == 10 { return generateDefaultTenRepPlan() }
        let base = Gate.allCases
        var pool: [Gate] = []
        var i = 0
        while pool.count < repCount {
            pool.append(base[i % base.count])
            i += 1
        }
        var gates = pool
        var attempts = 0
        while !noThreeIdenticalInARow(gates) && attempts < 500 {
            gates = pool.shuffled()
            attempts += 1
        }
        return gates.enumerated().map { RepPlan(repIndex: $0.offset, ballGate: $0.element) }
    }

    static func generatePlan() -> [RepPlan] {
        generateDefaultTenRepPlan()
    }

    private static func generateDefaultTenRepPlan() -> [RepPlan] {
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

    private static func noThreeIdenticalInARow(_ gates: [Gate]) -> Bool {
        guard gates.count >= 3 else { return true }
        for j in 0..<(gates.count - 2) {
            if gates[j] == gates[j + 1], gates[j + 1] == gates[j + 2] { return false }
        }
        return true
    }
}
