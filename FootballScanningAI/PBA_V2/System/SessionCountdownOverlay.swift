//
//  SessionCountdownOverlay.swift
//  FootballScanningAI
//
//  PBA V2 — Full-screen 3, 2, 1, Go countdown when a session is ready to begin.
//

import SwiftUI

/// Shows a 3–2–1–Go countdown, then reveals the wrapped content.
///
/// **Solo / non-partner:** countdown starts when the view appears (same as before).
/// **Partner:** when `waitForPartnerReady` is true, the drill UI (including join code / pairing) stays visible
/// until `partnerReady` becomes true; only then does the countdown run — so “3–2–1–Go” means the block is about to start,
/// not “more pairing setup is required.”
struct SessionCountdownModifier: ViewModifier {
    let waitForPartnerReady: Bool
    let partnerReady: Bool
    /// When non-nil, set to `true` while the 3–2–1–Go overlay is active so partner drill views can ignore coach `TwoMinuteMessage` ingress (engine/timer state must not advance while content is hidden).
    var suppressCoachMessagesDuringCountdown: Binding<Bool>?

    @State private var countdown: Int?
    @State private var timer: Timer?
    @State private var hasStartedCountdown = false
    /// After the first 3–2–1–Go fully finishes, partner relay blips must not re-run the countdown (which would suppress coach `nextRep` mid-block).
    @State private var hasFinishedInitialCountdown = false

    init(waitForPartnerReady: Bool, partnerReady: Bool, suppressCoachMessagesDuringCountdown: Binding<Bool>? = nil) {
        self.waitForPartnerReady = waitForPartnerReady
        self.partnerReady = partnerReady
        self.suppressCoachMessagesDuringCountdown = suppressCoachMessagesDuringCountdown
        _countdown = State(initialValue: waitForPartnerReady ? nil : 3)
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(countdown == nil ? 1 : 0)
            if countdown != nil {
                Color.black.ignoresSafeArea()
                if let n = countdown, n > 0 {
                    Text("\(n)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                } else if countdown == 0 {
                    Text("Go")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                }
            }
        }
        .onAppear {
            if !waitForPartnerReady {
                startCountdown()
            } else if partnerReady {
                startCountdownOnce()
            }
            syncCoachMessageSuppression(countdownValue: countdown)
        }
        .onChange(of: partnerReady) { _, ready in
            guard waitForPartnerReady else { return }
            if !ready {
                timer?.invalidate()
                timer = nil
                countdown = nil
                syncCoachMessageSuppression(countdownValue: nil)
                // Before the first "Go" completes, allow a fresh 3–2–1 after reconnect; after that, never re-arm mid-block.
                if !hasFinishedInitialCountdown {
                    hasStartedCountdown = false
                }
                return
            }
            startCountdownOnce()
        }
        .onChange(of: countdown) { _, newValue in
            syncCoachMessageSuppression(countdownValue: newValue)
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            syncCoachMessageSuppression(countdownValue: nil)
        }
    }

    private func syncCoachMessageSuppression(countdownValue: Int?) {
        let active = (countdownValue != nil)
        suppressCoachMessagesDuringCountdown?.wrappedValue = active
        if suppressCoachMessagesDuringCountdown != nil {
            TrainingPartnerConnectionCoordinator.shared.setPartnerDisplayCountdownActive(active)
        }
    }

    private func startCountdownOnce() {
        guard !hasStartedCountdown else { return }
        hasStartedCountdown = true
        startCountdown()
    }

    private func startCountdown() {
        timer?.invalidate()
        countdown = 3
        var remaining = 3
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { tim in
            remaining -= 1
            DispatchQueue.main.async {
                countdown = remaining > 0 ? remaining : 0
            }
            if remaining <= 0 {
                tim.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    countdown = nil
                    hasFinishedInitialCountdown = true
                }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }
}

extension View {
    /// Runs a 3–2–1–Go countdown when the session should start, then shows this view.
    /// - Parameters:
    ///   - waitForPartnerReady: Pass `true` for partner mode so countdown waits until the coach is connected/paired.
    ///   - partnerReady: `true` when relay/Multipeer pairing is complete (ignored when `waitForPartnerReady` is `false`).
    func sessionCountdown(waitForPartnerReady: Bool = false, partnerReady: Bool = false) -> some View {
        modifier(SessionCountdownModifier(waitForPartnerReady: waitForPartnerReady, partnerReady: partnerReady, suppressCoachMessagesDuringCountdown: nil))
    }

    /// Same as ``sessionCountdown(waitForPartnerReady:partnerReady:)`` but toggles `suppressCoachMessagesDuringCountdown` while the countdown overlay is visible so drill engines do not process coach messages until "Go".
    func sessionCountdown(waitForPartnerReady: Bool, partnerReady: Bool, suppressCoachMessagesDuringCountdown: Binding<Bool>) -> some View {
        modifier(SessionCountdownModifier(waitForPartnerReady: waitForPartnerReady, partnerReady: partnerReady, suppressCoachMessagesDuringCountdown: suppressCoachMessagesDuringCountdown))
    }
}
