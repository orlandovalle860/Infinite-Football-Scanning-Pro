import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  Code,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Pill,
  Row,
  Spacer,
  Stack,
  Stat,
  Table,
  Text,
  useHostTheme,
  useCanvasState,
} from "cursor/canvas";

type SectionId =
  | "summary"
  | "duo"
  | "compat"
  | "coach"
  | "continuity"
  | "ipad"
  | "perf"
  | "roadmap"
  | "testing"
  | "answers";

const SECTIONS: { id: SectionId; label: string }[] = [
  { id: "summary", label: "1. Summary" },
  { id: "duo", label: "2. Duo Specs" },
  { id: "compat", label: "3. Compatibility" },
  { id: "coach", label: "4. Coach Remote" },
  { id: "continuity", label: "5. Continuity" },
  { id: "ipad", label: "6. iPad Display" },
  { id: "perf", label: "7. Performance" },
  { id: "roadmap", label: "8. Roadmap" },
  { id: "testing", label: "9. Testing" },
  { id: "answers", label: "10. Answers" },
];

function Tag({
  kind,
}: {
  kind: "confirmed" | "risk" | "supported" | "device" | "inferred" | "official";
}) {
  const map = {
    confirmed: "CONFIRMED ISSUE",
    risk: "POTENTIAL RISK",
    supported: "ALREADY SUPPORTED",
    device: "REQUIRES DEVICE TESTING",
    inferred: "INFERRED / 3RD-PARTY",
    official: "OFFICIALLY DOCUMENTED",
  };
  return (
    <Pill size="sm" active>
      {map[kind]}
    </Pill>
  );
}

function FindingCard({
  title,
  kind,
  file,
  children,
}: {
  title: string;
  kind: "confirmed" | "risk" | "supported" | "device";
  file?: string;
  children: string;
}) {
  return (
    <Card>
      <CardHeader trailing={<Tag kind={kind} />}>{title}</CardHeader>
      <CardBody>
        <Stack gap={8}>
          {file ? (
            <Text size="small" tone="secondary">
              {file}
            </Text>
          ) : null}
          <Text size="small">{children}</Text>
        </Stack>
      </CardBody>
    </Card>
  );
}

export default function VisionPlayDuoAudit() {
  const theme = useHostTheme();
  const [section, setSection] = useCanvasState<SectionId>("section", "summary");

  return (
    <Stack gap={20} style={{ padding: 24, maxWidth: 1080 }}>
      <Stack gap={6}>
        <H1>VisionPlay — iPhone Duo Optimization Audit</H1>
        <Text tone="secondary">
          Phase 1 read-only investigation. No code, project settings, or deploy
          changes were made. Audited working tree on{" "}
          <Code>cursor/fix-short-beep-resource-9172</Code> @{" "}
          <Code>709a6d4</Code>. Known-good Partner reconnect baseline:{" "}
          <Code>7c90581</Code> on{" "}
          <Code>troubleshoot/hotspot-disconnect-appstore</Code>.
        </Text>
      </Stack>

      <Callout tone="warning" title="Baseline mismatch (blocking)">
        Commit <Code>7c90581</Code> is not an ancestor of this working tree and
        is not on <Code>origin/main</Code>. Current Partner reconnect code is
        substantially thinner than the field-tested baseline (~864 fewer lines
        in <Code>TrainingPartnerConnectionCoordinator</Code>; relay lacks
        same-token replace; empty-room grace is 5 min vs baseline 15 min). Duo
        layout work must not start on top of this tree without first aligning to
        the reconnect baseline.
      </Callout>

      <Row gap={8} style={{ flexWrap: "wrap" }}>
        {SECTIONS.map((s) => (
          <Pill
            key={s.id}
            active={section === s.id}
            onClick={() => setSection(s.id)}
          >
            {s.label}
          </Pill>
        ))}
      </Row>

      <Divider />

      {section === "summary" ? <SummarySection /> : null}
      {section === "duo" ? <DuoSection /> : null}
      {section === "compat" ? <CompatSection /> : null}
      {section === "coach" ? <CoachSection /> : null}
      {section === "continuity" ? <ContinuitySection /> : null}
      {section === "ipad" ? <IPadSection /> : null}
      {section === "perf" ? <PerfSection /> : null}
      {section === "roadmap" ? <RoadmapSection /> : null}
      {section === "testing" ? <TestingSection /> : null}
      {section === "answers" ? <AnswersSection /> : null}

      <Spacer />
      <Text size="small" tone="tertiary">
        Sources: Apple Support tech specs, developer.apple.com/iphone-duo/prepare,
        HIG Designing for iPhone Duo, ReservedRegion docs, Tech Talk 111461.
        Size-class point tables labeled where measured on simulator (not Apple
        published points). Host theme active: {String(Boolean(theme.bg.editor))}.
      </Text>
    </Stack>
  );
}

