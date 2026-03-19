//
//  MetricExplanations.swift
//  FootballScanningAI
//
//  PBA V2 — Short coaching-language explanations for metrics (no formulas). Shown when user taps info icon.
//

import Foundation

/// User-facing explanations for player metrics. Simple coaching language only; no formulas or internal calculations.
enum MetricExplanations {
    static func message(for metricName: String) -> String? {
        switch metricName {
        case "Scan Efficiency":
            return "Measures how efficiently you convert what you see into the correct action."
        case "Decision Speed":
            return "Measures how quickly you decide after the ball is played to you."
        case "Forward Intent":
            return "How often you choose the forward option when it is available."
        case "Early Decision Rate":
            return "Measures how often you decide before the ball reaches you."
        case "Pre-Receive Decision Rate":
            return "Measures how often you both decide early and commit with your first touch in the right direction."
        case "Status":
            return "Shows whether your overall efficiency is improving, stable, or declining over recent sessions."
        case "Decision Score":
            return "Reflects how well your recent decisions match the right option and timing."
        case "Pressure Escape Rate":
            return "Measures how effectively you handle pressure situations by choosing and executing the right escape."
        case "Correction Rate":
            return "How often your final direction differed from your first touch (final-outcome metric). Lower values indicate stronger commitment. Only shown when both first touch and exit are logged."
        default:
            return nil
        }
    }
}
