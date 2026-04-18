import Foundation
import Combine

/// Mirrors iPad rep input timing for UI. **Authoritative drill gating** is
/// ``*Engine.phase`` in each display session view — this object only tracks
/// coarse UI state between beep / pass / swipe for overlays and solo taps.
final class RepStateController: ObservableObject {

    enum State {
        case idle
        case preBeep
        case decisionWindow
        case locked
    }

    @Published private(set) var state: State = .idle

    private(set) var hasLoggedTap = false
    private(set) var hasLoggedSwipe = false

    // MARK: - State Transitions

    func startRep() {
        state = .preBeep
        resetInputs()
    }

    func openDecisionWindow() {
        state = .decisionWindow
    }

    func lockRep() {
        state = .locked
    }

    func reset() {
        state = .idle
        resetInputs()
    }

    /// Clears rep UI state when the player starts a **new** relay session from mid-session disconnect recovery.
    func resetForNewSession() {
        reset()
    }

    /// HARD gate for incoming `nextRep` transport messages (must align with engine `.waitingForNextRep`).
    func acceptIncomingNextRep() -> Bool {
        guard state == .idle else { return false }
        state = .preBeep
        resetInputs()
        return true
    }

    /// Drop back to ``idle`` when the engine is between reps.
    func completeRepCycleEnd() {
        guard state != .idle else { return }
        state = .idle
        resetInputs()
    }

    private func resetInputs() {
        hasLoggedTap = false
        hasLoggedSwipe = false
    }

    // MARK: - Input Guards (UI / solo; network handlers also check engine phase)

    func canAcceptTap() -> Bool {
        return state == .decisionWindow && !hasLoggedTap
    }

    func canStartRep() -> Bool {
        return state == .idle
    }

    func canAcceptSwipe() -> Bool {
        return state == .decisionWindow && !hasLoggedSwipe
    }

    func registerTap() {
        hasLoggedTap = true
    }

    func registerSwipe() {
        hasLoggedSwipe = true
        state = .locked
    }
}