function SummarySection() {
  return (
    <Stack gap={16}>
      <H2>1. Executive Summary</H2>
      <Grid columns={4} gap={12}>
        <Stat value="Partial" label="Duo readiness today" tone="warning" />
        <Stat value="Missing" label="Reconnect baseline on tree" tone="danger" />
        <Stat value="None" label="Size-class adaptive UI" tone="warning" />
        <Stat value="High" label="UIScreen.main layout risk" tone="danger" />
      </Grid>

      <Text>
        VisionPlay can run on iPhone Duo as a standard iPhone app, but it is not
        Duo-optimized. Coach Remote already uses a full-screen TAP surface that
        should work reasonably on compact outer display. The largest gaps are:
        (1) Partner reconnect baseline not present on this branch/main, (2)
        extensive <Code>UIScreen.main</Code> sizing in legacy display paths, (3)
        zero size-class / reserved-region adaptation, and (4) SDK generation —
        Apple documents that iOS 26 SDK builds letterbox on Duo’s inner display.
      </Text>

      <H3>Highest-priority findings</H3>
      <Stack gap={10}>
        <FindingCard
          title="Reconnect baseline not in working tree / main"
          kind="confirmed"
          file="7c90581 only on troubleshoot/hotspot-disconnect-appstore"
        >
          Same-room retained reconnect, same-token replace, 15-min empty-room
          grace, and HotspotBaselineLog exist only on the baseline branch. Current
          recycle paths can mint a new room (new join code) after socket loss.
        </FindingCard>
        <FindingCard
          title="No size-class based layout anywhere"
          kind="confirmed"
          file="rg horizontalSizeClass|verticalSizeClass → 0 matches"
        >
          Apple’s Duo prepare guidance requires adapting by available space / size
          classes. VisionPlay switches on UIDevice idiom (.phone/.pad) instead.
          Inner Duo display reports regular×regular — which can incorrectly take
          “iPad” layout paths if gated only on regular width or pad idiom.
        </FindingCard>
        <FindingCard
          title="Heavy UIScreen.main geometry"
          kind="confirmed"
          file="ContentView.swift ~6473–8565; FootballScanningAIApp.swift 33,46,61; TwoMinuteSlotPositions.swift 37"
        >
          Apple explicitly warns that UIScreen.main is ambiguous on multi-display
          devices and size can change mid-session on fold/unfold. PBA drill
          GeometryReader paths are better; legacy ContentView training is not.
        </FindingCard>
        <FindingCard
          title="Coach Remote TAP is already full-bleed"
          kind="supported"
          file="CoachSessionView.swift 173–281"
        >
          Full-screen contentShape + tap/swipe gestures, status line + optional
          rep header at top. Good baseline for one-handed coach use. Still needs
          fold/safe-area verification on physical Duo.
        </FindingCard>
      </Stack>
    </Stack>
  );
}

