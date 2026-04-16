//
//  PassTempoCalibrationOverlay.swift
//  FootballScanningAI
//
//  Full-screen pre-session pass timing calibration (two taps per rep).
//

import SwiftUI

struct TwoMinuteCalibrationPromptView: View {
    let hasExistingCalibration: Bool
    let onStartCalibration: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 11.0 / 255.0, green: 15.0 / 255.0, blue: 26.0 / 255.0),
                    Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                Text("Quick 10-second setup")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Get more accurate early vs late feedback")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                if hasExistingCalibration {
                    Text("Optional — improves accuracy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.74))
                        .padding(.top, 4)
                }

                Spacer()

                Button(action: onStartCalibration) {
                    Text("Start Calibration")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.yellow)
                        .cornerRadius(18)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.78))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 20)
            }
        }
    }
}

struct PassTempoCalibrationScreen: View {
    let onComplete: (Double?) -> Void

    @State private var hasStarted = false
    @State private var phase: CalibrationPhase = .waitingForPass
    @State private var passTimestamp: TimeInterval?
    @State private var travelTimes: [Double] = []
    @State private var isShowingCompletion = false
    @State private var completionWorkItem: DispatchWorkItem?

    private enum CalibrationPhase {
        case waitingForPass
        case waitingForArrival
    }

    private static let minimumSamples = 2
    private static let targetSamples = 3

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 11.0 / 255.0, green: 15.0 / 255.0, blue: 26.0 / 255.0),
                    Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                if isShowingCompletion {
                    VStack(spacing: 10) {
                        Text("Nice — timing calibrated")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text("Your timing now matches your pass speed")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.84))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                    }
                    .transition(.opacity)
                } else {
                    Text("Make Timing More Accurate")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("This helps the app match your pass speed\nso timing feedback is more accurate")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)

                    VStack(spacing: 8) {
                        Text("Make 2-3 normal passes")
                        Text("\(Text("Tap").fontWeight(.semibold)) when the ball is passed")
                        Text("\(Text("Tap").fontWeight(.semibold)) again when it reaches the player")
                    }
                    .font(.title3)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                    if hasStarted {
                        VStack(spacing: 8) {
                            Text(currentInstruction)
                                .font(.headline)
                                .foregroundColor(.yellow)
                            Text("Samples: \(travelTimes.count)/\(Self.targetSamples)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                if !isShowingCompletion, hasStarted {
                    Button {
                        handleCaptureTap()
                    } label: {
                        Text(currentTapButtonTitle)
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.yellow)
                            .cornerRadius(18)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)

                    if travelTimes.count >= Self.minimumSamples {
                        Button {
                            showCompletionThenFinish()
                        } label: {
                            Text("Continue")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                } else if !isShowingCompletion {
                    Button {
                        hasStarted = true
                        phase = .waitingForPass
                        passTimestamp = nil
                        travelTimes.removeAll(keepingCapacity: true)
                    } label: {
                        Text("Start")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.yellow)
                            .cornerRadius(18)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                }

                if !isShowingCompletion {
                    Button {
                        onComplete(nil)
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)

                    Text("Takes about 10 seconds")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.62))
                        .padding(.top, 2)
                }

                Spacer(minLength: 20)
            }
        }
    }

    private var currentInstruction: String {
        switch phase {
        case .waitingForPass:
            return "Tap when the ball is passed"
        case .waitingForArrival:
            return "Tap when it reaches the player"
        }
    }

    private var currentTapButtonTitle: String {
        switch phase {
        case .waitingForPass: return "Tap Pass"
        case .waitingForArrival: return "Tap Arrival"
        }
    }

    private func handleCaptureTap() {
        let now = Date().timeIntervalSince1970
        switch phase {
        case .waitingForPass:
            passTimestamp = now
            phase = .waitingForArrival
        case .waitingForArrival:
            if let passTimestamp {
                let travelTime = now - passTimestamp
                if travelTime > 0 {
                    travelTimes.append(travelTime)
                }
            }
            self.passTimestamp = nil
            phase = .waitingForPass
            if travelTimes.count >= Self.targetSamples {
                showCompletionThenFinish()
            }
        }
    }

    private func showCompletionThenFinish() {
        guard !isShowingCompletion else { return }
        isShowingCompletion = true
        completionWorkItem?.cancel()
        let work = DispatchWorkItem {
            onComplete(calibratedAverageTravelTime)
        }
        completionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private var calibratedAverageTravelTime: Double {
        guard !travelTimes.isEmpty else { return 0 }
        return travelTimes.reduce(0, +) / Double(travelTimes.count)
    }
}

