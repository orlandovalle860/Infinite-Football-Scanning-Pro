# App Privacy Questionnaire — VisionPlay

Click-through guide for **App Store Connect → App Privacy**. Aligns with the live privacy policy and current app behavior (Supabase auth/sync, first-party analytics, optional account, partner relay).

**Privacy Policy URL:** https://orlandovalle860.github.io/Infinite-Football-Scanning-Pro/privacy_policy.html

---

## Step 1: Do you or your third-party partners collect data from this app?

**Answer: Yes**

---

## Step 2: Tracking

**Do you or your third-party partners use data from this app to track users?**

**Answer: No**

- No App Tracking Transparency / IDFA
- No advertising networks
- No third-party analytics or ad SDKs (Firebase Analytics, Facebook SDK, etc.)
- First-party product events only (Supabase `events` table)

---

## Step 3: Data types to declare

For each type below: **Collected = Yes**, **Used for Tracking = No**.

Use these **purposes** in Connect (check all that apply per row):

| Purpose in Connect | Use when |
|--------------------|----------|
| App Functionality | Required for accounts, sync, training history, partner features |
| Analytics | First-party product usage events |
| Account Management | Sign-in, profiles, sign-out |

Do **not** select: Third-Party Advertising, Developer’s Advertising, Product Personalization (unless you add it later).

---

### A. Contact Info

#### Name

| Field | Answer |
|-------|--------|
| Collected | **Yes** |
| Linked to User | **Yes** |
| Used for Tracking | **No** |
| Purposes | App Functionality, Account Management |

**Sources:** Sign in with Apple (if user shares name); player profile names.

#### Email Address

| Field | Answer |
|-------|--------|
| Collected | **Yes** |
| Linked to User | **Yes** |
| Used for Tracking | **No** |
| Purposes | App Functionality, Account Management |

**Sources:** Email/password signup; Sign in with Apple (including private relay email).

#### Phone Number, Physical Address, Other User Contact Info

| Field | Answer |
|-------|--------|
| Collected | **No** |

---

### B. Health & Fitness

#### Fitness

| Field | Answer |
|-------|--------|
| Collected | **Yes** |
| Linked to User | **Yes** (when signed in and synced); **Not Linked to You** when not signed in (training data may be transmitted using an anonymous identifier) |
| Used for Tracking | **No** |
| Purposes | App Functionality |

**Examples:** Training sessions, reps completed, accuracy, reaction/decision timing, speed scores, session duration, progress metrics.

#### Health

| Field | Answer |
|-------|--------|
| Collected | **No** |

*(No medical records, clinical health data, or HealthKit integration.)*

---

### C. Identifiers

#### User ID

| Field | Answer |
|-------|--------|
| Collected | **Yes** |
| Linked to User | **Yes** (when signed in); **Not Linked to You** when not signed in (anonymous identifier) |
| Used for Tracking | **No** |
| Purposes | App Functionality, Analytics, Account Management |

**Sources:** Supabase auth user UUID when signed in; anonymous player UUID when not signed in; player UUIDs associated with account when signed in.

#### Device ID

| Field | Answer |
|-------|--------|
| Collected | **No** |

*(No IDFA; no third-party device fingerprinting SDKs.)*

---

### D. User Content

#### Gameplay Content

| Field | Answer |
|-------|--------|
| Collected | **Yes** |
| Linked to User | **Yes** (when signed in and synced); **Not Linked to You** when not signed in (training data may be transmitted using an anonymous identifier) |
| Used for Tracking | **No** |
| Purposes | App Functionality |

**Examples:** Per-rep decisions, correct/incorrect results, directional choices, session summaries, activity type, block/rep counts, difficulty settings tied to training.

#### Other User Content

| Field | Answer |
|-------|--------|
| Collected | **Yes** |
| Linked to User | **Yes** (when signed in) |
| Used for Tracking | **No** |
| Purposes | App Functionality |

**Examples:** Optional player fields — team, position; optional age on profile.

#### Photos or Videos, Audio Data, Emails or Text Messages, Customer Support

| Field | Answer |
|-------|--------|
| Collected | **No** |

*(Core training does not use camera, microphone, or photo library. Support email is outside the app.)*

