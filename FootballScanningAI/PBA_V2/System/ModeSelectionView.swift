import SwiftUI

// MARK: - Perception Mode Enum
enum PerceptionMode: String, CaseIterable {
    case findPicture = "Find the Picture"
    case playPicture = "Play the Picture"
}

// MARK: - Main View
struct ModeSelectionView: View {
    @State private var selectedMode: PerceptionMode = .findPicture

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Select Mode")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .bold()

                ForEach(PerceptionMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedMode = mode
                    }) {
                        Text(mode.rawValue)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedMode == mode ? Color.blue : Color.gray.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                Button(action: {
                    startSession()
                }) {
                    Text("Start Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
        }
    }

    // MARK: - Start Session Logic
    private func startSession() {
        print("Starting session with mode: \(selectedMode.rawValue)")
    }
}

#Preview {
    ModeSelectionView()
}