function DuoSection() {
  return (
    <Stack gap={16}>
      <H2>2. Verified iPhone Duo Technical Requirements</H2>

      <H3>Officially documented (Apple)</H3>
      <Table
        headers={["Topic", "Verified detail", "Source"]}
        rows={[
          [
            "Outer display",
            "5.4″ OLED, 1398×2034 px @ 460 ppi",
            "support.apple.com/148588",
          ],
          [
            "Inner display",
            "7.6″ OLED foldable, 1878×2670 px @ 430 ppi",
            "support.apple.com/148588",
          ],
          [
            "Closed / open size",
            "Closed 84.1×117.8×11.3 mm; open 164.6×117.8×5.2 mm",
            "Apple Support tech specs",
          ],
          [
            "SDK resize behavior",
            "iOS 26 SDK: letterboxed when open. iOS 27: fills most inner display. iOS 27.1+: full display + vertical bars",
            "developer.apple.com/iphone-duo/prepare",
          ],
          [
            "Do not use UIScreen.main for size",
            "Size from view/window; re-read on change; GeometryReader / onGeometryChange",
            "Prepare for iPhone Duo",
          ],
          [
            "Do not layout from orientation",
            "Inner display does not honor supported orientations the same way; compare bounds / use size classes",
            "Prepare + Tech Talk 111461",
          ],
          [
            "Size classes / idiom",
            "Any size-class combo possible; don’t treat regular width as iPad-only; don’t gate layout on phone/pad idiom",
            "Prepare for iPhone Duo",
          ],
          [
            "Safe areas + reserved regions",
            "Keep interactive controls in safe area; ReservedRegion occlusion (camera/island) + division (fold)",
            "HIG + ReservedRegion docs",
          ],
          [
            "UIRequiresFullScreen",
            "Still honored, but app still resizes when Duo opens/closes",
            "Tech Talk 111461",
          ],
          [
            "Adaptive containers",
            "NavigationSplitView, TabView, sheets adapt; ArrangementView for primary/secondary across fold",
            "HIG / ArrangementView",
          ],
        ]}
        rowTone={[
          "info",
          "info",
          "info",
          "warning",
          "warning",
          "warning",
          "warning",
          "info",
          "info",
          "info",
        ]}
      />

      <H3>Size classes / points</H3>
      <Row gap={8} style={{ alignItems: "center" }}>
        <Tag kind="inferred" />
        <Text size="small" tone="secondary">
          Point sizes below are from third-party simulator measurements (Sarunw /
          field notes), not published as official Apple point tables. Treat as
          working estimates pending Duo simulator / device confirmation.
        </Text>
      </Row>
      <Table
        headers={["Pose", "Orientation", "H", "V", "Approx. points"]}
        rows={[
          ["Folded (outer)", "Portrait", "Compact", "Regular", "466 × 678"],
          ["Folded (outer)", "Landscape", "Compact", "Compact", "678 × 466"],
          ["Half-open / Open", "Portrait", "Regular", "Regular", "669 × 951"],
          ["Half-open / Open", "Landscape", "Regular", "Regular", "951 × 669"],
        ]}
      />

      <H3>Inferred from standard iOS behavior</H3>
      <Text size="small">
        Scene/window resize on fold should fire geometry updates similar to Split
        View / Stage Manager. Background/foreground lifecycle should behave like
        other iPhones. Brightness APIs remain UIScreen-scoped (ambiguous on
        multi-display).
      </Text>

      <H3>Unknowns requiring physical-device testing</H3>
      <Row gap={8} style={{ alignItems: "center" }}>
        <Tag kind="device" />
        <Text size="small">
          Exact safe-area asymmetry with vertical system bars; active vs inactive
          fold division region while coaching; whether coach phone typically stays
          folded vs open on the field; tent/laptop pose usability for TAP; camera
          occlusion on outer display; battery impact of Partner Mode + haptics;
          App Store Duo badge/screenshot requirements.
        </Text>
      </Row>
    </Stack>
  );
}

