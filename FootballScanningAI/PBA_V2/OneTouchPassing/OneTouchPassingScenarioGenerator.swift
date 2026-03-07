//
//  OneTouchPassingScenarioGenerator.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 4: 12 reps = 4×1 green, 4×2 green, 2×3 green, 2×emergency (only DOWN green).
//

import Foundation

enum OneTouchPassingScenarioGenerator {
    static let totalReps = 12

    static func generatePlan() -> [OneTouchRepPlan] {
        let allGates: [Gate] = [.up, .down, .left, .right]
        var plans: [OneTouchRepPlan] = []

        // 4 reps: 1 green (balance across UP/LEFT/RIGHT/DOWN)
        var oneGreenCounts: [Gate: Int] = [.up: 0, .down: 0, .left: 0, .right: 0]
        for i in 0..<4 {
            let gate = pickBalanced(from: allGates, counts: oneGreenCounts)
            oneGreenCounts[gate, default: 0] += 1
            plans.append(OneTouchRepPlan(repIndex: i, greenDirections: [gate]))
        }

        // 4 reps: 2 green (rotate combinations)
        let twoGreenPairs: [[Gate]] = [
            [.up, .left], [.up, .right], [.down, .left], [.down, .right],
            [.left, .right], [.up, .down]
        ]
        for i in 0..<4 {
            let pair = twoGreenPairs[i % twoGreenPairs.count]
            plans.append(OneTouchRepPlan(repIndex: 4 + i, greenDirections: Set(pair)))
        }

        // 2 reps: 3 green (one red)
        for (idx, redGate) in [Gate.left, Gate.right].enumerated() {
            let greens = Set(Gate.allCases).subtracting([redGate])
            plans.append(OneTouchRepPlan(repIndex: 8 + idx, greenDirections: greens))
        }

        // 2 reps: emergency — only DOWN green
        plans.append(OneTouchRepPlan(repIndex: 10, greenDirections: [.down]))
        plans.append(OneTouchRepPlan(repIndex: 11, greenDirections: [.down]))

        // Shuffle with constraint: no direction green more than 3 times in a row
        var result = plans.shuffled()
        var attempts = 0
        while !validOrder(result) && attempts < 200 {
            result = plans.shuffled()
            attempts += 1
        }
        return result.enumerated().map { i, p in
            OneTouchRepPlan(repIndex: i, greenDirections: p.greenDirections)
        }
    }

    private static func pickBalanced(from gates: [Gate], counts: [Gate: Int]) -> Gate {
        let minCount = gates.map { counts[$0] ?? 0 }.min() ?? 0
        let candidates = gates.filter { (counts[$0] ?? 0) == minCount }
        return candidates.randomElement() ?? .up
    }

    private static func validOrder(_ plans: [OneTouchRepPlan]) -> Bool {
        for gate in Gate.allCases {
            var run = 0
            for p in plans {
                if p.greenDirections.contains(gate) {
                    run += 1
                    if run > 3 { return false }
                } else {
                    run = 0
                }
            }
        }
        return true
    }
}