---

### E. Usage Data

#### Product Interaction

| Field | Answer |
|-------|--------|
| Collected | **Yes** |
| Linked to User | **Yes** and **Not Linked to You** — events may include `user_id` when signed in; may omit user id for guest usage |
| Used for Tracking | **No** |
| Purposes | Analytics, App Functionality |

**Examples:** `app_opened`, `training_session_started`, `training_session_completed`, `account_created`, `player_created`, activity/session identifiers in events.

#### Advertising Data, Other Usage Data

| Field | Answer |
|-------|--------|
| Collected | **No** |

---

### F. Diagnostics

#### Crash Data, Performance Data, Other Diagnostic Data

| Field | Answer |
|-------|--------|
| Collected | **No** |

*(No Crashlytics, Sentry, or similar SDK integrated in the app. Apple may collect crash reports separately from users who opt in to share with developers — that is not declared here as app collection.)*

---

### G. Financial Info, Location, Sensitive Info, Contacts, Browsing History, Search History, Purchases

| Category | Answer |
|----------|--------|
| Payment Info / Credit Info / Other Financial Info | **No** |
| Precise Location / Coarse Location | **No** |
| Sensitive Info | **No** |
| Contacts | **No** |
| Browsing History | **No** |
| Search History | **No** |
| Purchase History / Other Purchases | **No** |

*(No StoreKit / IAP in current build.)*

---

### H. Other Data (optional)

If Connect prompts for **Other Data** and you want to be explicit about optional profile metadata:

| Field | Answer |
|-------|--------|
| Collected | **Yes** (optional fields only) |
| Linked to User | **Yes** (when signed in) |
| Used for Tracking | **No** |
| Purposes | App Functionality |

**Examples:** Optional player age, team, position.

*Alternatively, fold these into **Other User Content** above and skip this row.*

---

## Step 4: Linked to identity — guest vs signed-in (reviewer notes)

Use this if Connect asks for clarification or you need internal consistency:

| Scenario | Behavior |
|----------|----------|
| Guest / no account | Training data may be stored locally and may be transmitted to our servers using an anonymous identifier to support app functionality; not linked to a personal account until sign-in |
| Signed in | Account, player profiles, sessions, decisions, and summaries sync to Supabase |
| Analytics | First-party events to Supabase; may include user id when authenticated |
| Partner mode | Real-time relay for session coordination; not long-term training storage on relay |
| Sign out | Clears local account-linked caches; does not delete server account (deletion by email request per policy) |

---

## Step 5: Third-party partners

When asked whether **third-party partners** collect data from the app:

**Answer: Yes** — data is processed on your behalf by service providers (e.g. Supabase for auth/database/analytics storage; relay host for live partner sessions).

You still declare the **data types** above; storage/processing by Supabase does not change the category, only your privacy policy disclosure.

---

## Step 6: Quick “all No” checklist (do not collect)

Confirm **No** for all of the following:

- Location (precise and coarse)
- Contacts
- Health (medical)
- Financial / payment / purchases
- Browsing or search history
- Photos, videos, microphone audio
- Sensitive information
- Device ID / advertising identifiers
- Crash or performance diagnostics (in-app SDKs)
- Cross-app tracking

---

## Step 7: Match privacy policy & nutrition label

Before submitting, confirm:

- [ ] Privacy Policy URL in App Information matches live page
- [ ] Nutrition label types match `privacy_policy.html`
- [ ] **Fitness** and **Name** are included (common miss)
- [ ] Tracking = **No**
- [ ] Account creation is optional (stated in policy and accurate in app)

---

## App Review Notes (privacy-related, optional paste)

Optional account: users can train without signing in. The app may transmit training session data using an anonymous identifier before account creation to support functionality. No personal account is required to begin training.

Sign in with Apple and email/password are supported. Training and profile data may sync via Supabase when signed in.

Partner/coach mode uses network connectivity for real-time coordination between devices; relay is not used as long-term storage of training history.

No third-party advertising or cross-app tracking. First-party analytics only.

Privacy Policy: https://orlandovalle860.github.io/Infinite-Football-Scanning-Pro/privacy_policy.html
