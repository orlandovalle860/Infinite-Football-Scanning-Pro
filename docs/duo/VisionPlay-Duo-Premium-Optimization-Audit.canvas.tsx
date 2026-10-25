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
  | "folded"
  | "unfolded"
  | "adaptive"
  | "partner"
  | "ipad"
  | "ux"
  | "perf"
  | "roadmap"
  | "field"
  | "answers";

const SECTIONS: { id: SectionId; label: string }[] = [
  { id: "summary", label: "1. Summary" },
  { id: "duo", label: "2. Duo Specs" },
  { id: "compat", label: "3. Compatibility" },
  { id: "folded", label: "4. Folded" },
  { id: "unfolded", label: "5. Unfolded" },
  { id: "adaptive", label: "6. Adaptive" },
  { id: "partner", label: "7. Partner" },
  { id: "ipad", label: "8. iPad" },
  { id: "ux", label: "9. Premium UX" },
  { id: "perf", label: "10. Perf" },
  { id: "roadmap", label: "11. Roadmap" },
  { id: "field", label: "12. Field Test" },
  { id: "answers", label: "13. Answers" },
];

function Tag({
  kind,
}: {
  kind: "confirmed" | "risk" | "supported" | "device" | "inferred";
}) {
  const map = {
    confirmed: "CONFIRMED ISSUE",
    risk: "POTENTIAL RISK",
    supported: "ALREADY SUPPORTED",
    device: "REQUIRES PHYSICAL DEVICE TESTING",
    inferred: "INFERRED / 3RD-PARTY",
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

export default function VisionPlayDuoPremiumAudit() {
  const theme = useHostTheme();
  const [section, setSection] = useCanvasState<SectionId>("section", "summary");

  return (
    <Stack gap={20} style={{ padding: 24, maxWidth: 1120 }}>
      <Stack gap={6}>
        <H1>VisionPlay — iPhone Duo Premium Optimization Audit</H1>
        <Text tone="secondary">
          Phase 1 read-only. No code, settings, commits, merges, or deploys.
          Tree: <Code>cursor/fix-short-beep-resource-9172</Code> @{" "}
          <Code>709a6d4</Code>. Protect reconnect baseline{" "}
          <Code>7c90581</Code> (
          <Code>troubleshoot/hotspot-disconnect-appstore</Code>).
        </Text>
      </Stack>

      <Callout tone="danger" title="Blocking: reconnect baseline not on this tree">
        <Code>7c90581</Code> is not an ancestor of HEAD and is not on{" "}
        <Code>origin/main</Code>. Coordinator is 1566 lines here vs 2430 on
        baseline. Relay still rejects same-token reconnect (
        <Code>DISPLAY_ALREADY_CONNECTED</Code> / <Code>COACH_ALREADY_CONNECTED</Code>
        ). Empty-room grace is 5 min vs baseline 15. Recycle can mint a new room.
        Premium Duo UI must not ship ahead of restoring this baseline.
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
      {section === "folded" ? <FoldedSection /> : null}
      {section === "unfolded" ? <UnfoldedSection /> : null}
      {section === "adaptive" ? <AdaptiveSection /> : null}
      {section === "partner" ? <PartnerSection /> : null}
      {section === "ipad" ? <IPadSection /> : null}
      {section === "ux" ? <UXSection /> : null}
      {section === "perf" ? <PerfSection /> : null}
      {section === "roadmap" ? <RoadmapSection /> : null}
      {section === "field" ? <FieldSection /> : null}
      {section === "answers" ? <AnswersSection /> : null}

      <Spacer />
      <Text size="small" tone="tertiary">
        Sources: Apple Support 148588; developer.apple.com/iphone-duo/prepare;
        HIG Designing for iPhone Duo; ReservedRegion; Tech Talk 111461. Point
        tables from third-party Duo simulator measurements — not Apple-published
        points. Theme: {String(Boolean(theme.bg.editor))}.
      </Text>
    </Stack>
  );
}

function SummarySection() {
  return (
    <Stack gap={16}>
      <H2>1. Executive Summary</H2>
      <Grid columns={4} gap={12}>
        <Stat value="~35%" label="Premium Duo readiness" tone="warning" />
        <Stat value="Missing" label="Reconnect baseline" tone="danger" />
        <Stat value="Strong" label="Full-screen TAP foundation" tone="success" />
        <Stat value="Hidden" label="Rep counter on timed coach" tone="danger" />
      </Grid>

      <Text>
        VisionPlay already has the right Coach Remote interaction model for a
        field instrument: full-screen TAP/PASS/SWIPE on black, escalating wait
        haptics, and live-drill back suppression. It is not yet a purpose-built
        Duo product. Folded experience needs safer chrome (rep + connection
        glanceable outdoors). Unfolded experience currently stretches the same
        single-column layout. Partner Mode on this tree is behind the
        field-tested hotspot baseline — that is the first gate before athlete
        testing.
      </Text>

      <H3>Top findings</H3>
      <Stack gap={10}>
        <FindingCard
          title="Timed Partner coach hides Rep X of Y"
          kind="confirmed"
          file="TimedSessionDisplayIntegration.swift:61 showsCoachBlockRepProgress = false"
        >
          All four activity coach remotes pass this flag into CoachSessionView.
          On the field, coaches lose glanceable rep identity unless they infer
          from phase text alone.
        </FindingCard>
        <FindingCard
          title="Full-screen TAP is already instrument-grade"
          kind="supported"
          file="CoachSessionView.swift 173–281, 400–437, 714–751"
        >
          Entire surface is the control. Debounce via CoachTapInputGuard (0.65s).
          Valid-tap scale/opacity flash. Escalating light→heavy wait haptics.
          Premium work should refine hierarchy, not replace the model.
        </FindingCard>
        <FindingCard
          title="No size-class / ReservedRegion adaptation"
          kind="confirmed"
          file="Zero matches for horizontalSizeClass, ArrangementView, ReservedRegion"
        >
          Unfolded Duo (regular×regular) gets the same layout as folded compact.
          Apple expects compact-outer / regular-inner adaptation.
        </FindingCard>
        <FindingCard
          title="Reconnect baseline absent from shipping line"
          kind="confirmed"
          file="7c90581 only on troubleshoot/hotspot-disconnect-appstore"
        >
          Same-room retained reconnect, same-token replace, 15-min grace missing
          from this tree and origin/main.
        </FindingCard>
      </Stack>
    </Stack>
  );
}

function DuoSection() {
  return (
    <Stack gap={16}>
      <H2>2. Verified Duo Technical Specifications</H2>
      <Table
        headers={["Topic", "Detail", "Class"]}
        rows={[
          [
            "Outer display",
            "5.4″ OLED, 1398×2034 px @ 460 ppi",
            "VERIFIED (Apple Support)",
          ],
          [
            "Inner display",
            "7.6″ OLED foldable, 1878×2670 px @ 430 ppi",
            "VERIFIED",
          ],
          [
            "Closed / open hardware size",
            "84.1×117.8×11.3 mm closed; 164.6×117.8×5.2 mm open",
            "VERIFIED",
          ],
          [
            "SDK resize",
            "iOS 26 SDK letterboxes when open; 27 fills most; 27.1+ full + vertical bars",
            "VERIFIED (prepare page)",
          ],
          [
            "Layout rules",
            "No UIScreen.main size; no orientation-driven layout; size classes / bounds; safe area; ReservedRegion occlusion+division",
            "VERIFIED",
          ],
          [
            "Idiom / size class",
            "Any size-class combo; don’t treat regular width as iPad-only",
            "VERIFIED",
          ],
          [
            "Approx. points (folded portrait)",
            "466×678 compact×regular",
            "INFERRED (3rd-party sim)",
          ],
          [
            "Approx. points (open portrait)",
            "669×951 regular×regular",
            "INFERRED (3rd-party sim)",
          ],
          [
            "Coach field pose preference",
            "Likely folded one-handed; open as console between reps",
            "UNKNOWN — measure with owner",
          ],
          [
            "Outdoor contrast / vertical bar insets on Duo",
            "Must measure safeArea + status strip on device",
            "UNKNOWN",
          ],
        ]}
        rowTone={[
          "info",
          "info",
          "info",
          "warning",
          "warning",
          "warning",
          "neutral",
          "neutral",
          "neutral",
          "neutral",
        ]}
      />
    </Stack>
  );
}

function CompatSection() {
  return (
    <Stack gap={16}>
      <H2>3. Current App Compatibility</H2>
      <Table
        headers={["Item", "Current", "Implication"]}
        rows={[
          ["Deployment target (app)", "18.0", "Runs on Duo; build SDK drives resize"],
          ["LastUpgradeCheck", "2620 (Xcode 26 lineage)", "Likely letterbox when open until 27/27.1 SDK"],
          ["Device family", "1,2 iPhone+iPad", "Correct for Duo coach + iPad display"],
          ["iPhone orientations", "Portrait + L/R landscape", "OK; don’t layout from orientation"],
          ["Scene", "Single WindowGroup App.swift 50–63", "Keep session owners outside view rebuilds"],
          ["Navigation", "NavigationStack + AppRouter (~ContentView 998)", "Path must survive resize"],
          ["Size classes", "None used", "CONFIRMED ISSUE for Duo"],
          ["UIScreen.main layout", "Heavy in ContentView 6473–8565", "CONFIRMED ISSUE"],
          ["PBA drill geometry", "GeometryReader in display sessions", "ALREADY SUPPORTED"],
          ["Brightness / idle", "UIScreen.main.brightness=1; idleTimerDisabled", "Outdoor intent; multi-display brightness ambiguous"],
        ]}
      />
    </Stack>
  );
}

function FoldedSection() {
  return (
    <Stack gap={16}>
      <H2>4. Folded Field Controller Assessment</H2>
      <Text tone="secondary">
        Primary athlete-side use: one-handed coach, eyes mostly on the player.
      </Text>

      <Table
        headers={["Lens", "Assessment", "Evidence", "Label"]}
        rows={[
          [
            "TAP size",
            "Entire screen is the hit target — excellent",
            "CoachSessionView 269–281 contentShape + TapGesture",
            "ALREADY SUPPORTED",
          ],
          [
            "TAP placement / look-down",
            "Prompt is vertically centered; thumb comfort OK because whole surface taps, but cue sits mid-screen",
            "Spacer(minLength: 48) then prompt then Spacer 200–249",
            "POTENTIAL RISK",
          ],
          [
            "Eyes-free reliability",
            "Strong: full-screen + escalating wait haptics + PASS rigid double-pulse elsewhere",
            "Haptic loop 622–668; CoachRemoteHaptics 49–81",
            "ALREADY SUPPORTED",
          ],
          [
            "Accidental activation",
            "0.65s start-rep debounce; phase guards ignore taps in waitingBeep",
            "CoachTapInputGuard; handleTap 400–437",
            "ALREADY SUPPORTED",
          ],
          [
            "Visual response",
            "Brief whole-view scale 0.985 + opacity flash (~100ms)",
            "266–268, 568–576",
            "ALREADY SUPPORTED",
          ],
          [
            "Rep visibility",
            "OFF for timed Partner (showsCoachBlockRepProgress=false)",
            "TimedSessionDisplayIntegration.swift:61",
            "CONFIRMED ISSUE",
          ],
          [
            "Activity name",
            "Header subheadline 70% white — readable but secondary",
            "CoachSessionView 181–187",
            "POTENTIAL RISK outdoors",
          ],
          [
            "Connection status",
            "Caption 60% opacity; hidden during mid-session disconnect overlay",
            "PartnerLinkPassiveStatusLine 186–198; formatting 359–391",
            "POTENTIAL RISK",
          ],
          [
            "Reconnect clarity",
            "Reconnecting/Restoring banners exist; weaker than baseline transient link-loss",
            "PartnerRelayLifecycleBannerOverlay; isPartnerRelayReconnecting",
            "CONFIRMED ISSUE vs baseline",
          ],
          [
            "Destructive actions",
            "Nav back hidden during live partner drill; disconnect behind confirm on hub",
            "115–119; CoachRemoteHubView 167–179",
            "ALREADY SUPPORTED",
          ],
          [
            "Outdoor contrast",
            "Black + white largeTitle is good; status/header under-emphasized; color-only green/blue banners",
            "bannerBackground 140–151",
            "REQUIRES PHYSICAL DEVICE TESTING",
          ],
        ]}
      />

      <H3>Recommended premium folded layout (do not implement yet)</H3>
      <Card>
        <CardHeader>Field Controller visual hierarchy</CardHeader>
        <CardBody>
          <Stack gap={8}>
            <Text size="small">
              1. TOP SAFE BAND (non-interactive): activity short name · Rep N ·
              connection pill (Connected / Reconnecting / Disconnected) with icon
              + text, not color alone.
            </Text>
            <Text size="small">
              2. PRIMARY ACTION ZONE (majority of height): keep full-screen
              hit-testing; move the visible TAP/PASS/SWIPE cue slightly
              lower-third for thumb geography while walking.
            </Text>
            <Text size="small">
              3. HAPTICS: keep wait escalation + accepted-tap flash; ensure
              reconnect cancels nagging haptics (already partially gated).
            </Text>
            <Text size="small">
              4. NAV: keep back suppressed during live partner; End Session only
              via explicit control away from TAP center.
            </Text>
            <Text size="small">
              5. CODE TOUCH: primarily CoachSessionView +
              PartnerLinkPassiveStatusLine + TimedSessionDisplayIntegration
              (enable glanceable rep). No coordinator/relay edits.
            </Text>
            <Text size="small">
              6. RISK: low if presentation-only; medium if rep counter drives
              wrong totalReps wrapping — reuse existing currentRepOneBased only.
            </Text>
          </Stack>
        </CardBody>
      </Card>
    </Stack>
  );
}

function UnfoldedSection() {
  return (
    <Stack gap={16}>
      <H2>5. Unfolded Coaching Console Assessment</H2>
      <Callout tone="warning" title="Current behavior">
        Unfolded Duo will present the same single-column CoachSessionView stretched
        into regular×regular space. That feels sparse, not console-grade.
      </Callout>

      <H3>Recommended intentional console (concept)</H3>
      <Grid columns={2} gap={12}>
        <Card>
          <CardHeader>CONTROL REGION (primary)</CardHeader>
          <CardBody>
            <Stack gap={6}>
              <Text size="small">Large TAP/PASS/SWIPE surface (reuse CoachSessionView gestures).</Text>
              <Text size="small">Immediate connection chip.</Text>
              <Text size="small">Phase word remains dominant (TAP TO START / PASS / SWIPE NOW).</Text>
              <Text size="small">No extra buttons that compete with TAP.</Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>INFORMATION REGION (secondary)</CardHeader>
          <CardBody>
            <Stack gap={6}>
              <Text size="small">Activity name + short coaching context.</Text>
              <Text size="small">Rep progress (N, or N of block when meaningful).</Text>
              <Text size="small">Session timer / remaining if already available from TimedSessionController — only if already on coach.</Text>
              <Text size="small">Soft status: Connected / Reconnecting / Restored.</Text>
              <Text size="small">Do not invent analytics panels for v1.</Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>

      <Text>
        Prefer a size-class split (compact = stacked Field Controller; regular
        width = Control | Information) implemented inside CoachSessionView or a
        thin wrapper — not ArrangementView unless fold-split proves useful in
        field. Hub already has Recommended + 2-column grid
        (CoachRemoteHubView 229–278) — densify further on regular width only.
      </Text>

      <H3>Shared components to keep identical</H3>
      <Text size="small">
        Gesture semantics, phase machine, CoachTapInputGuard, beep-arm waiting,
        PartnerLinkPassiveStatusLine copy vocabulary, haptic patterns,
        logging/evaluative copy from CoachRemoteCopy, activity wrappers’ relay
        send paths.
      </Text>
    </Stack>
  );
}

function AdaptiveSection() {
  return (
    <Stack gap={16}>
      <H2>6. Adaptive Layout & Transitions</H2>
      <Callout tone="danger" title="Non-negotiable">
        Display configuration changes must never end Partner session, mint rooms,
        reset rep/activity/TAP, Train Again, pop to pairing, drop healthy sockets,
        or interrupt the athlete drill.
      </Callout>

      <Table
        headers={["Risk source", "Code", "Concern", "Label"]}
        rows={[
          [
            "Coach onAppear beginPartner…",
            "TwoMinuteCoachRemoteView ~181–197 (and siblings)",
            "Should no-op when already active — verify under fold remount",
            "POTENTIAL RISK",
          ],
          [
            ".id(coachSessionInputResetToken)",
            "sharedSessionInput ~361",
            "Resets phase UI; must not be tied to geometry",
            "POTENTIAL RISK",
          ],
          [
            "Hub onAppear auto-reconnect / auto-open activity",
            "CoachRemoteHubView 129–200",
            "Resize remount could re-push routes if guards fail",
            "POTENTIAL RISK",
          ],
          [
            "Recycle → new room",
            "Coordinator recycle ~541–574; PartnerRelayDisplaySession ~261–286",
            "Unexpected disconnect regenerates join code on this tree",
            "CONFIRMED ISSUE",
          ],
          [
            "Singleton ownership",
            "TrainingPartnerConnectionCoordinator.shared",
            "Good — survives view rebuilds",
            "ALREADY SUPPORTED",
          ],
          [
            "Rep ownership outside CoachSessionView",
            "Parent currentRepIndex + CoachTapInputGuard",
            "Good for TAP state survival across .id remounts",
            "ALREADY SUPPORTED",
          ],
        ]}
      />

      <Text size="small">
        Safe architecture: drive layout with horizontalSizeClass (and available
        height) only inside presentation views; never put session mutations in
        onGeometryChange / size onChange. Measure Duo safe areas on device before
        hard-coding insets.
      </Text>
    </Stack>
  );
}

function PartnerSection() {
  return (
    <Stack gap={16}>
      <H2>7. Partner Mode Continuity Risks</H2>
      <Table
        headers={["System", "Baseline 7c90581", "This tree", "Label"]}
        rows={[
          [
            "TrainingPartnerConnectionCoordinator",
            "Same-room retained reconnect loops + transient link-loss UI",
            "Thinner; soft flags exist but no retained WS config / same-room loops",
            "CONFIRMED ISSUE",
          ],
          [
            "relay roomStore.attachSocket",
            "Same-token replace (replacedSocket)",
            "Rejects second socket ALREADY_CONNECTED",
            "CONFIRMED ISSUE",
          ],
          [
            "EMPTY_ROOM_GRACE_MS",
            "15 min default",
            "5 min default (roomStore.js:9)",
            "CONFIRMED ISSUE",
          ],
          [
            "NetworkReachabilityObserver",
            "Pokes same-room reconnect",
            "Only ContentView sync retry (~1211)",
            "CONFIRMED ISSUE",
          ],
          [
            "PartnerRelayDisplaySession",
            "Prefer same-room recovery",
            "Unexpected drop schedules recycle → new session",
            "CONFIRMED ISSUE",
          ],
          [
            "HotspotBaselineLog",
            "Present",
            "Missing",
            "CONFIRMED ISSUE",
          ],
        ]}
        rowTone={["danger", "danger", "danger", "danger", "danger", "danger"]}
      />
      <Text size="small">
        Duo presentation changes can proceed after baseline restore without
        touching these files — and must not touch them during UI milestones.
      </Text>
    </Stack>
  );
}

function IPadSection() {
  return (
    <Stack gap={16}>
      <H2>8. iPad Player Display Risks</H2>
      <Stack gap={10}>
        <FindingCard
          title="Drill math is GeometryReader-based"
          kind="supported"
          file="TwoMinuteCriticalScanSessionView ~1634–1700; AFP/DOP/OTP DisplaySessionViews"
        >
          Isolate Duo work to Coach* / PartnerLink chrome. Do not edit slot/ball
          helpers for coach polish.
        </FindingCard>
        <FindingCard
          title="Soft reconnect restart notifications are shared"
          kind="risk"
          file="partnerSoftReconnectRepRestart; isPartnerSoftReconnectRepRestartSuppressed"
        >
          Coach layout remounts must not double-post restarts to the display.
        </FindingCard>
        <FindingCard
          title="Legacy ContentView UIScreen paths"
          kind="risk"
          file="ContentView.swift UIScreen.main.bounds"
        >
          Out of scope for Coach Duo premium; don’t global-refactor into drill
          timing.
        </FindingCard>
      </Stack>
    </Stack>
  );
}

function UXSection() {
  return (
    <Stack gap={16}>
      <H2>9. Premium Visual & Interaction Design</H2>
      <Table
        headers={["Dimension", "Today", "Premium direction"]}
        rows={[
          [
            "Typography",
            "largeTitle phase + weak subheadline header; fixed sizes elsewhere",
            "Semantic hierarchy: phase dominant; rep/activity secondary but legible outdoors",
          ],
          [
            "Color / contrast",
            "Black canvas, white text, blue/green/red banners",
            "Keep black instrument look; raise status contrast; don’t rely on color alone",
          ],
          [
            "Spacing",
            "Centered sparse column",
            "Folded: lower-third cue; Unfolded: two-region balance",
          ],
          [
            "Buttons",
            "Full-screen gesture; unused CoachRemotePassPrimaryButton yellow pattern",
            "Keep gesture model; optional console affordance only if it doesn’t shrink hit area",
          ],
          [
            "Haptics",
            "Strong wait escalation + PASS rigid double-pulse + light direction",
            "Keep; verify outdoor feel on Duo hardware; cancel when reconnecting",
          ],
          [
            "Animation",
            "Pulse dim + optional 1.05 scale after 5s; 100ms tap flash",
            "Keep subtle; avoid decorative motion",
          ],
          [
            "Consistency",
            "Four remotes share CoachSessionView — good",
            "Single presentation layer for folded/unfolded; wrappers stay thin",
          ],
          [
            "Accessibility",
            "Some accessibilityLabel on status; limited Dynamic Type",
            "Larger status; VoiceOver labels for Connected/Reconnecting; avoid tiny captions",
          ],
        ]}
      />
      <Text>
        Premium = intentional instrument, not more chrome. Reuse CoachSessionView,
        PartnerLinkPassiveStatusLine, CoachRemoteCopy, CoachRemoteHaptics,
        CoachTapInputGuard, hub tiles.
      </Text>
    </Stack>
  );
}

function PerfSection() {
  return (
    <Stack gap={16}>
      <H2>10. Performance Findings</H2>
      <Table
        headers={["Topic", "Evidence", "Label"]}
        rows={[
          [
            ".id remounts",
            "coachSessionInputResetToken rebuilds CoachSessionView",
            "POTENTIAL RISK if overused",
          ],
          [
            "Many onChange observers",
            "CoachSessionView 313–378",
            "POTENTIAL RISK",
          ],
          [
            "Escalating haptic loop",
            "622–668 continuous while waiting",
            "POTENTIAL RISK (battery)",
          ],
          [
            "Idle off + max brightness",
            "App.swift 21–46",
            "ALREADY SUPPORTED (intentional)",
          ],
          [
            "beginPartner no-op when active",
            "Coordinator ~876+",
            "ALREADY SUPPORTED",
          ],
          [
            "Duo fold jank",
            "Not profiled on hardware",
            "REQUIRES PHYSICAL DEVICE TESTING",
          ],
        ]}
      />
    </Stack>
  );
}

function RoadmapSection() {
  return (
    <Stack gap={16}>
      <H2>11. Prioritized Implementation Roadmap</H2>
      <Text tone="secondary">
        Complexity: S localized · M multi-file careful · L high regression surface.
        No calendar estimates — scope is technical.
      </Text>

      <H3>PHASE A — Field-ready essentials (before first athlete test)</H3>
      <Table
        headers={["Item", "Pri", "Files", "Change", "Benefit", "Cx", "Partner risk"]}
        rows={[
          [
            "A0 Restore 7c90581 reconnect",
            "Critical",
            "Coordinator, WebSocket*, PartnerRelay*, relay/*, coach+display remotes",
            "Same-room reconnect + 15m grace + same-token replace",
            "Hotspot walk-away survives",
            "L",
            "High if wrong; Critical if skipped",
          ],
          [
            "A1 Glanceable rep on timed coach",
            "Critical",
            "TimedSessionDisplayIntegration; CoachSessionView header",
            "Show Rep N (and block total if meaningful)",
            "Eyes-up coaching",
            "S",
            "Low",
          ],
          [
            "A2 High-contrast connection pill",
            "Critical",
            "PartnerLinkPassiveStatusLine / banner",
            "Icon+text Connected/Reconnecting/Disconnected",
            "Outdoor clarity",
            "S",
            "Low",
          ],
          [
            "A3 Folded lower-third TAP cue",
            "High",
            "CoachSessionView only",
            "Keep full-screen hits; move label",
            "One-handed field use",
            "S",
            "Low",
          ],
          [
            "A4 Compact→regular console split",
            "High",
            "CoachSessionView (± thin wrapper)",
            "Control | Information on regular width",
            "Purpose-built unfolded",
            "M",
            "Low if presentation-only",
          ],
          [
            "A5 Fold/resize continuity smoke",
            "Critical",
            "Test only + logging",
            "Prove no room mint / rep reset",
            "Athlete safety",
            "S",
            "N/A",
          ],
        ]}
        rowTone={["danger", "danger", "danger", "warning", "warning", "danger"]}
      />

      <H3>PHASE B — Premium UX refinement</H3>
      <Table
        headers={["Item", "Pri", "Notes"]}
        rows={[
          ["B1 Unified coach design tokens", "Medium", "Type/spacing/status styles shared"],
          ["B2 Haptic tuning on Duo hardware", "Medium", "Validate outdoor; cancel on reconnect"],
          ["B3 Hub regular-width densification", "Medium", "CoachRemoteHubView grid only"],
          ["B4 Cross-activity chrome parity", "High", "All four remotes via shared view"],
        ]}
      />

      <H3>PHASE C — Advanced Duo (optional)</H3>
      <Table
        headers={["Item", "Pri", "Notes"]}
        rows={[
          ["C1 ReservedRegion.division for book pose", "Low", "Only if coaches train half-open"],
          ["C2 SDK 27.1 full-bleed + vertical bars polish", "Medium", "After Apple toolchain available"],
          ["C3 Landscape compact-height special case", "Medium", "Outer landscape 466pt-class height"],
        ]}
      />

      <H3>PHASE D — Performance / polish</H3>
      <Table
        headers={["Item", "Pri", "Notes"]}
        rows={[
          ["D1 Audit reset-token bumpers", "Medium", "Avoid geometry-tied remounts"],
          ["D2 Profile fold transition", "Low", "Evidence-based only"],
        ]}
      />
    </Stack>
  );
}

function FieldSection() {
  return (
    <Stack gap={16}>
      <H2>12. Initial Athlete Field-Test Checklist</H2>
      <Callout tone="info" title="Prerequisite">
        Run against a build that contains <Code>7c90581</Code> reconnect behavior.
      </Callout>
      <Table
        headers={["#", "Test", "Expected", "Failure", "Logs", "Sim", "Duo+field"]}
        rows={[
          ["1", "Launch on Duo", "Coach Remote reachable", "Crash/blank", "Launch", "Partial", "Yes"],
          ["2", "Pair with iPad", "Same room; hub unlocks", "New code loops", "Relay join", "Partial", "Yes"],
          ["3", "Start Two-Minute", "Drill live; coach armed", "Desync", "sessionStarted", "Yes", "Yes"],
          ["4", "Several reps", "Rep advances correctly", "Reset/skip", "rep index", "Yes", "Yes"],
          ["5", "TAP responsiveness", "Immediate haptic+visual", "Missed taps", "INPUT / HapticDebug", "Limited", "Yes"],
          ["6", "Haptics", "Wait escalate; PASS confirm", "Silent/spam", "HapticDebug", "No", "Yes"],
          ["7", "Outdoor visibility", "Rep+link readable in sun", "Status invisible", "photo notes", "No", "Yes"],
          ["8", "Fold/unfold mid-rep", "Session continuous", "Pairing/new room", "HotspotBaseline", "Duo sim", "Yes"],
          ["9", "Session continuity", "Same activity/credentials", "Train Again spuriously", "coordinator", "Partial", "Yes"],
          ["10", "Continue reps", "No index reset", "Jump to 1", "rep", "Yes", "Yes"],
          ["11", "Leave hotspot", "Reconnecting UI", "Session ended", "transport", "No", "Mandatory"],
          ["12", "Return / recover", "Same room restored", "ALREADY_CONNECTED", "baseline logs", "No", "Mandatory"],
          ["13", "Continue same session", "Athlete uninterrupted", "New join code", "sessionId", "No", "Yes"],
          ["14", "End normally", "Clean hub", "Zombie active", "endPartner", "Yes", "Yes"],
          ["15", "Start another activity", "Fresh drill OK", "Stale state", "activityId", "Yes", "Yes"],
          ["16", "Train Again", "Only on explicit path", "Geometry triggers it", "Train Again", "Yes", "Yes"],
          ["17", "Repeat on AFP/DOP/OTP", "Parity", "One activity regresses", "per-activity", "Yes", "Yes"],
        ]}
      />
    </Stack>
  );
}

function AnswersSection() {
  return (
    <Stack gap={16}>
      <H2>13. Direct Answers</H2>

      <Card>
        <CardHeader>1. How close to fully optimized for Duo?</CardHeader>
        <CardBody>
          <Text>
            Roughly one-third of the way to a premium Duo instrument: interaction
            model is strong; adaptive presentation, outdoor chrome, unfolded
            console, and reconnect baseline alignment are not.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>2. What must change before first athlete field test?</CardHeader>
        <CardBody>
          <Text>
            Restore <Code>7c90581</Code> Partner reconnect; show glanceable rep;
            high-contrast connection states; verify fold/unfold does not mint rooms
            or reset reps; smoke all four coach remotes + hotspot walk-away on
            physical Duo + iPad.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>3. What makes folded Coach Remote feel premium?</CardHeader>
        <CardBody>
          <Text>
            Eyes-up instrument: huge reliable TAP (keep), lower-third cue, always-visible
            Rep + Connected/Reconnecting pill, decisive haptics, zero accidental
            navigation, sunlight-legible hierarchy.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>4. What makes unfolded feel purpose-built?</CardHeader>
        <CardBody>
          <Text>
            Not stretched phone UI — a Control region (TAP) plus Information region
            (activity, rep, session/link) with intentional spacing. No filler widgets.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>5. Can both layouts ship without disturbing Partner networking?</CardHeader>
        <CardBody>
          <Text>
            Yes — if presentation-only in CoachSessionView / status chrome / hub,
            after reconnect baseline is restored, with no edits to coordinator,
            WebSocket transport, or relay room logic in UI PRs.
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>6. Which components to reuse?</CardHeader>
        <CardBody>
          <Text>
            CoachSessionView, CoachTapInputGuard, CoachRemoteHaptics /
            CoachRemotePassTrigger, PartnerLinkPassiveStatusLine + lifecycle banner,
            CoachRemoteCopy, CoachRemoteHubView tiles, four thin activity wrappers,
            TrainingPartnerConnectionCoordinator.shared (observe only).
          </Text>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>7. Safest smallest first implementation milestone?</CardHeader>
        <CardBody>
          <Stack gap={8}>
            <Text weight="semibold">
              Milestone 0: land <Code>7c90581</Code> reconnect only (no Duo UI).
            </Text>
            <Text size="small">
              Milestone 1: CoachSessionView presentation — enable timed rep chrome +
              stronger status pill + lower-third TAP cue (folded). Still no networking
              edits.
            </Text>
          </Stack>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>8. How quickly to a premium field-test build?</CardHeader>
        <CardBody>
          <Text>
            Scope, not calendar: Milestone 0 is a large careful merge/re-apply of
            reconnect + physical hotspot verification. Milestone 1 is a small
            presentation-only Coach Remote pass. Unfolded console split is a medium
            follow-on after folded feels right on the real Duo. The longest pole is
            reconnect parity validation on hardware, not the UI polish itself.
          </Text>
        </CardBody>
      </Card>

      <Callout tone="success" title="Awaiting approval">
        Investigation only. No code changed. Waiting for approval before Milestone
        0 / Phase A work.
      </Callout>
    </Stack>
  );
}
