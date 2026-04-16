import SwiftUI

struct CoachCalibrationDecisionView: View {
    let hasPreviousCalibration: Bool
    let onStartCalibration: () -> Void
    let onSkip: () -> Void

    private var recommendationText: String {
        hasPreviousCalibration ? "Optional — improves accuracy" : "Recommended before first session"
    }

    private var lastCalibratedText: String? {
        guard hasPreviousCalibration else { return nil }
        guard let relative = PartnerPassTempoCalibrationStore.lastCalibratedLabel() else { return nil }
        return "Last calibrated: \(relative)"
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Ready to Train")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            Text("Calibrate timing for more accurate feedback")
                .font(.headline)
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.center)

            Text("Takes 2–3 passes (10 seconds)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.78))
                .multilineTextAlignment(.center)

            Text(recommendationText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.yellow.opacity(0.95))
                .multilineTextAlignment(.center)

            if let lastCalibratedText {
                Text(lastCalibratedText)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
            }

            Button(action: onStartCalibration) {
                Text("Start Calibration")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Button(action: onSkip) {
                VStack(spacing: 2) {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.92))
                    Text("You can always calibrate later")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.62))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
}
