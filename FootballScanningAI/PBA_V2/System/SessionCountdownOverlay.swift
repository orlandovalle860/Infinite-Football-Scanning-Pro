//
//  SessionCountdownOverlay.swift
//  FootballScanningAI
//
//  PBA V2 — Full-screen 3, 2, 1, Go countdown when a session view appears.
//

import SwiftUI

/// Shows a 3–2–1–Go countdown when the session first appears, then reveals the wrapped content.
struct SessionCountdownModifier: ViewModifier {
    @State private var countdown: Int? = 3
    @State private var timer: Timer?

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
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
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
    /// Runs a 3–2–1–Go countdown when the view appears, then shows this view.
    func sessionCountdown() -> some View {
        modifier(SessionCountdownModifier())
    }
}
