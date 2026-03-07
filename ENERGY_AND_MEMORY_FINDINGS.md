# Energy & Memory Audit – Findings and Recommendations

## Fixes applied (timer leaks)

- **MainView (display session) countdown** – The 3‑2‑1 countdown timer was not stored or invalidated when leaving the screen. It is now stored in `countdownTimer`, invalidated in `onDisappear`, and cleared in `stopTimer()` so it never keeps running after the view is gone.
- **TwoMinuteGetReadyView countdown** – Same issue: countdown timer was unreferenced. It is now stored in `countdownTimer` and invalidated in `onDisappear` so leaving during “Get ready” does not leave a timer running.

## Already in good shape

- **Other timers** – GetReady countdowns and coach‑remote volume‑polling timers in PBA flows are invalidated in `onDisappear` or when `enabled`/`connected` turns false.
- **Multipeer** – `stopBrowsing()` / `stopAdvertising()` are called when coach remotes and session views disappear.
- **NotificationCenter** – Audio interruption observers in display session views use a stored observer and `removeObserver` in cleanup; the app‑level observer in the app delegate is left in place by design for the app lifecycle.
- **Weak references** – Several engine and coach‑remote timers already use `[weak self]` where appropriate.

## Intentional energy use (by design)

- **Idle timer disabled** – The app disables the device idle timer during training so the screen stays on; this increases energy use but is required for the use case.
- **Brightness** – When “screen protection” is on, brightness is set to 1.0 and a 1 s timer keeps resetting it for outdoor visibility. This is intentional.

## Optional tuning (if you want to reduce energy further)

1. **Screen protection timer** – Currently runs every **1 s** to reset brightness. You could increase the interval (e.g. 5–10 s) or only set brightness on `scenePhase`/`becomeActive` to reduce CPU wakeups.
2. **Coach remote volume polling** – Polling at ~0.12 s is responsive but costs a bit of CPU; keeping it is reasonable for UX; reducing frequency would save a small amount of energy at the cost of slightly slower volume response.
3. **No further timer leaks found** – All other timers we checked are either invalidated on disappear or tied to phases that end correctly.

## Memory

- No obvious retain cycles or large unbounded caches were found. SwiftUI state and observed objects are used in a normal way. If you see growth over long sessions, the next place to look would be any caches (e.g. images or session data) and ensuring they are cleared or bounded when leaving flows.

## Summary

- **Two timer leaks were fixed** (MainView and TwoMinuteGetReadyView countdowns).
- **Multipeer, observers, and other timers** are cleaned up on disappear.
- **Higher energy use** comes mainly from intentional choices (idle timer off, brightness, screen‑on during training). Optional tweaks above can reduce energy a bit if needed.
