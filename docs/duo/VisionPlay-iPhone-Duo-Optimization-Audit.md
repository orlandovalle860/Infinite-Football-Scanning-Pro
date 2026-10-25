# VisionPlay — iPhone Duo Optimization Audit

Phase 1 read-only investigation. No code, project settings, or deploy changes were made.

**Audited tree (original):** `cursor/fix-short-beep-resource-9172` @ `709a6d4`  
**Known-good Partner reconnect baseline:** `7c90581` on `troubleshoot/hotspot-disconnect-appstore`

> **Baseline note for this branch:** `feature/duo-optimization` now includes `7c90581` (and a merge of `origin/main`). The “reconnect baseline missing” blocking callout below described the *audit tree*, not this branch.

---

## Blocking finding (on the audited tree)

Commit `7c90581` was not an ancestor of the audited working tree and was not on `origin/main`. Partner reconnect code there was substantially thinner than the field-tested baseline (~864 fewer lines in `TrainingPartnerConnectionCoordinator`; relay lacked same-token replace; empty-room grace was 5 min vs baseline 15 min). Duo layout work must not start without aligning to the reconnect baseline.

---

## 1. Executive Summary

| Metric | Status |
|--------|--------|
| Duo readiness today | Partial |
| Reconnect baseline on audited tree | Missing |
| Size-class adaptive UI | None |
| UIScreen.main layout risk | High |

VisionPlay can run on iPhone Duo as a standard iPhone app, but it is not Duo-optimized. Coach Remote already uses a full-screen TAP surface that should work reasonably on the compact outer display.

**Largest gaps (as of audit):**
1. Partner reconnect baseline not present on audited branch/main
2. Extensive `UIScreen.main` sizing in legacy display paths
3. Zero size-class / reserved-region adaptation
4. SDK generation — Apple documents that iOS 26 SDK builds letterbox on Duo’s inner display

### Highest-priority findings

**Reconnect baseline not in working tree / main** — CONFIRMED  
`7c90581` only on `troubleshoot/hotspot-disconnect-appstore`. Same-room retained reconnect, same-token replace, 15-min empty-room grace, and HotspotBaselineLog existed only on the baseline branch. Recycle paths could mint a new room (new join code) after socket loss.

**No size-class based layout anywhere** — CONFIRMED  
`rg horizontalSizeClass|verticalSizeClass` → 0 matches. Apple’s Duo prepare guidance requires adapting by available space / size classes. VisionPlay switches on UIDevice idiom (`.phone`/`.pad`) instead. Inner Duo display reports regular×regular — which can incorrectly take “iPad” layout paths if gated only on regular width or pad idiom.

**Heavy UIScreen.main geometry** — CONFIRMED  
`ContentView.swift` ~6473–8565; `FootballScanningAIApp.swift` 33,46,61; `TwoMinuteSlotPositions.swift` 37. Apple warns `UIScreen.main` is ambiguous on multi-display devices and size can change mid-session on fold/unfold. PBA drill GeometryReader paths are better; legacy ContentView training is not.

**Coach Remote TAP is already full-bleed** — ALREADY SUPPORTED  
`CoachSessionView.swift` 173–281. Full-screen contentShape + tap/swipe gestures, status line + optional rep header at top. Good baseline for one-handed coach use. Still needs fold/safe-area verification on physical Duo.

---

## 2. Verified iPhone Duo Technical Requirements

### Officially documented (Apple)

| Topic | Verified detail | Source |
|-------|-----------------|--------|
| Outer display | 5.4″ OLED, 1398×2034 px @ 460 ppi | support.apple.com/148588 |
| Inner display | 7.6″ OLED foldable, 1878×2670 px @ 430 ppi | support.apple.com/148588 |
| Closed / open size | Closed 84.1×117.8×11.3 mm; open 164.6×117.8×5.2 mm | Apple Support tech specs |
| SDK resize behavior | iOS 26 SDK: letterboxed when open. iOS 27: fills most inner display. iOS 27.1+: full display + vertical bars | developer.apple.com/iphone-duo/prepare |
| Do not use UIScreen.main for size | Size from view/window; re-read on change; GeometryReader / onGeometryChange | Prepare for iPhone Duo |
| Do not layout from orientation | Inner display does not honor supported orientations the same way; compare bounds / use size classes | Prepare + Tech Talk 111461 |
| Size classes / idiom | Any size-class combo possible; don’t treat regular width as iPad-only; don’t gate layout on phone/pad idiom | Prepare for iPhone Duo |
| Safe areas + reserved regions | Keep interactive controls in safe area; ReservedRegion occlusion (camera/island) + division (fold) | HIG + ReservedRegion docs |
| UIRequiresFullScreen | Still honored, but app still resizes when Duo opens/closes | Tech Talk 111461 |
| Adaptive containers | NavigationSplitView, TabView, sheets adapt; ArrangementView for primary/secondary across fold | HIG / ArrangementView |

