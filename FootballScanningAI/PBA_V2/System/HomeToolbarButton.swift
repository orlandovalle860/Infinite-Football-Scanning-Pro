//
//  HomeToolbarButton.swift
//  FootballScanningAI
//
//  Global Home control + legacy no-op toolbar modifier (replaced by ``GlobalHomeNavigationOverlay`` on the root stack).
//

import SwiftUI

/// Top-trailing Home: clears `AppRouter` path and resets player-home local navigation via ``PopToRootTrigger``.
struct GlobalHomeNavigationOverlay: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger

    private var isPadDisplay: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// iPad field display: larger control for distance tapping; phone unchanged.
    private var homeIconPointSize: CGFloat { isPadDisplay ? 20 : 14 }
    private var homeCircleSide: CGFloat { isPadDisplay ? 52 : 36 }
    /// At least 60×60 effective hit area on iPad (visual circle stays 52, centered).
    private var homeMinimumTapSide: CGFloat { isPadDisplay ? 60 : 0 }

    /// Keeps the control clear of inline navigation titles (horizontal inset toward center).
    private var homeLeadingTitleClearance: CGFloat { isPadDisplay ? 16 : 14 }
    private var homeTopPadding: CGFloat { isPadDisplay ? 22 : 12 }
    private var homeTrailingPadding: CGFloat { isPadDisplay ? 20 : 12 }

    private var shouldShow: Bool {
        !router.path.isEmpty || popToRootTrigger.isPlayerHomeLocalNavigationActive
    }

    var body: some View {
        Group {
            if shouldShow {
                Button {
                    if popToRootTrigger.isPlayerHomeLocalNavigationActive {
                        popToRootTrigger.request = true
                    }
                    router.popToRoot(endingPartnerSession: false)
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: homeIconPointSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: homeCircleSide, height: homeCircleSide)
                        .background(Color.black.opacity(0.38))
                        .clipShape(Circle())
                        .modifier(HomeOverlayTapTargetFrame(minSide: homeMinimumTapSide))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Home")
                .padding(.top, homeTopPadding)
                .padding(.leading, homeLeadingTitleClearance)
                .padding(.trailing, homeTrailingPadding)
            }
        }
    }
}

/// Expands the button label hit area when `minSide > 0` without changing the drawn circle size.
private struct HomeOverlayTapTargetFrame: ViewModifier {
    let minSide: CGFloat

    func body(content: Content) -> some View {
        if minSide > 0 {
            content
                .frame(width: minSide, height: minSide)
                .contentShape(Rectangle())
        } else {
            content
        }
    }
}

struct PBAHomeToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func pbaHomeToolbar(router: AppRouter) -> some View {
        modifier(PBAHomeToolbarModifier())
    }
}
