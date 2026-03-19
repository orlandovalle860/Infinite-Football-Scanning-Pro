# PBA V2 — Training analytics measurement model

## Decision timing (decision speed)

- **Definition:** Time from **trigger timestamp** (beep / pass triggered) to **coach directional input** (when the coach selects the player’s decision: up / down / left / right).
- **Formula:** `decisionTime = coachInputTimestamp − triggerTimestamp`
- **No separate first-touch logging.** The coach’s single tap (direction or incorrect) is treated as the first decision. Zero extra coach friction.

### By activity

- **Playing Away From Pressure:** `decisionTimeSeconds` = `exitLoggedAt − passTriggeredAt` (when coach taps exit direction or ✕).
- **Dribble or Pass:** Decision time = trigger → when coach taps chosen gate (direction).
- **One-Touch Passing:** Decision time = trigger → when coach taps pass direction or ✕.
- **2-Minute Test:** Decision time = trigger → when coach taps exit direction.

## Optional metrics (first touch)

- **First touch** (when logged) can still be used for optional analytics (e.g. correction rate: first touch wrong but exit correct). Not required for decision speed.
- **Correction rate** requires both first touch and exit logged; if not logged consistently, do not calculate.

## v1 priorities

1. **Decision Speed** — timing from trigger to coach directional input.
2. **Accuracy** — correct vs incorrect (from coach’s logged direction).
