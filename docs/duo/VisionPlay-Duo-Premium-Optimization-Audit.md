# VisionPlay — iPhone Duo Premium Optimization Audit

Phase 1 read-only. No code, settings, commits, merges, or deploys.

**Audited tree (original):** `cursor/fix-short-beep-resource-9172` @ `709a6d4`  
**Protect reconnect baseline:** `7c90581` (`troubleshoot/hotspot-disconnect-appstore`)

> **Baseline note for this branch:** `feature/duo-optimization` now includes `7c90581`. Treat the “reconnect missing” blocking callout as resolved here.

---

## Blocking finding (on the audited tree)

`7c90581` was not an ancestor of HEAD and was not on `origin/main`. Coordinator was 1566 lines there vs 2430 on baseline. Relay still rejected same-token reconnect (`DISPLAY_ALREADY_CONNECTED` / `COACH_ALREADY_CONNECTED`). Empty-room grace was 5 min vs baseline 15. Recycle could mint a new room. Premium Duo UI must not ship ahead of restoring this baseline.

---

## 1. Executive Summary

| Metric | Status |
|--------|--------|
| Premium Duo readiness | ~35% |
| Reconnect baseline (audited tree) | Missing |
| Full-screen TAP foundation | Strong |
| Rep counter on timed coach | Hidden |

VisionPlay already has the right Coach Remote interaction model for a field instrument: full-screen TAP/PASS/SWIPE on black, escalating wait haptics, and live-drill back suppression. It is not yet a purpose-built Duo product.

### Top findings

**Timed Partner coach hides Rep X of Y** — CONFIRMED  
`TimedSessionDisplayIntegration.swift:61` `showsCoachBlockRepProgress = false`. Coaches lose glanceable rep identity.

**Full-screen TAP is already instrument-grade** — ALREADY SUPPORTED  
`CoachSessionView.swift` 173–281, 400–437, 714–751. Premium work should refine hierarchy, not replace the model.

**No size-class / ReservedRegion adaptation** — CONFIRMED  
Unfolded Duo (regular×regular) gets the same layout as folded compact.

**Reconnect baseline absent from shipping line** — CONFIRMED (on audited tree)

---

## 2. Verified Duo Technical Specifications

Same Apple-verified display/SDK/layout rules as the iPhone Duo audit (outer 5.4″, inner 7.6″, SDK 26 letterbox → 27 → 27.1 full + vertical bars, no UIScreen.main, size classes, ReservedRegion).

Approx. points (inferred): folded portrait ~466×678; open portrait ~669×951.

Unknowns: coach field pose preference; outdoor contrast / vertical bar insets on device.

---

## 3. Current App Compatibility

Deployment 18.0; LastUpgradeCheck 2620; device family 1,2; single WindowGroup; NavigationStack + AppRouter; **no size classes used**; heavy UIScreen.main in ContentView; PBA drills GeometryReader-based; brightness/idle intentional outdoor settings.

---

## 4. Folded Field Controller Assessment

Primary use: one-handed coach, eyes mostly on the player.

| Lens | Assessment | Label |
|------|------------|-------|
| TAP size | Entire screen is the hit target | ALREADY SUPPORTED |
| TAP placement | Cue mid-screen; whole surface still taps | POTENTIAL RISK |
| Eyes-free reliability | Full-screen + escalating wait haptics | ALREADY SUPPORTED |
| Accidental activation | 0.65s debounce + phase guards | ALREADY SUPPORTED |
| Visual response | Brief scale/opacity flash | ALREADY SUPPORTED |
| Rep visibility | OFF for timed Partner | CONFIRMED ISSUE |
| Activity name | Header 70% white — secondary | POTENTIAL RISK outdoors |
| Connection status | Caption 60% opacity | POTENTIAL RISK |
| Reconnect clarity | Weaker than baseline on audited tree | CONFIRMED ISSUE vs baseline |
| Destructive actions | Back hidden; disconnect behind confirm | ALREADY SUPPORTED |
| Outdoor contrast | Black + white good; status under-emphasized | REQUIRES DEVICE TESTING |

### Recommended premium folded layout (do not implement yet)

1. **TOP SAFE BAND** (non-interactive): activity short name · Rep N · connection pill (Connected / Reconnecting / Disconnected) with icon + text  
2. **PRIMARY ACTION ZONE**: keep full-screen hit-testing; move TAP/PASS/SWIPE cue slightly lower-third  
3. **HAPTICS**: keep wait escalation + accepted-tap flash; cancel nagging haptics on reconnect  
4. **NAV**: keep back suppressed; End Session only via explicit control away from TAP center  
5. **CODE TOUCH**: primarily CoachSessionView + PartnerLinkPassiveStatusLine + TimedSessionDisplayIntegration — no coordinator/relay edits  

---

## 5. Unfolded Coaching Console Assessment

**Current behavior:** Unfolded Duo stretches the same single-column CoachSessionView into regular×regular — sparse, not console-grade.

**Recommended intentional console:**
- **CONTROL REGION (primary):** Large TAP/PASS/SWIPE; connection chip; dominant phase word; no competing buttons  
- **INFORMATION REGION (secondary):** Activity name; rep progress; session timer if already available; soft status; no invented analytics for v1  

Prefer size-class split (compact = stacked Field Controller; regular width = Control | Information) inside CoachSessionView or a thin wrapper.

---

## 6. Adaptive Layout & Transitions