function CompatSection() {
  return (
    <Stack gap={16}>
      <H2>3. Current Application Compatibility Assessment</H2>

      <H3>Project / scene baseline</H3>
      <Table
        headers={["Setting", "Current value", "Duo implication"]}
        rows={[
          [
            "App IPHONEOS_DEPLOYMENT_TARGET",
            "18.0 (target Debug/Release)",
            "Runs on Duo; SDK used to build matters more for resize.",
          ],
          [
            "Project LastUpgradeCheck",
            "2620 (Xcode 26 lineage)",
            "If shipping with iOS 26 SDK: letterboxed on open Duo per Apple.",
          ],
          [
            "TARGETED_DEVICE_FAMILY",
            "1,2 (iPhone + iPad)",
            "Good — Duo is iPhone family; iPad display still required.",
          ],
          [
            "iPhone orientations",
            "Portrait + Landscape L/R",
            "Outer landscape supported. Do not use orientation for layout.",
          ],
          [
            "iPad orientations",
            "All four",
            "Player display OK. Keep GeometryReader-based drill math.",
          ],
          [
            "Scene",
            "Single WindowGroup (FootballScanningAIApp.swift 50–63)",
            "Simple; mid-session size change must not recreate session owners.",
          ],
          [
            "Navigation",
            "NavigationStack(path:) via AppRouter (ContentView ~998)",
            "Protect path from onAppear resets during resize.",
          ],
        ]}
      />

      <H3>Adaptive vs fixed layout signals</H3>
      <Stack gap={10}>
        <FindingCard
          title="Zero size-class environment usage"
          kind="confirmed"
          file="FootballScanningAI/**/*.swift"
        >
          No horizontalSizeClass / verticalSizeClass reads. Layout cannot follow
          Apple’s recommended compact-outer / regular-inner adaptation.
        </FindingCard>
        <FindingCard
          title="Idiom-gated coach/player roles"
          kind="risk"
          file="CoachRemoteSessionStartGate.swift 11–18; ContentView.swift 684,711,854+"
        >
          isPadPlayerRole() requires .pad idiom. Duo is .phone, so coach-on-Duo is
          fine. Risk is any UI that assumes “regular width ⇒ pad player display
          layout” or that phone is always compact.
        </FindingCard>
        <FindingCard
          title="PBA drills mostly GeometryReader-based"
          kind="supported"
          file="TwoMinuteCriticalScanSessionView.swift ~1634; AwayFromPressureDisplaySessionView.swift ~1266"
        >
          Ball/slot math prefers GeometryReader size + safeAreaInsets. Legacy
          positionsForCurrentScreen() still exists but has no callers.
        </FindingCard>
        <FindingCard
          title="Legacy ContentView still UIScreen-bound"
          kind="confirmed"
          file="ContentView.swift 6473–8565 (many)"
        >
          Critical-scan-era layouts position with UIScreen.main.bounds. Mid-session
          fold would leave stale geometry until next read — Apple calls this out
          explicitly.
        </FindingCard>
        <FindingCard
          title="Dynamic Type"
          kind="risk"
          file="Widespread .font(.system(size: N))"
        >
          Mix of semantic fonts (CoachSessionView title3/largeTitle) and many fixed
          point sizes. Large Dynamic Type on compact outer may clip coach chrome.
        </FindingCard>
      </Stack>

      <Callout tone="info" title="Verdict">
        VisionPlay is a traditional iPhone+iPad SwiftUI app with good GeometryReader
        habits in PBA V2 display drills, but it assumes stable phone/pad dimensions
        and does not yet implement Duo adaptive layout. Compatibility today:
        functional on outer display with letterbox risk when open if built with
        pre-27.1 SDK; Coach Remote usable; Partner reconnect not at field-tested
        baseline on this tree.
      </Callout>
    </Stack>
  );
}

function CoachSection() {
  return (
    <Stack gap={16}>
      <H2>4. Coach Remote Findings (Highest Priority)</H2>
      <Text tone="secondary">
        Primary Duo role: Coach Remote controlling iPad player display. Shared
        surface is CoachSessionView; activity wrappers are TwoMinute / AFP / DOP /
        OTP CoachRemote views.
      </Text>

      <Table
        headers={["Criterion", "Assessment", "Evidence", "Label"]}
        rows={[
          [
            "A. TAP sizing / placement",
            "Full-screen tap target; prompt centered via Spacers",
            "CoachSessionView.swift 173–281, 714–735",
            "ALREADY SUPPORTED",
          ],
          [
            "B. One-handed operation",
            "Large central TAP; may feel sparse when Duo open (tall regular)",
            "CoachSessionView VStack + Spacer(minLength: 48)",
            "POTENTIAL RISK",
          ],
          [
            "C. Reachability",
            "Tap anywhere; swipe for direction; nav back hidden in live drill",
            "hidesNavigationBackDuringLivePartnerDrill 115–119",
            "ALREADY SUPPORTED",
          ],
          [
            "D. Rep counter visibility",
            "Optional block progress; partner timed often hides counter",
            "showsBlockRepProgress; PartnerLinkPassiveStatusLine 188",
            "POTENTIAL RISK",
          ],
          [
            "E. Connection status",
            "Passive status line + reconnect waiting views on all 4 remotes",
            "PartnerRelayDisplayContracts; *CoachRemoteView ~316–328",
            "ALREADY SUPPORTED",
          ],
          [
            "F. Reconnecting indicators",
            "Present, weaker than baseline (no transient link-loss flag)",
            "isPartnerRelayReconnecting / isMidSessionPartnerDisconnect",
            "CONFIRMED ISSUE vs baseline",
          ],
          [
            "G. Navigation",
            "Hub → activity remote; Done / role switch; live drill suppresses back",
            "CoachRemoteHubView; CoachTrainingContainerView",
            "ALREADY SUPPORTED",
          ],
          [
            "H. Text readability",
            "largeTitle bold on black; fixed sizes may not scale",
            "statusText / PulsingTapToStartPrompt",
            "POTENTIAL RISK",
          ],
          [
            "I. Landscape",
            "Spacers reflow; compact×compact outer landscape is short",
            "No landscape-specific coach layout",
            "REQUIRES DEVICE TESTING",
          ],
          [
            "J. Dimension changes",
            "SwiftUI reflows; .id remount is intentional for rep input reset",
            "TwoMinuteCoachRemoteView.swift ~361",
            "POTENTIAL RISK",
          ],
          [
            "K. Touch targets",
            "Full-screen ≥ 44pt; escalating haptics while waiting",
            "CoachTapInputGuard 0.65s",
            "ALREADY SUPPORTED",
          ],
          [
            "L. Clip / obscure",
            "ignoresSafeArea black bg; not fold-aware; vertical bars steal edge",
            "CoachSessionView 175–176; Apple prepare",
            "REQUIRES DEVICE TESTING",
          ],
        ]}
      />

      <H3>Shared components inspected</H3>
      <Text size="small">
        CoachRemoteHubView, CoachRemoteHubRelayPairingView,
        CoachRemoteSessionStartGate, CoachSessionView,
        CoachRemoteConnectionStatusView, CoachRemoteDirectionZoneInput (not the
        live TAP path), CoachRepFlowDecoupling / CoachTapInputGuard, four activity
        CoachRemote views.
      </Text>

      <Callout tone="success" title="Redesign not required">
        Do not redesign Coach Remote for Duo. Prefer: keep full-screen TAP; ensure
        status + reconnect chrome stay inside safe area; optional bottom-weighted
        TAP cue on tall layouts; never remount session owners on geometry change.
      </Callout>
    </Stack>
  );
}

