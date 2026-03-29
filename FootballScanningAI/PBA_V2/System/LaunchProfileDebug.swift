//
//  LaunchProfileDebug.swift
//  FootballScanningAI
//
//  Targeted launch / profile routing logs (prefix: [LaunchProfile-Debug]).
//

import Foundation

enum LaunchProfileDebug {
    static func log(_ message: String) {
        print("[LaunchProfile-Debug] \(message)")
    }
}
