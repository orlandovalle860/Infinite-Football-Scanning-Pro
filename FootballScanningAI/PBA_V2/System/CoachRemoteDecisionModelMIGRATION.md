# Coach / display decision model — phased migration (internal)

## Current state (Phase 1 — product copy only)

### Legacy **wire / Codable** names (do not rename in Phase 1)

| Name | Role | Why it stays |
|------|------|----------------|
| `TwoMinuteMessage.firstTouchLogged(repIndex:gate:timestamp:)` | Optional coach timing on DOP / AFP | Relay payloads decode `kind: "firstTouchLogged"`. Renaming requires dual-decode or protocol versioning. |
| `TwoMinuteMessage.incorrectDecision(repIndex:timestamp:)` | Coach marks rep wrong without logging a direction | Same: stable `kind` string on the wire. |

**Internal Swift** mirrors this: `onFirstTouchLogged`, `firstTouchGate`, `firstTouchLoggedAt`, etc. Renaming types/properties is a later phase once all clients ship compatible decoders.

### Desired **future** names (not implemented yet)

- Wire: e.g. `earlyActionLogged` or `firstDecisionLogged` (TBD) — only with versioned payloads or dual decode.
- Code: align model fields with “first decision / action” once migration path is defined.

---

## Where `incorrectDecision` is **still required** (Phase 1)

Coach remote cannot be removed until each activity can mark **wrong** without implying a misleading **direction**:

| Activity | App-computed correctness from `exitLogged` alone? | Why `incorrectDecision` stays |
|----------|---------------------------------------------------|-------------------------------|
| **Dribble or Pass** | Yes — `correct = (gate == expectedCorrectGate)` | Coach ✕ forces `correct: false` when logging a direction would misrepresent the player or dispute auto scoring. |
| **One-Touch Passing** | Yes — `correct = greenDirections.contains(gate)` | Same — human override. |
| **Away From Pressure** | Yes when coach logs a **direction** — `correct = (exitedGate == pressureGate.opposite)` | ✕ records `exitedGate == nil` → incorrect without a direction. |
| **2-Minute / Critical Scan** | Yes when coach logs direction — `correct = (ballGate == exitedGate)` | ✕ builds a log with intentional wrong exit (see engine). |

**None** of these can drop the ✕ path until there is another authoritative signal (e.g. display-side tracking) that replaces “coach says wrong without picking a gate.”

---

## “App-computed correctness” readiness (today)

| Activity | Primary correctness | Optional extra metrics |
|----------|---------------------|-------------------------|
| **DOP / OTP** | Fully from chosen gate vs scenario | Optional coach “first touch” direction is for **match / correction** stats only — not required for base `correct`. |
| **AFP** | From logged exit direction vs pressure | Optional `firstTouchLogged` improves late-correction / commitment stats. |
| **2-Minute** | From logged exit vs ball | N/A |

---

## Before removing the ✕ button everywhere

1. Stable alternative for “wrong rep, no direction” (sensor / video / display-only adjudication), **or** accept that direction-only logging is always sufficient (product decision).
2. Versioned relay schema **or** dual decode for any renamed `kind` values.
3. Backfill / analytics alignment if stored aggregates change meaning.

---

## References in code

- `TwoMinuteModels.swift` — `TwoMinuteMessage` encode/decode `kind` strings.
- `RemoteService.sendIncorrectDecision` / `send` paths — unchanged in Phase 1.
- Engines: `onIncorrectDecision`, `onFirstTouchLogged` — behavior unchanged in Phase 1.