function ContinuitySection() {
  return (
    <Stack gap={16}>
      <H2>5. Partner Session Continuity Risks</H2>

      <Callout tone="danger" title="Critical: working tree ≠ field-tested baseline">
        Baseline <Code>7c90581</Code> added retained same-room WebSocket reconnect,
        mid-session non-destructive reconnecting UI, same-token socket replace on
        relay, and 15-minute empty-room grace. This working tree / main still uses
        DISPLAY_ALREADY_CONNECTED / COACH_ALREADY_CONNECTED rejection and 5-minute
        grace, and can regenerate a new display room after unexpected disconnect.
      </Callout>

      <H3>System ownership (good patterns)</H3>
      <Stack gap={10}>
        <FindingCard
          title="Coordinator is a process singleton"
          kind="supported"
          file="TrainingPartnerConnectionCoordinator.shared"
        >
          Coach remotes use @ObservedObject on shared coordinator — ownership is
          independent of individual view lifetime. AppRouter + MultipeerManager are
          @StateObject at app root.
        </FindingCard>
        <FindingCard
          title="Rep index owned by parent coach remote"
          kind="supported"
          file="CoachSessionView.swift 54–56, 156–157; CoachTapInputGuard"
        >
          CoachSessionView does not own the authoritative rep counter. Tap debounce
          survives .id remounts via CoachTapInputGuard static state.
        </FindingCard>
        <FindingCard
          title="Background vs inactive discrimination exists"
          kind="supported"
          file="SessionStartCueRepGate.swift 41–141; coordinator lifecycle observers"
        >
          didEnterBackground is distinguished from inactive — good for avoiding
          false session ends on transient interruptions.
        </FindingCard>
      </Stack>

      <H3>Concrete continuity risks on THIS tree</H3>
      <Table
        headers={["Risk", "Mechanism", "Could cause", "Label"]}
        rows={[
          [
            "Missing same-token replace",
            "relay/src/roomStore.js attachSocket rejects second socket (144–165)",
            "Hotspot reconnect fails with ALREADY_CONNECTED",
            "CONFIRMED ISSUE",
          ],
          [
            "Shorter empty-room grace",
            "EMPTY_ROOM_GRACE_MS default 5 min vs baseline 15 min",
            "Room deleted during longer walk-away",
            "CONFIRMED ISSUE",
          ],
          [
            "No retained coach WS config",
            "Absent vs baseline coordinator",
            "Cannot reconnect same room without POST /join",
            "CONFIRMED ISSUE",
          ],
          [
            "Recycle mints new room",
            "recycle…KeepingPartnerRun → forceRegenerate… → resetSession (coord ~541–574; PartnerRelayDisplaySession ~261–286)",
            "New join code mid-run; coach may return to pairing",
            "CONFIRMED ISSUE",
          ],
          [
            "Expired join recovery",
            "recoverCoachRelayStateAfterExpiredJoinCode (289–298)",
            "Correct for real expiry; dangerous on false positive",
            "POTENTIAL RISK",
          ],
          [
            "Coach onAppear begin session",
            "TwoMinuteCoachRemoteView.swift ~181–197",
            "Should no-op if already active — verify under fold remount",
            "POTENTIAL RISK",
          ],
          [
            ".id(coachSessionInputResetToken)",
            "Resets CoachSessionView phase/UI",
            "If geometry bumps token, TAP state resets (rep should survive)",
            "POTENTIAL RISK",
          ],
          [
            "Reachability not wired to Partner reconnect",
            "Only ContentView sync retry (~1211)",
            "Path restore after hotspot may not aggressively reattach",
            "CONFIRMED ISSUE vs baseline",
          ],
        ]}
        rowTone={[
          "danger",
          "danger",
          "danger",
          "danger",
          "warning",
          "warning",
          "warning",
          "danger",
        ]}
      />

      <Callout tone="warning" title="Do not modify reconnect while doing Duo layout">
        Any Duo-facing UI change must keep TrainingPartnerConnectionCoordinator,
        WebSocket transport, and relay room identity untouched until the baseline
        is merged and re-verified on hotspot walk-away.
      </Callout>
    </Stack>
  );
}

