//
//  AwayFromPressureRepPlanner.swift
//  FootballScanningAI
//
//  PBA V2 — 12 reps: each gate 3×, shuffled, no 3 in a row.
//

import Foundation

struct AwayFromPressureRepPlan {
    let repIndex: Int
    let pressureGate: Gate
}

enum AwayFromPressureRepPlanner {
    static func generatePlan(forBlockSize repCount: Int) -> [AwayFromPressureRepPlan] {
        let full = generatePlan()
        guard repCount > 0 else { return [] }
        if repCount <= full.count {
            return Array(full.prefix(repCount)).enumerated().map { AwayFromPressureRepPlan(repIndex: $0.offset, pressureGate: $0.element.pressureGate) }
        }
        return (0..<repCount).map { i in
            let t = full[i % full.count]
            return AwayFromPressureRepPlan(repIndex: i, pressureGate: t.pressureGate)
        }
    }

    static func generatePlan() -> [AwayFromPressureRepPlan] {
        let pool: [Gate] = [.up, .up, .up, .down, .down, .down, .left, .left, .left, .right, .right, .right]
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

        return result.enumerated().map { AwayFromPressureRepPlan(repIndex: $0.offset, pressureGate: $0.element) }
    }
}
