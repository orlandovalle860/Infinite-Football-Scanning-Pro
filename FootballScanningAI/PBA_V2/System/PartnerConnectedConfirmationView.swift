import SwiftUI

enum PartnerCalibrationTransition {
    static let connectedConfirmationDuration: TimeInterval = 0.9
}

struct PartnerConnectedConfirmationView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Connected ✓")
                .font(.title2.weight(.semibold))
                .foregroundColor(.green.opacity(0.98))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