**Non-negotiable:** Display configuration changes must never end Partner session, mint rooms, reset rep/activity/TAP, Train Again, pop to pairing, drop healthy sockets, or interrupt the athlete drill.

Risks: coach onAppear beginPartner; `.id(coachSessionInputResetToken)`; hub onAppear auto-reconnect; recycle → new room (on audited tree). Singleton ownership and parent-owned rep index are good.

Drive layout with `horizontalSizeClass` only inside presentation views; never put session mutations in geometry onChange.

---

## 7. Partner Mode Continuity Risks (audited tree vs baseline)

| System | Baseline 7c90581 | Audited tree |
|--------|------------------|--------------|
| Coordinator | Same-room retained reconnect + transient UI | Thinner; no retained WS / same-room loops |
| relay attachSocket | Same-token replace | Rejects second socket ALREADY_CONNECTED |
| EMPTY_ROOM_GRACE_MS | 15 min | 5 min |
| NetworkReachabilityObserver | Pokes same-room reconnect | Only ContentView sync retry |
| PartnerRelayDisplaySession | Prefer same-room recovery | Unexpected drop → recycle → new session |
| HotspotBaselineLog | Present | Missing |

Duo presentation can proceed after baseline restore without touching these files — and must not touch them during UI milestones.

---

## 8. iPad Player Display Risks

Drill math GeometryReader-based — isolate Duo work to Coach* chrome. Soft reconnect restart notifications are shared — don’t double-post. Legacy ContentView UIScreen paths out of scope for Coach Duo premium.

---

## 9. Premium Visual & Interaction Design

Premium = intentional instrument, not more chrome. Reuse CoachSessionView, PartnerLinkPassiveStatusLine, CoachRemoteCopy, CoachRemoteHaptics, CoachTapInputGuard, hub tiles.

Keep black instrument look; raise status contrast; don’t rely on color alone; folded lower-third cue; unfolded two-region balance; keep gesture model and haptic patterns.

---

## 10. Performance Findings

`.id` remounts; many onChange observers; escalating haptic loop; idle off + max brightness intentional; Duo fold jank not profiled on hardware.

---

## 11. Prioritized Implementation Roadmap

### PHASE A — Field-ready essentials (before first athlete test)
- **A0** Restore `7c90581` reconnect — Critical — L  
- **A1** Glanceable rep on timed coach — Critical — S  
- **A2** High-contrast connection pill — Critical — S  
- **A3** Folded lower-third TAP cue — High — S  
- **A4** Compact→regular console split — High — M  
- **A5** Fold/resize continuity smoke — Critical — S  

### PHASE B — Premium UX refinement
- B1 Unified coach design tokens — Medium  
- B2 Haptic tuning on Duo hardware — Medium  
- B3 Hub regular-width densification — Medium  
- B4 Cross-activity chrome parity — High  

### PHASE C — Advanced Duo (optional)
- C1 ReservedRegion.division — Low  
- C2 SDK 27.1 full-bleed polish — Medium  
- C3 Landscape compact-height special case — Medium  

### PHASE D — Performance / polish
- D1 Audit reset-token bumpers — Medium  
- D2 Profile fold transition — Low  

---

## 12. Initial Athlete Field-Test Checklist

**Prerequisite:** build contains `7c90581` reconnect behavior.

1. Launch on Duo  
2. Pair with iPad  
3. Start Two-Minute  
4. Several reps  
5. TAP responsiveness  
6. Haptics  
7. Outdoor visibility  
8. Fold/unfold mid-rep  
9. Session continuity  
10. Continue reps (no index reset)  
11. Leave hotspot → Reconnecting UI  
12. Return / recover same room  
13. Continue same session  
14. End normally  
15. Start another activity  
16. Train Again only on explicit path  
17. Repeat on AFP/DOP/OTP  

---

## 13. Direct Answers

**1. How close to fully optimized for Duo?** ~One-third of the way: strong interaction model; adaptive presentation / outdoor chrome / unfolded console / reconnect alignment incomplete on audited tree.

**2. What must change before first athlete field test?** Restore `7c90581`; glanceable rep; high-contrast connection; fold/unfold must not mint rooms or reset reps; smoke all four remotes + hotspot walk-away on physical Duo + iPad.

**3. What makes folded Coach Remote feel premium?** Eyes-up instrument: huge reliable TAP, lower-third cue, always-visible Rep + Connected/Reconnecting pill, decisive haptics, zero accidental navigation, sunlight-legible hierarchy.

**4. What makes unfolded feel purpose-built?** Control region (TAP) + Information region (activity, rep, session/link) — not stretched phone UI.

**5. Can both layouts ship without disturbing Partner networking?** Yes — presentation-only after reconnect baseline restored; no coordinator/WebSocket/relay edits in UI PRs.

**6. Which components to reuse?** CoachSessionView, CoachTapInputGuard, CoachRemoteHaptics, PartnerLinkPassiveStatusLine, CoachRemoteCopy, CoachRemoteHubView tiles, four thin activity wrappers, observe TrainingPartnerConnectionCoordinator.shared only.

**7. Safest smallest first milestone?**  
Milestone 0: land `7c90581` reconnect only (no Duo UI).  
Milestone 1: CoachSessionView presentation — timed rep chrome + stronger status pill + lower-third TAP cue (folded).

**8. How quickly to a premium field-test build?** Longest pole is reconnect parity validation on hardware, not UI polish.

---

Sources: Apple Support 148588; developer.apple.com/iphone-duo/prepare; HIG Designing for iPhone Duo; ReservedRegion; Tech Talk 111461.
