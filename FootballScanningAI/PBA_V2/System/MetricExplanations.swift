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
        case "First Touch Commitment":
            return "Measures whether your first touch immediately executes your decision."
        case "Forward Intent":
            return "Measures how often you choose a forward action when available."
        case "Early Decision Rate":
            return "Measures how often you decide before the ball reaches you."
        case "Pre-Receive Decision Rate":
            return "Measures how often you both decide early and commit with your first touch in the right direction."
        case "Decision Before Contact":
            return "Measures how often you decide before touching the ball (quick decision and first touch in the correct direction)."
        case "Status":
            return "Shows whether your overall efficiency is improving, stable, or declining over recent sessions."
        case "Decision Score":
            return "Reflects how well your recent decisions match the right option and timing."
        case "Pressure Escape Rate":
            return "Measures how effectively you handle pressure situations by choosing and executing the right escape."
        default:
            return nil
        }
    }
}
