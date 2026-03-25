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

    @State private var countdown: Int?
    @State private var timer: Timer?
    @State private var hasStartedCountdown = false

    init(waitForPartnerReady: Bool, partnerReady: Bool) {
        self.waitForPartnerReady = waitForPartnerReady
        self.partnerReady = partnerReady
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
        }
        .onChange(of: partnerReady) { _, ready in
            guard waitForPartnerReady, ready else { return }
            startCountdownOnce()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
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
        modifier(SessionCountdownModifier(waitForPartnerReady: waitForPartnerReady, partnerReady: partnerReady))
    }
}
