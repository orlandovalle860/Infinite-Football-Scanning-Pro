//
//  TrainingModeSelectionView.swift
//  FootballScanningAI
//
//  PBA V2 — Choose Partner / Wall / Solo before an activity. Next destination is built from selected mode.
//

import SwiftUI

struct TrainingModeSelectionView<Next: View>: View {
    let activityTitle: String
    let nextDestination: ((TrainingMode) -> Next)?
    let onSelectMode: ((TrainingMode) -> Void)?
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var playerStore: PlayerStore
    @EnvironmentObject private var popToRootTrigger: PopToRootTrigger
    @EnvironmentObject private var router: AppRouter

    init(activityTitle: String, onSelectMode: ((TrainingMode) -> Void)? = nil, @ViewBuilder nextDestination: @escaping (TrainingMode) -> Next) {
        self.activityTitle = activityTitle
        self.onSelectMode = onSelectMode
        self.nextDestination = nextDestination
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Text("Training mode")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal)

            Text("Who triggers each rep?")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(spacing: 16) {
                ForEach(TrainingMode.allCases, id: \.self) { mode in
                    if onSelectMode != nil {
                        Button {
                            onSelectMode?(mode)
                        } label: {
                            modeRowLabel(mode: mode)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 28)
                    } else if let next = nextDestination {
                        NavigationLink(destination: next(mode)) {
                            modeRowLabel(mode: mode)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 28)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .navigationTitle(activityTitle)
        .navigationBarTitleDisplayMode(.inline)
        .pbaHomeToolbar(router: router)
    }

    private func modeRowLabel(mode: TrainingMode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: mode.systemImage)
                Text(mode.rawValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            Text(mode.shortDescription)
                .font(.footnote)
                .foregroundColor(mode == .partner ? .black.opacity(0.8) : .white.opacity(0.9))
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(mode == .partner ? .black : .white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(mode == .partner ? Color.yellow : Color.white.opacity(0.12))
        .cornerRadius(18)
    }
}