### Size classes / points (INFERRED — 3rd-party simulator, not Apple-published)

| Pose | Orientation | H | V | Approx. points |
|------|-------------|---|---|----------------|
| Folded (outer) | Portrait | Compact | Regular | 466 × 678 |
| Folded (outer) | Landscape | Compact | Compact | 678 × 466 |
| Half-open / Open | Portrait | Regular | Regular | 669 × 951 |
| Half-open / Open | Landscape | Regular | Regular | 951 × 669 |

### Unknowns requiring physical-device testing

Exact safe-area asymmetry with vertical system bars; active vs inactive fold division region while coaching; whether coach phone typically stays folded vs open on the field; tent/laptop pose usability for TAP; camera occlusion on outer display; battery impact of Partner Mode + haptics; App Store Duo badge/screenshot requirements.

---

## 3. Current Application Compatibility Assessment

### Project / scene baseline

| Setting | Current value | Duo implication |
|---------|---------------|-----------------|
| App IPHONEOS_DEPLOYMENT_TARGET | 18.0 | Runs on Duo; SDK used to build matters more for resize |
| Project LastUpgradeCheck | 2620 (Xcode 26 lineage) | If shipping with iOS 26 SDK: letterboxed on open Duo per Apple |
| TARGETED_DEVICE_FAMILY | 1,2 (iPhone + iPad) | Good — Duo is iPhone family; iPad display still required |
| iPhone orientations | Portrait + Landscape L/R | Outer landscape supported. Do not use orientation for layout |
| iPad orientations | All four | Player display OK. Keep GeometryReader-based drill math |
| Scene | Single WindowGroup | Mid-session size change must not recreate session owners |
| Navigation | NavigationStack via AppRouter | Protect path from onAppear resets during resize |

### Adaptive vs fixed layout signals

- **Zero size-class environment usage** — CONFIRMED
- **Idiom-gated coach/player roles** — POTENTIAL RISK (`CoachRemoteSessionStartGate`, ContentView)
- **PBA drills mostly GeometryReader-based** — ALREADY SUPPORTED
- **Legacy ContentView still UIScreen-bound** — CONFIRMED
- **Dynamic Type** — POTENTIAL RISK (many fixed point sizes)

**Verdict:** Traditional iPhone+iPad SwiftUI app with good GeometryReader habits in PBA V2 display drills, but assumes stable phone/pad dimensions and does not yet implement Duo adaptive layout.

---

## 4. Coach Remote Findings (Highest Priority)

Primary Duo role: Coach Remote controlling iPad player display.

| Criterion | Assessment | Label |
|-----------|------------|-------|
| A. TAP sizing / placement | Full-screen tap target; prompt centered | ALREADY SUPPORTED |
| B. One-handed operation | Large central TAP; may feel sparse when Duo open | POTENTIAL RISK |
| C. Reachability | Tap anywhere; swipe for direction; nav back hidden in live drill | ALREADY SUPPORTED |
| D. Rep counter visibility | Optional block progress; partner timed often hides counter | POTENTIAL RISK |
| E. Connection status | Passive status line + reconnect waiting views | ALREADY SUPPORTED |
| F. Reconnecting indicators | Present, weaker than baseline on audited tree | CONFIRMED ISSUE vs baseline |
| G. Navigation | Hub → activity remote; live drill suppresses back | ALREADY SUPPORTED |
| H. Text readability | largeTitle bold on black; fixed sizes may not scale | POTENTIAL RISK |
| I. Landscape | Spacers reflow; compact×compact outer landscape is short | REQUIRES DEVICE TESTING |
| J. Dimension changes | SwiftUI reflows; .id remount intentional for rep input reset | POTENTIAL RISK |
| K. Touch targets | Full-screen ≥ 44pt; escalating haptics while waiting | ALREADY SUPPORTED |
| L. Clip / obscure | ignoresSafeArea black bg; not fold-aware | REQUIRES DEVICE TESTING |

