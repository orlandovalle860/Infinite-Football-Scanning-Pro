//
//  SoloSessionSummaryView.swift
//  FootballScanningAI
//
//  Text-only session complete for Solo mode — no scores, timing breakdowns, or derived metrics in the UI.
//

import SwiftUI

struct SoloSessionSummaryView: View {
    private let focusText: String
    private let nextText: String
    private let recalibrationRoute: AppRoute
    let onRunItBack: () -> Void
    let onDone: () -> Void

    @EnvironmentObject private var router: AppRouter

    init(
        passTempo: PassTempo,
        recalibrationRoute: AppRoute,
        onRunItBack: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.recalibrationRoute = recalibrationRoute
        self.onRunItBack = onRunItBack
        self.onDone = onDone
        let tempo = SoloTempo(passTempo: passTempo)
        let type = resolveSoloFeedbackType(tempo: tempo)
        let feedback = soloFeedback(for: type)
        let focus = pickNonRepeating(from: feedback.focusOptions, last: SoloFeedbackLastPhraseMemory.lastFocus)
        let next = pickNonRepeating(from: feedback.nextOptions, last: SoloFeedbackLastPhraseMemory.lastNext)
        SoloFeedbackLastPhraseMemory.lastFocus = focus
        SoloFeedbackLastPhraseMemory.lastNext = next
        self.focusText = focus
        self.nextText = next
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Session Complete")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Focus")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))

                    Text(focusText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 6) {
                    Text("Next")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))

                    Text(nextText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 12) {
                Button("Run It Back") {
                    onRunItBack()
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundColor(.black)

                Button("Recalibrate") {
                    UserDefaults.standard.removeObject(forKey: AppStorageKeys.soloReturnTime)
                    router.replace(with: recalibrationRoute)
                }
                .foregroundColor(.secondary)

                Button("Done") {
                    onDone()
                }
                .foregroundColor(.white.opacity(0.55))

                Text("Adjust timing if needed")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.12))
    }
}
