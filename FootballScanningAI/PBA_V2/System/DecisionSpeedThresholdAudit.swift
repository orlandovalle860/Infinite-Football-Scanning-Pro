//
//  DecisionSpeedThresholdAudit.swift
//  FootballScanningAI
//
//  DEBUG: one-shot summary of per-rep fast/medium/slow cutoffs (single source: `TimingThresholds`).
//

import Foundation

// MARK: - DEBUG audit log (current thresholds)

#if DEBUG
enum ThresholdAuditDebug {
    private static var didLogAuditThisProcess = false

    /// Prints one `[ThresholdAudit-Debug]` block per process (DEBUG builds). Safe to call from app launch.
    static func logAuditSummaryOnce() {
        guard !didLogAuditThisProcess else { return }
        didLogAuditThisProcess = true

        let cur = currentSnapshot()

        print("[ThresholdAudit-Debug] === Per-rep decision speed thresholds (TimingThresholds) — AFP < DOP < OTP < 2MT ===")

        line("AFP", cur: cur.afp, why: """
            Tightest: rewards pre-oriented decisions; fast is strictly below 0.75s.
            """)

        line("DOP", cur: cur.dop, why: """
            One beat more than AFP; fast below 0.95s.
            """)

        line("OTP", cur: cur.otp, why: """
            Slightly more time than DOP for multi-green scan; fast below 1.05s.
            """)

        line("2MT", cur: cur.two, why: """
            Most forgiving baseline test; fast below 1.25s, medium band ends below 2.5s, slow at or above 2.5s.
            """)
    }

    private struct Snap {
        let fast: Double
        let mediumUpper: Double
    }

    private static func currentSnapshot() -> (afp: Snap, dop: Snap, otp: Snap, two: Snap) {
        (
            afp: Snap(fast: TimingThresholds.pressureFast, mediumUpper: TimingThresholds.pressureMediumUpper),
            dop: Snap(fast: TimingThresholds.dribblePassFast, mediumUpper: TimingThresholds.dribblePassMediumUpper),
            otp: Snap(fast: TimingThresholds.oneTouchFast, mediumUpper: TimingThresholds.oneTouchMediumUpper),
            two: Snap(fast: TimingThresholds.twoMinuteFast, mediumUpper: TimingThresholds.twoMinuteMediumUpper)
        )
    }

    private static func line(_ tag: String, cur: Snap, why: String) {
        let c = String(format: "fast_lt=%.2fs medium_upto=%.2fs", cur.fast, cur.mediumUpper)
        print("[ThresholdAudit-Debug] \(tag) thresholds={\(c)}")
        let trimmed = why.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        print("[ThresholdAudit-Debug] \(tag) note: \(trimmed)")
    }
}
#endif
