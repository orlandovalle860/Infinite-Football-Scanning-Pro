//
//  CoachInsightGenerator.swift
//  FootballScanningAI
//
//  PBA V2 — Rule-based coach insight for session summary (2 sentences max).
//

import Foundation

enum CoachInsightGenerator {
    static func coachInsight(for session: SessionResult) -> String {
        let correct = session.correctCount
        let slowCount = session.speedCounts.slow

        var sentences: [String] = []

        if correct >= 10 && slowCount <= 2 {
            sentences.append("Strong block. You recognized the best option early. Keep scanning before the pass arrives.")
        } else if correct >= 9 && slowCount >= 3 {
            sentences.append("Good decisions, but sometimes late. Focus on deciding before the ball arrives—scan earlier on the critical check.")
        } else if correct <= 7 {
            sentences.append("You're reacting after the ball arrives. Slow your feet, scan earlier, and commit to a first touch before the pass.")
        } else {
            sentences.append("Good decisions. Keep building consistency and speed.")
        }

        if let bias = session.biasDirection {
            let direction = biasDirectionLabel(bias)
            sentences.append("You're favoring the \(direction) side. Challenge yourself to scan both shoulders and use the whole field.")
        }

        // First-touch decision tips (AFP & Dribble or Pass): show at most one, by priority.
        if let toward = session.firstTouchTowardPressureCount, toward >= 3 {
            sentences.append("Your first touch is going into pressure too often.")
        } else if let hesitant = session.firstTouchHesitantCount, hesitant >= 3 {
            sentences.append("You're hesitating between options. Commit to your decision.")
        } else if (session.firstTouchMatchCount != nil && session.firstTouchMatchCount! <= 6) || (session.lateAdjustments ?? 0) >= 3 {
            sentences.append("You're correcting your touch after receiving. Decide earlier.")
        } else if let match = session.firstTouchMatchCount, match <= 7 {
            sentences.append("Your first touch is not matching your decision. Try pre-opening your hips so your first touch goes where you intended.")
        }

        return sentences.prefix(2).joined(separator: " ")
    }

    private static func biasDirectionLabel(_ gate: Gate) -> String {
        switch gate {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        }
    }
}
