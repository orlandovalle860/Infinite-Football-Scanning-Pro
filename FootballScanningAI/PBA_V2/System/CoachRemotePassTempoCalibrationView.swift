import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CoachRemotePassTempoCalibrationView: View {
    let sampleCount: Int
    let targetSamples: Int
    let step: PartnerPassCalibrationStep
    let canFinish: Bool
    let onTapPass: () -> Void
    let onTapArrival: () -> Void
    let onFinish: () -> Void
    var showCompletionFeedback: Bool = false

    private var completionFeedbackView: some View {
        VStack(spacing: 6) {
            Text("Nice — timing calibrated")
                .font(.headline.weight(.semibold))
                .foregroundColor(.green.opacity(0.95))
            Text("Your timing now matches your pass speed")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.86))
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Get more accurate early vs late feedback")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Takes 2–3 passes (10 seconds)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Text("Pass \(min(sampleCount + 1, targetSamples)) of \(targetSamples)")
                .font(.headline)
                .foregroundColor(.yellow)

            if step == .waitingForPass {
                Button(action: onTapPass) {
                    Text("Tap When Ball Is Passed")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onTapArrival) {
                    Text("Tap When Ball Arrives")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            if canFinish {
                Button(action: onFinish) {
                    Text("Start Session")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            if showCompletionFeedback {
                completionFeedbackView
            }
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: showCompletionFeedback)
        .onChange(of: showCompletionFeedback) { _, visible in
            guard visible else { return }
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            #endif
        }
    }
}

