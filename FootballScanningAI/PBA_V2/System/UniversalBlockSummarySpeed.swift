//
//  UniversalBlockSummarySpeed.swift
//  FootballScanningAI
//
//  Single user-facing rule for block-level decision speed headlines: dominant bucket (most common
//  fast/medium/slow). Tie-break: choose the worse bucket (slow > medium > fast). Average raw delta
//  is kept for analytics elsewhere, not for headline classification.
//

import Foundation
import SwiftUI

/// User-facing rep-bucket breakdown line (matches universal headline counts; no separate rules).
enum BlockSummarySpeedCountsFormatting {
    /// Example: `"7 fast • 2 medium • 1 slow"`
    static func summaryLine(fast: Int, medium: Int, slow: Int) -> String {
        "\(fast) fast • \(medium) medium • \(slow) slow"
    }
}

#if DEBUG
enum SummaryCountsLineDebugLog {
    static func log(activity: ActivityKind, fast: Int, medium: Int, slow: Int, renderedLine: String) {
        print("[SummaryCountsLine-Debug] activity=\(activity.rawValue) fastCount=\(fast) mediumCount=\(medium) slowCount=\(slow) renderedSummaryLine=\(renderedLine)")
    }
}
#endif

/// Small secondary line under a Fast/Medium/Slow headline; keeps tight vertical spacing.
struct BlockSummarySpeedCountsSubline: View {
    let fast: Int
    let medium: Int
    let slow: Int
    var foregroundColor: Color = Color.white.opacity(0.55)
    var textAlignment: TextAlignment = .center
    /// When set, logs once on appear (DEBUG).
    var debugActivity: ActivityKind? = nil

    var body: some View {
        let line = BlockSummarySpeedCountsFormatting.summaryLine(fast: fast, medium: medium, slow: slow)
        Text(line)
            .font(.caption)
            .foregroundColor(foregroundColor)
            .multilineTextAlignment(textAlignment)
            .onAppear {
                #if DEBUG
                if let a = debugActivity {
                    SummaryCountsLineDebugLog.log(activity: a, fast: fast, medium: medium, slow: slow, renderedLine: line)
                }
                #endif
            }
    }
}

enum UniversalBlockSummaryHeadline {
    struct Resolution: Sendable {
        let bucket: SpeedBucket
        /// True when two or more buckets shared the max count and the worse bucket was chosen.
        let tieBreakApplied: Bool
    }

    /// Dominant bucket from per-rep counts. If all counts are zero, returns `.medium`.
    /// Tie-break: among buckets tied for the highest count, pick the **worse** speed (slow beats medium beats fast).
    static func resolve(fast: Int, medium: Int, slow: Int) -> Resolution {
        let total = fast + medium + slow
        guard total > 0 else {
            return Resolution(bucket: .medium, tieBreakApplied: false)
        }
        let maxC = max(fast, medium, slow)
        var tied: [SpeedBucket] = []
        if fast == maxC { tied.append(.fast) }
        if medium == maxC { tied.append(.medium) }
        if slow == maxC { tied.append(.slow) }
        if tied.count == 1 {
            return Resolution(bucket: tied[0], tieBreakApplied: false)
        }
        if tied.contains(.slow) {
            return Resolution(bucket: .slow, tieBreakApplied: true)
        }
        if tied.contains(.medium) {
            return Resolution(bucket: .medium, tieBreakApplied: true)
        }
        return Resolution(bucket: .fast, tieBreakApplied: true)
    }

    /// English label for the dominant bucket (Fast / Medium / Slow).
    static func headlineLabel(fast: Int, medium: Int, slow: Int) -> String {
        resolve(fast: fast, medium: medium, slow: slow).bucket.rawValue.capitalized
    }

    /// Coaching line from rep-level fast/medium/slow counts (same dominant-bucket rules as ``resolve``).
    /// Tie → "inconsistent"; otherwise maps dominant bucket to pocket-moment feedback.
    static func pocketMomentInterpretationLine(fast: Int, medium: Int, slow: Int) -> String {
        let res = resolve(fast: fast, medium: medium, slow: slow)
        if res.tieBreakApplied {
            return "Your pocket moments are inconsistent."
        }
        switch res.bucket {
        case .fast:
            return "You're winning your pocket moments."
        case .medium:
            return "You're seeing the pocket, but deciding late."
        case .slow:
            return "You're reacting after the pocket moment."
        }
    }
}

#if DEBUG
enum UniversalSummaryBucketDebugLog {
    /// One line per completed block / results screen — use when saving or presenting summary.
    static func log(
        activity: ActivityKind,
        perRepBucketLabels: [String],
        fast: Int,
        medium: Int,
        slow: Int,
        avgRawDeltaSeconds: Double?,
        headline: SpeedBucket,
        tieBreakApplied: Bool
    ) {
        let tie = tieBreakApplied ? "worse_wins_among_tied" : "none"
        let avgStr = avgRawDeltaSeconds.map { String(format: "%.4f", $0) } ?? "nil"
        let repList = perRepBucketLabels.joined(separator: ",")
        print("[UniversalSummaryBucket-Debug] activity=\(activity.rawValue) perRepBuckets=[\(repList)] fast=\(fast) medium=\(medium) slow=\(slow) avgRawDeltaSeconds=\(avgStr) dominantHeadline=\(headline.rawValue) tieBreak=\(tie)")
    }
}
#endif
