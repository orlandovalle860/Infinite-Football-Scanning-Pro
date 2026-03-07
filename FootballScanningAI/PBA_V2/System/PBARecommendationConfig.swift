//
//  PBARecommendationConfig.swift
//  FootballScanningAI
//
//  PBA V2 — Shared thresholds for recommendation and dashboard (level, consistency, status).
//

import Foundation
import Combine

enum PBARecommendationConfig {
    // MARK: - Decision score thresholds (0–100)
    /// Score threshold for Elite status (with steady consistency).
    static let eliteDecisionScore = 80
    /// Score threshold for Playmaker status.
    static let playmakerDecisionScore = 60
    /// Score threshold for Developing status.
    static let developingDecisionScore = 40

    // MARK: - Consistency score thresholds (0–100)
    /// Minimum consistency score for Steady label.
    static let consistencySteadyMin = 80
    /// Minimum consistency score for Improving label (below steady).
    static let consistencyImprovingMin = 60
}
