import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum SwipeDirection: String {
    case up = "Forward"
    case down = "Back"
    case left = "Left"
    case right = "Right"
}

extension SwipeDirection {
    var gate: Gate {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

enum SessionPhase {
    case idle
    case waitingForNextRep
    case waitingBeep
    case waitingPass
    case logging
}

struct CoachSessionView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: PerceptionMode
    let totalReps: Int
    let preBeepDelayRange: ClosedRange<Double>
    let onRepStarted: ((Int) -> Void)?
    let onPassTriggered: ((Int) -> Void)?
    let onDirectionLogged: ((Int, SwipeDirection) -> Void)?

    @State private var phase: SessionPhase = .idle
    @State private var repIndex: Int = 1
    @State private var lastDirection: SwipeDirection? = nil
    @State private var preBeepWorkItem: DispatchWorkItem?
    @State private var beepTime: Date?
    @State private var lastTapTime: TimeInterval = 0
    private let tapDebounceInterval: TimeInterval = 0.15
    @State private var passSentForRep: Set<Int> = []
    @State private var inputLocked = false

    init(
        mode: PerceptionMode,
        totalReps: Int = 12,
        preBeepDelayRange: ClosedRange<Double> = 0.0...0.0,
        onRepStarted: ((Int) -> Void)? = nil,
        onPassTriggered: ((Int) -> Void)? = nil,
        onDirectionLogged: ((Int, SwipeDirection) -> Void)? = nil
    ) {
        self.mode = mode
        self.totalReps = totalReps
        self.preBeepDelayRange = preBeepDelayRange
        self.onRepStarted = onRepStarted
        self.onPassTriggered = onPassTriggered
        self.onDirectionLogged = onDirectionLogged
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
                // Top info
                HStack {
                    Text("Rep \(repIndex) of \(totalReps)")
                        .foregroundColor(.white)
                        .font(.headline)

                    Spacer()

                    Text(mode.rawValue)
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
                .padding()

                Spacer()

                Text(statusText)
                    .foregroundColor(.white.opacity(0.25))
                    .font(.title)
                    .bold()

                // Direction feedback
                if let direction = lastDirection {
                    Text(direction.rawValue)
                        .font(.largeTitle)
                        .foregroundColor(.green)
                        .padding(.top, 8)
                }

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    handleSwipe(value)
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    handleTap()
                }
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    dismiss()
                }
                .zIndex(10)
            }
        }
        .background(DisableSwipeBack())
    }

    private var statusText: String {
        switch phase {
        case .idle, .waitingForNextRep: return "TAP TO START"
        case .waitingBeep: return "WAIT..."
        case .waitingPass: return "PASS (TAP)"
        case .logging: return "SWIPE NOW"
        }
    }

    private func handleTap() {
        guard !inputLocked else { return }
        let now = Date().timeIntervalSince1970
        if (now - lastTapTime) <= tapDebounceInterval {
            print("[INPUT-GUARD] Tap debounced")
            return
        }
        lastTapTime = now

        switch phase {
        case .idle, .waitingForNextRep:
            print("[INPUT] Start next rep")
            startRep()
        case .waitingPass:
            let currentRep = repIndex - 1
            guard !passSentForRep.contains(currentRep) else {
                print("[INPUT-GUARD] Duplicate pass ignored for rep \(currentRep)")
                return
            }
            passSentForRep.insert(currentRep)
            print("[INPUT] PASS triggered for rep \(currentRep)")
            triggerPass()
        case .waitingBeep:
            print("[INPUT-GUARD] Tap ignored before beep")
        case .logging:
            print("[INPUT-GUARD] Tap ignored during logging (use swipe)")
            triggerHaptic(style: .light)
        }
    }

    private func startRep() {
        triggerHaptic(style: .light)
        lastDirection = nil
        beepTime = nil
        phase = .waitingBeep
        onRepStarted?(repIndex - 1)

        preBeepWorkItem?.cancel()
        let delay = Double.random(in: preBeepDelayRange)
        let work = DispatchWorkItem {
            beep()
        }
        preBeepWorkItem = work
        if delay <= 0 {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func beep() {
        guard phase == .waitingBeep else { return }
        beepTime = Date()
        phase = .waitingPass
    }

    private func triggerPass() {
        guard phase == .waitingPass else { return }
        triggerHaptic(style: .medium)

        // 1) Update UI state immediately.
        phase = .logging

        // 2) Then trigger transport callback.
        onPassTriggered?(repIndex - 1)
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        guard phase == .logging else {
            print("[INPUT-GUARD] Swipe ignored — not in logging phase")
            return
        }
        let dx = value.translation.width
        let dy = value.translation.height

        guard abs(dx) > 30 || abs(dy) > 30 else { return }

        let direction: SwipeDirection

        if abs(dx) > abs(dy) {
            direction = dx > 0 ? .right : .left
        } else {
            direction = dy > 0 ? .down : .up
        }
        let currentRep = repIndex - 1
        print("[INPUT] Swipe logged direction \(direction.rawValue) for rep \(currentRep)")
        triggerHaptic(style: .rigid)
        lastDirection = nil
        lastDirection = direction
        beepTime = nil
        onDirectionLogged?(currentRep, direction)
        passSentForRep.remove(currentRep)
        if repIndex < totalReps {
            repIndex += 1
        }
        // Immediately allow next rep.
        phase = .waitingForNextRep
        inputLocked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // allow next interactions after 100ms
            inputLocked = false
        }
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

struct DisableSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#Preview {
    CoachSessionView(
        mode: .findPicture,
        totalReps: 12,
        preBeepDelayRange: 0.0...0.0,
        onRepStarted: nil,
        onPassTriggered: nil,
        onDirectionLogged: nil
    )
}
