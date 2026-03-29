//
//  AppConfig.swift
//  FootballScanningAI
//
//  Global configuration. `testerMode` is DEBUG-only so TestFlight / App Store Release never see tester UI or forced unlocks.
//

import Foundation

struct AppConfig {
    /// When true: Home shows "Tester Tools" and Path unlocks all activities (`ProgressStore.isUnlocked`).
    ///
    /// **Release / TestFlight:** always `false` (no tester UI).
    ///
    /// **Debug builds (Run from Xcode to a device):** defaults to `false` so behavior matches TestFlight
    /// unless you opt in. Xcode normally uses the **Debug** configuration, which still defines `DEBUG`;
    /// we do **not** auto-enable tester mode there, or the Tester Tools button would reappear on every
    /// device run while `AppConfig` used to force `testerMode == true` in `#if DEBUG`.
    ///
    /// Set `enableTesterToolsInDebugBuilds` to `true` only while you need Tester Tools or full Path unlock locally.
    #if DEBUG
    private static let enableTesterToolsInDebugBuilds = false
    static var testerMode: Bool { enableTesterToolsInDebugBuilds }
    #else
    static var testerMode: Bool { false }
    #endif
}
