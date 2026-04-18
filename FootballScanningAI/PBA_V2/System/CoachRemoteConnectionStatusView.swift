//
//  CoachRemoteConnectionStatusView.swift
//  FootballScanningAI
//
//  Passive partner link line on the player display (relay + Multipeer).
//

import SwiftUI

/// Displays connection status for the iPad when in partner mode.
struct CoachRemoteConnectionStatusView: View {
    var body: some View {
        PartnerLinkPassiveStatusLine(role: .display, displayPresentation: .statusBar)
    }
}
