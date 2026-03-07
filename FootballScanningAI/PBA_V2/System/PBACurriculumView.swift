//
//  PBACurriculumView.swift
//  FootballScanningAI
//
//  PBA V2 — SCREEN 9 CURRICULUM VIEW. Perception Training Path: 3 activities.
//  Row-based layout: each row = ladder segment (dot + connectors) + activity card. No single long vertical line.
//

import SwiftUI

struct PBACurriculumView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var profileManager: UserProfileManager
    @ObservedObject var progressStore: ProgressStore
    @ObservedObject var playerStore: PlayerStore
    @ObservedObject var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(settingsViewModel: SettingsViewModel, profileManager: UserProfileManager, progressStore: ProgressStore, playerStore: PlayerStore, popToRootTrigger: PopToRootTrigger) {
        self.settingsViewModel = settingsViewModel
        self.profileManager = profileManager
        self.progressStore = progressStore
        self.playerStore = playerStore
        self.popToRootTrigger = popToRootTrigger
        #if DEBUG
        print("[PBACurriculumView] init (router from environment)")
        #endif
    }

    private static let activities: [(title: String, subtitle: String, activity: ActivityKind)] = [
        ("Playing Away From Pressure", "Read danger and escape.", .awayFromPressure),
        ("Dribble or Pass", "Choose action under pressure.", .dribbleOrPass),
        ("One-Touch Passing", "Decide before the ball arrives.", .oneTouchPassing)
    ]

    private let pathLineColor = Color.gray.opacity(0.58)
    private let pathLineWidth: CGFloat = 2.5
    private let ladderColumnWidth: CGFloat = 32
    private let connectorHeight: CGFloat = 28
    private var cardMaxWidth: CGFloat { horizontalSizeClass == .regular ? 820 : 700 }
    private let cardMinHeight: CGFloat = 150
    private let ladderToCardSpacing: CGFloat = 12
    private let circleSize: CGFloat = 18
    private let circleStrokeWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Perception Training Path")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, ladderColumnWidth + ladderToCardSpacing)

                    curriculumRow(index: 0, title: "Playing Away From Pressure", subtitle: "Read danger and escape.", route: .awayFromPressureRoleSelection)
                    curriculumRow(index: 1, title: "Dribble or Pass", subtitle: "Choose action under pressure.", route: .dribbleOrPassRoleSelection)
                    curriculumRow(index: 2, title: "One-Touch Passing", subtitle: "Decide before the ball arrives.", route: .oneTouchPassingRoleSelection)
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .navigationTitle("Path")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house.fill")
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear {
            onAppearPopToRootIfRequested(trigger: popToRootTrigger, dismiss: dismiss)
        }
    }

    /// One row: ladder segment (left) + activity card (right). HStack(alignment: .center) so dot aligns with card center.
    private func curriculumRow(index: Int, title: String, subtitle: String, route: AppRoute) -> some View {
        HStack(alignment: .center, spacing: ladderToCardSpacing) {
            ladderSegmentForRow(index: index)
            activityCard(title: title, subtitle: subtitle, route: route)
        }
        .frame(maxWidth: cardMaxWidth, alignment: .leading)
    }

    /// This row's ladder segment only: optional top line, circle, optional bottom line. Fixed heights so no shared long line.
    private func ladderSegmentForRow(index: Int) -> some View {
        let hasTopLine = index > 0
        let hasBottomLine = index < Self.activities.count - 1
        let isCurrent = index == 0

        return VStack(spacing: 0) {
            if hasTopLine {
                Rectangle()
                    .fill(pathLineColor)
                    .frame(width: pathLineWidth, height: connectorHeight)
            } else {
                Color.clear
                    .frame(width: pathLineWidth, height: connectorHeight)
            }

            Group {
                if isCurrent {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: circleSize, height: circleSize)
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.9), lineWidth: circleStrokeWidth)
                        .frame(width: circleSize, height: circleSize)
                }
            }

            if hasBottomLine {
                Rectangle()
                    .fill(pathLineColor)
                    .frame(width: pathLineWidth, height: connectorHeight)
            } else {
                Color.clear
                    .frame(width: pathLineWidth, height: connectorHeight)
            }
        }
        .frame(width: ladderColumnWidth)
    }

    /// Card: dark rounded rect, title, subtitle, large yellow Train button (NavigationLink so path updates correctly). minHeight 150, padding 24.
    private func activityCard(title: String, subtitle: String, route: AppRoute) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
            NavigationLink(value: route) {
                Text("Train")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .cornerRadius(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .cornerRadius(18)
    }
}
