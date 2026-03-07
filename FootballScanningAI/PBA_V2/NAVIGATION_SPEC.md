# PBA Training — Navigation Spec

Single NavigationStack at app root. All destinations and buttons are defined below.

## App Root (MainAppView)
- **IF** `hasCompletedInitialTest == false` → **IntroOnboardingView**
- **ELSE** → **HomeDashboardView** (IntroView)

## Screen 1 — IntroOnboardingView
- **Start 2-Minute Test** → TwoMinuteRoleSelectionView
- **How it works** → modal sheet (dismiss returns here)
- No other navigation.

## Screen 2 — TwoMinuteRoleSelectionView
- **Display** → TwoMinuteTestSetupView
- **Coach Remote** → Coach remote connect flow
- Back → previous

## Screen 3A — TwoMinuteTestSetupView
- **Partner pass** → TwoMinuteGetReadyView(partner, config)
- **Wall pass** → TwoMinuteGetReadyView(wall, config)
- Back → TwoMinuteRoleSelectionView

## Screen 4A — TwoMinuteGetReadyView
- After countdown → TwoMinuteCriticalScanSessionView (session)
- Back → previous

## Screen 5A — TwoMinuteCriticalScanSessionView (Display)
- On test complete → fullScreenCover **TwoMinuteTestResultsView**
- No tap navigation during reps.

## Screen 6 — TwoMinuteTestResultsView (fullScreenCover)
- **Start Training** → recommended activity role selection (inside cover NavigationStack)
- **Run Test Again** → TwoMinuteRoleSelectionView
- **Continue to Home** (first-time) → CreatePlayerProfileAfterTestView, then onComplete → dismiss cover + pop to root → Home
- **Back to Home** → onDismissCover + dismiss → session pops to root → Home
- On profile complete: set `hasCompletedInitialTest = true`; user lands on HomeDashboardView.

## Screen 7 — CreatePlayerProfileAfterTestView (optional)
- **Save** / **Skip** → onComplete() → dismiss cover, pop to root → HomeDashboardView

## Screen 8 — HomeDashboardView (IntroView)
- Pinned: **Train Now** → recommended activity (introDestination)
- **Player: Name ▾** → Players sheet
- Card order: 1 Your Snapshot, 2 Today's Target, 3 Perception Training Path, 4 2-Minute Test, 5 Progress, 6 Normal Scanning Activities (supplemental). Coach Remote is only in the pinned top row (no duplicate card).
- **Perception Training Path** card tap → PBACurriculumView
- **Run Test** (2-Min card) → TwoMinuteRoleSelectionView
- **Open Coach Remote** (Coach Remote card) → CoachRemoteHubView → pick activity → that activity’s CoachRemoteView (2-Min, Dribble or Pass, Away From Pressure, One-Touch Passing)
- **View Progress** → PlayerProgressView
- **Home** (toolbar on child screens) → dismiss → back to this

## Screen 9 — PBACurriculumView
- **Train** / **Train Now** per activity → that activity’s role selection
- **Home** (toolbar) → dismiss → HomeDashboardView

## Screen 10 — Activity setup/session
- Each activity: Role → Setup → GetReady → Session → BlockSummary (or SessionSummary)
- Back at each step → previous

## Screen 11 — SessionSummaryView
- **Train Another Block** → same activity GetReady/Session
- **Back to Home** → onBackToHome?() ?? dismiss (block summaries pass popToRoot)
- **Share Report** → share sheet

## Screen 12 — PlayerProgressView
- **Train Now** → recommended activity
- **Back to Home** → dismiss

## Rules
1. **Onboarding once:** `hasCompletedInitialTest` gates IntroOnboardingView vs HomeDashboardView.
2. **Home is hub:** After results/summary, primary “home” action returns to HomeDashboardView.
3. **No dead ends:** Every session end goes to Results or Session Summary.
4. **Curriculum visible:** Home shows path card + recommended next; Curriculum shows all 3 activities.