function IPadSection() {
  return (
    <Stack gap={16}>
      <H2>6. iPad Player Display Considerations</H2>
      <Text>
        Duo work targets Coach Remote on iPhone. iPad remains the player display
        for Two-Minute Test, Away From Pressure, Dribble or Pass, and One-Touch
        Passing.
      </Text>

      <Stack gap={10}>
        <FindingCard
          title="Drill geometry is largely isolated via GeometryReader"
          kind="supported"
          file="TwoMinuteCriticalScanSessionView ~1634–1700; AFP/DOP/OTP DisplaySessionView"
        >
          Ball side length and slot positions derive from geo.size +
          safeAreaInsets. Prefer keeping Duo coach changes out of these files.
        </FindingCard>
        <FindingCard
          title="Legacy UIScreen paths still in ContentView"
          kind="risk"
          file="ContentView.swift UIScreen.main.bounds positioning"
        >
          If shared helpers are modernized globally for Duo, avoid changing iPad
          cue timing / animation geometry. Scope UIScreen replacements per surface.
        </FindingCard>
        <FindingCard
          title="Soft reconnect rep restart notifications"
          kind="risk"
          file=".partnerSoftReconnectRepRestart; isPartnerSoftReconnectRepRestartSuppressed"
        >
          Display and coach both observe soft-reconnect restart. Layout remounts
          must not double-fire these.
        </FindingCard>
      </Stack>

      <H3>Isolation recommendations</H3>
      <Table
        headers={["Strategy", "Why"]}
        rows={[
          [
            "Change only Coach* / PartnerLink chrome files first",
            "Avoid DisplaySessionView / engine / slot math churn",
          ],
          [
            "Gate Duo polish on size class + role, not idiom alone",
            "Inner Duo is regular×regular but still coach phone (.phone)",
          ],
          [
            "Never share UIScreen→Geometry refactors into ball positioning without iPad regression tests",
            "Timing and geometry are field-sensitive",
          ],
          [
            "Keep TimedSessionController / CurrentSessionStore APIs stable",
            "Session continuity depends on them during soft resume",
          ],
        ]}
      />
    </Stack>
  );
}

function PerfSection() {
  return (
    <Stack gap={16}>
      <H2>7. Performance Findings</H2>
      <Table
        headers={["Topic", "Evidence", "Label"]}
        rows={[
          [
            "View reconstruction from .id remounts",
            "coachSessionInputResetToken rebuilds CoachSessionView — intentional; avoid geometry-tied remounts",
            "POTENTIAL RISK",
          ],
          [
            "Many onChange handlers on CoachSessionView",
            "phase, rep, transport, countdown, session, disconnect, timed, beep arm (313–378)",
            "POTENTIAL RISK",
          ],
          [
            "Escalating haptic loop while waiting TAP",
            "CoachWaitingRepHapticKit — battery on long waits",
            "POTENTIAL RISK",
          ],
          [
            "Idle timer disabled + max brightness",
            "FootballScanningAIApp.swift 21–46 — outdoor training by design",
            "ALREADY SUPPORTED",
          ],
          [
            "Duplicate connection init",
            "beginPartnerTrainingSessionIfNeeded no-ops when active (876+)",
            "ALREADY SUPPORTED",
          ],
          [
            "Main-thread Combine sink for mid-session link",
            "subscribeMidSessionPartnerLinkMonitoring merges many publishers",
            "POTENTIAL RISK",
          ],
          [
            "Confirmed animation jank on Duo fold",
            "No profiling on Duo hardware yet",
            "REQUIRES DEVICE TESTING",
          ],
        ]}
      />
      <Text size="small" tone="secondary">
        No confirmed Duo-specific performance defect in code alone; risks are
        extrapolations from existing Partner Mode patterns under resize.
      </Text>
    </Stack>
  );
}

