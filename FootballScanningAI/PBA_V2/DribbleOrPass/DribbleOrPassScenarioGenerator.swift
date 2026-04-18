//
//  DribbleOrPassScenarioGenerator.swift
//  FootballScanningAI
//
//  PBA V2 — Activity 3: 12 reps = 4 forward dribble, 4 forward pass, 2 lateral pass, 2 lateral dribble.
//

import Foundation

enum DribbleOrPassScenarioGenerator {
    static func generatePlan() -> [DribbleOrPassRepPlan] {
        var scenarios: [DribbleOrPassRepPlan] = []

        // Forward Dribble x4: UP=open, correct=DRIBBLE UP
        for i in 0..<4 {
            scenarios.append(forwardDribble(repIndex: i))
        }
        // Forward Pass x4: UP=teammate, correct=PASS UP
        for i in 0..<4 {
            scenarios.append(forwardPass(repIndex: 4 + i))
        }
        // Lateral Pass x2 (one left, one right or random mirror)
        scenarios.append(lateralPassLeft(repIndex: 8))
        scenarios.append(lateralPassRight(repIndex: 9))
        // Lateral Dribble x2
        scenarios.append(lateralDribbleLeft(repIndex: 10))
        scenarios.append(lateralDribbleRight(repIndex: 11))

        // Shuffle with constraint: no same correct gate more than 3 times in a row
        var result = scenarios.shuffled()
        var attempts = 0
        while !validOrder(result) && attempts < 200 {
            result = scenarios.shuffled()
            attempts += 1
        }
        return result.enumerated().map { i, p in
            DribbleOrPassRepPlan(repIndex: i, up: p.up, down: p.down, left: p.left, right: p.right, expectedCorrectGate: p.expectedCorrectGate)
        }
    }

    /// Truncates the canonical 12-rep pool or cycles it when the coach requests a longer block.
    static func generatePlan(forBlockSize repCount: Int) -> [DribbleOrPassRepPlan] {
        let full = generatePlan()
        guard repCount > 0 else { return [] }
        if repCount <= full.count {
            return Array(full.prefix(repCount)).enumerated().map { idx, p in
                DribbleOrPassRepPlan(repIndex: idx, up: p.up, down: p.down, left: p.left, right: p.right, expectedCorrectGate: p.expectedCorrectGate)
            }
        }
        return (0..<repCount).map { i in
            let t = full[i % full.count]
            return DribbleOrPassRepPlan(repIndex: i, up: t.up, down: t.down, left: t.left, right: t.right, expectedCorrectGate: t.expectedCorrectGate)
        }
    }

    private static func validOrder(_ plans: [DribbleOrPassRepPlan]) -> Bool {
        var run = 0
        var last: Gate?
        for p in plans {
            if p.expectedCorrectGate == last {
                run += 1
                if run > 3 { return false }
            } else {
                run = 1
                last = p.expectedCorrectGate
            }
        }
        return true
    }

    private static func randomContent(excluding: DribbleOrPassGateContent? = nil) -> DribbleOrPassGateContent {
        let all: [DribbleOrPassGateContent] = [.opponent, .teammate, .open]
        let filtered = excluding == nil ? all : all.filter { $0 != excluding }
        return filtered.randomElement() ?? .open
    }

    private static func forwardDribble(repIndex: Int) -> DribbleOrPassRepPlan {
        DribbleOrPassRepPlan(
            repIndex: repIndex,
            up: .open,
            down: randomContent(),
            left: randomContent(),
            right: randomContent(),
            expectedCorrectGate: .up
        )
    }

    private static func forwardPass(repIndex: Int) -> DribbleOrPassRepPlan {
        DribbleOrPassRepPlan(
            repIndex: repIndex,
            up: .teammate,
            down: randomContent(),
            left: randomContent(),
            right: randomContent(),
            expectedCorrectGate: .up
        )
    }

    private static func lateralPassLeft(repIndex: Int) -> DribbleOrPassRepPlan {
        DribbleOrPassRepPlan(
            repIndex: repIndex,
            up: .opponent,
            down: randomContent(),
            left: .teammate,
            right: Bool.random() ? .open : .opponent,
            expectedCorrectGate: .left
        )
    }

    private static func lateralPassRight(repIndex: Int) -> DribbleOrPassRepPlan {
        DribbleOrPassRepPlan(
            repIndex: repIndex,
            up: .opponent,
            down: randomContent(),
            left: Bool.random() ? .open : .opponent,
            right: .teammate,
            expectedCorrectGate: .right
        )
    }

    private static func lateralDribbleLeft(repIndex: Int) -> DribbleOrPassRepPlan {
        DribbleOrPassRepPlan(
            repIndex: repIndex,
            up: .opponent,
            down: randomContent(),
            left: .open,
            right: .opponent,
            expectedCorrectGate: .left
        )
    }

    private static func lateralDribbleRight(repIndex: Int) -> DribbleOrPassRepPlan {
        DribbleOrPassRepPlan(
            repIndex: repIndex,
            up: .opponent,
            down: randomContent(),
            left: .opponent,
            right: .open,
            expectedCorrectGate: .right
        )
    }
}
