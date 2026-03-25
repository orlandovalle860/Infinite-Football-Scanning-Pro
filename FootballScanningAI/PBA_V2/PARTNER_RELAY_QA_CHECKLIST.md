# Partner & relay QA checklist (internal)

**Purpose:** Regression and rollout-prep for coach ↔ display partner flows.  
**Relay:** DEBUG builds use `PartnerTransportPolicy` → relay WebSocket; Release uses Multipeer (same scenarios apply where noted).

**Legend:** ✅ pass · ⚠️ issue · N/A skip

---

## Shared scenarios (run per activity)

| # | Scenario | What to verify |
|---|----------|----------------|
| A | **Same WiFi** | Display + coach discover each other (Multipeer) or relay join succeeds; pairing → block countdown → reps. |
| B | **Hotspot** | Phone hotspot: display on one device, coach on other; relay join or Multipeer invite works; session stable for one block. |
| C | **Display background** | With coach paired, press Home on Display; relay/Multipeer tears down; coach returns to hub or shows disconnected; no stuck “connected” UI. |
| D | **Coach background** | Coach app backgrounded; display behavior acceptable (session end or disconnect path); reconnect policy unchanged. |
| E | **Display exit** | User leaves Display session (toolbar/back); `sessionEnded` or equivalent; coach not stuck in active session. |
| F | **Coach exit** | Coach leaves remote; display unpairs / shows appropriate state; can start fresh session. |
| G | **Fresh rejoin after disconnect** | New join code (relay) or re-browse (Multipeer); full pairing → countdown → reps without stale state (join field cleared on coach). |

---

## Two Minute (`TwoMinuteCriticalScanSessionView` / `TwoMinuteCoachRemoteView`)

| Step | Check |
|------|--------|
| 1 | Partner: Instructions note mentions Display setup before block countdown. |
| 2 | Relay DEBUG: join code visible; coach joins; `peer_joined`; session countdown runs **after** coach connected. |
| 3 | Multipeer Release: hosting + invite; countdown after peer connected. |
| 4 | Scenarios A–G | 

---

## Dribble or Pass

| Step | Check |
|------|--------|
| 1 | Get Ready + Instructions partner copy accurate. |
| 2 | Relay DEBUG: display relay session + coach WS; reps and logging. |
| 3 | Multipeer Release: parity with prior behavior. |
| 4 | Scenarios A–G | 

---

## Away From Pressure

| Step | Check |
|------|--------|
| 1 | Get Ready + Instructions partner copy accurate. |
| 2 | Relay DEBUG end-to-end. |
| 3 | Multipeer Release. |
| 4 | Scenarios A–G | 

---

## One Touch Passing

| Step | Check |
|------|--------|
| 1 | Get Ready + Instructions partner copy accurate. |
| 2 | Relay DEBUG end-to-end. |
| 3 | Multipeer Release. |
| 4 | Scenarios A–G | 

---

## Debug logging (optional)

- `[RelayWS-DEBUG][DOP Display]` / `[DOP Coach]` (and AFP/OTP tags) for relay path tracing.
- `[RelayWS-DEBUG]` in `PartnerRelayDisplaySession` for HTTP/WS lifecycle.

---

## Not in scope for this checklist

- Changing `PartnerTransportPolicy` rollout rules.
- Server/infra load testing (separate doc).