function RoadmapSection() {
  return (
    <Stack gap={16}>
      <H2>8. Prioritized Implementation Roadmap</H2>
      <Text tone="secondary">
        Complexity: S = small localized, M = multi-file careful, L = cross-cutting /
        high regression risk.
      </Text>

      <H3>PHASE A — Essential compatibility / continuity</H3>
      <Table
        headers={["Item", "Pri", "Files", "Proposed", "Partner risk", "Cx"]}
        rows={[
          [
            "A1. Merge 7c90581 reconnect baseline",
            "Critical",
            "Coordinator, WebSocket*, PartnerRelay*, relay/*, Coach+Display remotes",
            "Restore same-room reconnect",
            "High if wrong / if skipped",
            "L",
          ],
          [
            "A2. Confirm SDK 27 / 27.1 plan",
            "Critical",
            "Xcode / CI",
            "Avoid letterbox when open",
            "Low",
            "S",
          ],
          [
            "A3. Quarantine UIScreen.main layout reads",
            "High",
            "ContentView, NavigationHelpers, legacy slot API",
            "View geometry instead",
            "Med if display math touched",
            "M",
          ],
          [
            "A4. Guard size/pose changes from ending session",
            "Critical",
            "Coordinator + CoachRemote onAppear",
            "No new room / no pairing pop on fold",
            "High if wrong",
            "M",
          ],
        ]}
        rowTone={["danger", "danger", "warning", "danger"]}
      />

      <H3>PHASE B — Coach Remote usability</H3>
      <Table
        headers={["Item", "Pri", "Files", "Improvement", "Risk", "Cx"]}
        rows={[
          [
            "B1. Safe-area status/reconnect chrome",
            "High",
            "CoachSessionView, PartnerRelayDisplayContracts",
            "Avoid bar/fold occlusion",
            "Low",
            "S",
          ],
          [
            "B2. Bottom-weighted TAP cue on tall layouts",
            "Medium",
            "CoachSessionView only",
            "One-handed comfort when open",
            "Low",
            "S",
          ],
          [
            "B3. Keep rep + connection visible in reconnect scrim",
            "High",
            "*CoachRemoteView waiting overlays",
            "Never hide session identity",
            "Med",
            "S",
          ],
          [
            "B4. Compact-height landscape chrome audit",
            "Medium",
            "CoachSessionView, Hub",
            "Prevent prompt clipping",
            "Low",
            "S",
          ],
        ]}
      />

      <H3>PHASE C — Expanded-screen enhancements</H3>
      <Table
        headers={["Item", "Pri", "Notes"]}
        rows={[
          [
            "C1. Size-class hub density (list → grid)",
            "Medium",
            "CoachRemoteHubView only",
          ],
          [
            "C2. ReservedRegion.division for book pose",
            "Low",
            "Only if coaches fold mid-session in field use",
          ],
          [
            "C3. Never show player-display layout on coach regular width",
            "High",
            "Gate on role + size class, not .pad idiom",
          ],
        ]}
      />

      <H3>PHASE D — Performance and polish</H3>
      <Table
        headers={["Item", "Pri", "Notes"]}
        rows={[
          [
            "D1. Reduce unnecessary CoachSessionView remounts",
            "Medium",
            "Audit coachSessionInputResetToken bumpers",
          ],
          [
            "D2. Haptic loop power when reconnecting / backgrounded",
            "Low",
            "Verify cancel on fold",
          ],
          [
            "D3. App Store Duo screenshots / badge",
            "Low",
            "After 27.1 SDK + layout pass",
          ],
        ]}
      />
    </Stack>
  );
}