**Redesign not required.** Prefer: keep full-screen TAP; ensure status + reconnect chrome stay inside safe area; optional bottom-weighted TAP cue on tall layouts; never remount session owners on geometry change.

---

## 5. Partner Session Continuity Risks

**Critical on audited tree:** missing same-token replace, 5-min empty-room grace, no retained coach WS config, recycle can mint new room, reachability not wired to Partner reconnect.

**Good patterns:** coordinator singleton; rep index owned by parent coach remote; background vs inactive discrimination.

**Do not modify reconnect while doing Duo layout** until baseline is merged and re-verified on hotspot walk-away.

---

## 6. iPad Player Display Considerations

- Drill geometry largely isolated via GeometryReader — ALREADY SUPPORTED  
- Legacy UIScreen paths still in ContentView — POTENTIAL RISK  
- Soft reconnect rep restart notifications shared — POTENTIAL RISK  

Change only Coach* / PartnerLink chrome first. Gate Duo polish on size class + role, not idiom alone.

---

## 7. Performance Findings

View reconstruction from `.id` remounts; many onChange handlers; escalating haptic loop; idle timer disabled + max brightness (intentional); no confirmed Duo-specific performance defect without hardware profiling.

---

## 8. Prioritized Implementation Roadmap

### PHASE A — Essential compatibility / continuity
- **A1** Merge `7c90581` reconnect baseline — Critical — L  
- **A2** Confirm SDK 27 / 27.1 plan — Critical — S  
- **A3** Quarantine UIScreen.main layout reads — High — M  
- **A4** Guard size/pose changes from ending session — Critical — M  

### PHASE B — Coach Remote usability
- **B1** Safe-area status/reconnect chrome — High — S  
- **B2** Bottom-weighted TAP cue on tall layouts — Medium — S  
- **B3** Keep rep + connection visible in reconnect scrim — High — S  
- **B4** Compact-height landscape chrome audit — Medium — S  

### PHASE C — Expanded-screen enhancements
- **C1** Size-class hub density — Medium  
- **C2** ReservedRegion.division for book pose — Low  
- **C3** Never show player-display layout on coach regular width — High  

### PHASE D — Performance and polish
- **D1** Reduce unnecessary CoachSessionView remounts — Medium  
- **D2** Haptic loop power when reconnecting / backgrounded — Low  
- **D3** App Store Duo screenshots / badge — Low  

---

## 9. Testing Matrix

Every Partner test must be run against a branch containing `7c90581` before declaring Duo work safe.

Key tests: cold launch; coach pairing; start drill + reps; fold/unfold mid-rep; orientation mid-rep; background/foreground; network blip; **hotspot walk-away (mandatory physical)**; rep continuity; end / new activity / Train Again only on explicit action; iPad display regression.

---

## 10. Direct Answers

**1. How compatible is VisionPlay with iPhone Duo today?**  
Partially compatible. Outer display + Coach Remote TAP are solid. Not Duo-optimized (no size-class adaptation, heavy UIScreen usage, letterbox risk with iOS 26 SDK). On the audited tree, Partner reconnect was not the field-tested baseline.

**2. What absolutely must change?**  
(1) Align with reconnect baseline `7c90581` before Duo UI. (2) Size/pose changes must not mint rooms / clear credentials / pop to pairing. (3) Stop UIScreen.main for layout. (4) Plan SDK 27/27.1. (5) Do not treat regular width as iPad player UI when role is coach.

**3. What would make Coach Remote substantially better on Duo?**  
Keep full-screen TAP; pin connection + rep chrome in safe areas; slightly bottom-weight TAP prompt on tall open layouts; non-destructive reconnect scrims; optionally densify hub when open.

**4. Highest-risk changes to Partner Mode?**  
Coordinator, WebSocketRemoteTransport, PartnerRelayDisplaySession recycle/reset, relay attachSocket / empty-room grace, coach onAppear session start / Train Again, bumping `coachSessionInputResetToken` from geometry, merging Duo layout into DisplaySessionView ball/cue code.

**5. Smallest, safest first implementation step?**  
Bring `7c90581` Partner reconnect baseline onto the shipping branch and re-run physical hotspot walk-away — with zero Duo layout changes in that PR. Only after green: coach-only safe-area / status-chrome pass.

---

Sources: Apple Support tech specs, developer.apple.com/iphone-duo/prepare, HIG Designing for iPhone Duo, ReservedRegion docs, Tech Talk 111461.
