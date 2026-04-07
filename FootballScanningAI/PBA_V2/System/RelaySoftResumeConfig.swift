//
//  RelaySoftResumeConfig.swift
//  FootballScanningAI
//
//  Tunable grace window for brief relay interruptions (background / transient socket loss).
//

import Foundation

enum RelaySoftResumeConfig {
    /// If the app returns and reconnects within this window, we attempt **soft resume** (no rejoin unless validation fails).
    /// Adjust without changing call sites.
    static var interruptionGraceSeconds: TimeInterval = 12
}