function TestingSection() {
  return (
    <Stack gap={16}>
      <H2>9. Testing Matrix</H2>
      <Callout tone="info" title="Preserve hotspot recovery">
        Every Partner test must be run against a branch containing{" "}
        <Code>7c90581</Code> before declaring Duo work safe.
      </Callout>
      <Table
        headers={["Test", "Expected", "Failure indicators", "Sim", "Physical"]}
        rows={[
          [
            "Cold launch on Duo outer",
            "Launch; Coach Remote reachable",
            "Crash / blank window",
            "Yes",
            "Yes",
          ],
          [
            "Coach pairing",
            "Same room; hub unlocks",
            "New code each retry; slot taken loops",
            "Partial",
            "Yes",
          ],
          [
            "Start drill + several reps",
            "Rep advances; TAP/PASS/SWIPE OK",
            "Rep reset; PASS ignored; desync",
            "Yes",
            "Yes",
          ],
          [
            "Fold/unfold mid-rep",
            "No session end; same room",
            "Pairing screen; new room; Train Again",
            "Duo sim",
            "Yes",
          ],
          [
            "Orientation mid-rep",
            "Reflow; no disconnect",
            "Re-broadcast start; nav pop",
            "Yes",
            "Yes",
          ],
          [
            "Background / foreground",
            "Soft resume; same credentials",
            "Session ended; false join expiry",
            "Limited",
            "Yes",
          ],
          [
            "Network blip",
            "Reconnecting UI; recover",
            "Destructive recycle; new join code",
            "Partial",
            "Yes",
          ],
          [
            "Hotspot walk-away",
            "Same-room reconnect (7c90581)",
            "ALREADY_CONNECTED; room gone at 5 min",
            "No",
            "Mandatory",
          ],
          [
            "Correct rep continuity",
            "Matches display engine",
            "Coach ahead/behind",
            "Yes",
            "Yes",
          ],
          [
            "End / new activity / Train Again",
            "Only on explicit user action",
            "Triggered by fold/geometry",
            "Yes",
            "Yes",
          ],
          [
            "iPad display regression",
            "Ball/gates/cues unchanged",
            "Slot drift; timing change",
            "iPad sim",
            "Field",
          ],
        ]}
      />
    </Stack>
  );
}

function AnswersSection() {
  return (
    <Stack gap={16}>
      <H2>10. Direct Answers</H2>

      <Card>
        <CardHeader>1. How compatible is VisionPlay with iPhone Duo today?</CardHeader>
        <CardBody>
          <Text>
            Partially compatible. It should run as an iPhone app on the outer
            display, and Coach Remote’s full-screen TAP model is a solid fit.
            It is not Duo-optimized: no size-class adaptation, heavy UIScreen
            usage in legacy paths, likely letterboxing when open if built with
            iOS 26 SDK, and — on this working tree — Partner reconnect is not the
            field-tested baseline.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>2. What absolutely must change?</CardHeader>
        <CardBody>
          <Text>
            1) Align shipping code with reconnect baseline <Code>7c90581</Code>{" "}
            before Duo UI work. 2) Ensure mid-session size/pose changes cannot
            mint a new room, clear credentials, or pop to pairing. 3) Stop using
            UIScreen.main for layout (keep GeometryReader for drills). 4) Plan
            SDK 27/27.1 for native Duo resize. 5) Do not treat regular width as
            iPad player UI when role is coach.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>3. What would make Coach Remote substantially better on Duo?</CardHeader>
        <CardBody>
          <Text>
            Keep full-screen TAP; pin connection + rep chrome in safe areas across
            outer/inner/landscape; slightly bottom-weight the TAP prompt on tall
            open layouts; make reconnect scrims non-destructive and always show
            session identity; optionally densify the hub when open — without
            rearranging the TAP interaction model.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>4. Highest-risk changes to working Partner Mode?</CardHeader>
        <CardBody>
          <Text>
            Any edit to TrainingPartnerConnectionCoordinator, WebSocketRemoteTransport,
            PartnerRelayDisplaySession recycle/reset, relay attachSocket / empty-room
            grace, coach onAppear session start / Train Again paths, or bumping
            coachSessionInputResetToken from geometry. Also merging Duo layout into
            DisplaySessionView ball/cue code.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>5. Smallest, safest first implementation step?</CardHeader>
        <CardBody>
          <Stack gap={10}>
            <Text weight="semibold">
              Bring <Code>7c90581</Code> Partner reconnect baseline onto the
              intended shipping branch and re-run the physical hotspot walk-away
              matrix — with zero Duo layout changes in that PR.
            </Text>
            <Text size="small" tone="secondary">
              Only after that green: a coach-only safe-area / status-chrome pass in
              CoachSessionView + PartnerLinkPassiveStatusLine (no coordinator, no
              relay, no display drill files).
            </Text>
          </Stack>
        </CardBody>
      </Card>

      <Callout tone="success" title="Awaiting approval">
        Audit complete. No implementation performed. Waiting for approval before
        any Phase A–D work.
      </Callout>
    </Stack>
  );
}
