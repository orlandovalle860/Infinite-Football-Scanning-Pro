//
//  CoachActivityChangePickerView.swift
//  FootballScanningAI
//
//  Coach remote: premium activity switcher for partner timed sessions.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CoachActivityChangePickerView: View {
    let currentActivity: ActivityKind
    let onSelect: (ActivityKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pressedActivity: ActivityKind?
    @State private var livePulse = false
    @State private var appeared = false

    private let liveTint = Color.green

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private let activities: [ActivityKind] = [
        .dribbleOrPass,
        .awayFromPressure,
        .oneTouchPassing,
        .twoMinuteTest
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            Text("Change Activity")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 10)

            currentActivityRow
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(activities, id: \.self) { activity in
                    activityTile(for: activity)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 28)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                livePulse = true
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var currentActivityRow: some View {
        HStack(spacing: 6) {
            Text(currentActivity.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                Text("●")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(liveTint)
                    .opacity(livePulse ? 1 : 0.32)
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(liveTint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityTile(for activity: ActivityKind) -> some View {
        let isCurrent = activity == currentActivity
        let isPressed = pressedActivity == activity
        let restingScale: CGFloat = isCurrent ? 1.02 : 1
        let displayScale: CGFloat = isPressed ? 0.97 : restingScale

        return Button {
            guard pressedActivity == nil else { return }
            triggerSelectionHaptic()
            withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                pressedActivity = activity
            }
            onSelect(activity)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: activity.activityPickerIcon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(isCurrent ? liveTint : .primary)
                        .symbolRenderingMode(.hierarchical)

                    Spacer(minLength: 0)

                    if isCurrent {
                        liveBadge
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(activity.activityPickerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isCurrent ? liveTint : Color.primary.opacity(0.06),
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .scaleEffect(displayScale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activity.displayName)
        .accessibilityHint(isCurrent ? "Currently live on display" : "Switch to this activity")
    }

    private var liveBadge: some View {
        HStack(spacing: 3) {
            Text("●")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(liveTint)
                .opacity(livePulse ? 1 : 0.35)
            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(liveTint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(liveTint.opacity(0.12))
        )
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

struct CoachActivitySwitchBannerView: View {
    enum Style: Equatable {
        case switched(activityName: String)
        case connectionRetrying
    }

    let style: Style

    var body: some View {
        HStack(spacing: 8) {
            switch style {
            case .switched(let name):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Switched to \(name)")
                    .font(.subheadline.weight(.semibold))
            case .connectionRetrying:
                ProgressView()
                    .controlSize(.small)
                Text("Connection issue — retrying…")
                    .font(.subheadline.weight(.medium))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        )
        .padding(.horizontal, 20)
    }
}
