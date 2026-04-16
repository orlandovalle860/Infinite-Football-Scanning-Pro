//
//  ChartMetricDescriptions.swift
//  FootballScanningAI
//
//  One-line, player-friendly graph hints (no formulas). Shown under charts on Home / Player Dashboard.
//

import Foundation

enum ChartMetricDescriptions {
    static let correctFirstDecisionTrend = "Higher = more correct first decisions"
    static let correctDecisionTrend = "Higher = more correct decisions"
    /// Seconds chart: earlier cue-to-decision = more buffer before expected arrival.
    static let decisionTiming = "Earlier = you decide before expected arrival (relative to pass tempo)"
    static let balancedScanTrend = "Higher = faster and more accurate decisions"
    static let forwardThinking = "Higher = choosing forward options more often"
}
