# Supabase session sync setup

Training blocks are saved to Supabase when the app is configured. The app uses the **Supabase Swift client** (supabase-swift) and your **Project URL** and **anon public key** to send session data.

## 1. Create tables

In the [Supabase SQL Editor](https://supabase.com/dashboard/project/_/sql), run the statements in `SupabaseSchema.sql`:

- **sessions**: one row per completed block (`player_id`, `created_at`; activity from `activity_id` → **activities** table).
- **decisions**: one row per decision in a block, linked by `session_id` (`rep_index`, `correct`, `decision_time_seconds`, `chosen_direction`).

## 2. Configure the app

Initialize the Supabase client by setting your **Project URL** and **anon (public) key**:

- **Option A**: In Xcode, open the app target → **Info** tab → **Custom iOS Target Properties**. Add:
  - `SUPABASE_URL` = `https://YOUR_PROJECT_REF.supabase.co`
  - `SUPABASE_ANON_KEY` = your project’s anon (public) key (from **Project Settings → API** in the Supabase dashboard).

- **Option B**: Add the same keys to `Info.plist` if you use a custom plist.

If either key is missing or empty, the Supabase client is not created and session sync is skipped (no errors; local progress is unchanged).

## 3. Flow

1. User completes a training block (e.g. 12 decisions) or the 2-minute baseline test.
2. App creates a `SessionRecord` and calls `ProgressStore.add(record)` (local).
3. App calls `SupabaseSessionService.shared.saveSession(record, decisions)`:
   - Uses `SupabaseClientManager.client` (initialized with Project URL and anon key).
   - Inserts one row into `sessions`.
   - Inserts one row per decision into `decisions` with that `session_id`.

Decisions are derived from the block’s rep logs/results (Away From Pressure, Dribble or Pass, One-Touch Passing, 2-Minute Test). When rep-level data isn’t available (e.g. some 2-min result screens), only the session row is inserted.

## 4. Row-Level Security (RLS)

If you see **"new row violates row-level security policy for table \"sessions\""** (Postgres 42501), RLS is enabled but no policy allows the insert. Run the statements in **`SupabaseRLSPolicies.sql`** in the [Supabase SQL Editor](https://supabase.com/dashboard/project/_/sql):

- **sessions**: insert, update, select
- **decisions**: insert, update
- **session_activities**: insert, update
- **session_summary**: insert

After adding these policies, session and decision inserts should succeed. The FK errors (23503) will stop once the session row is created successfully.

## 5. Auth: Sign in with Apple

- The app uses **Sign in with Apple** and requires the **Sign in with Apple** capability. The project includes `FootballScanningAI/FootballScanningAI.entitlements` with `com.apple.developer.applesignin` = Default.
- In the [Supabase Dashboard](https://supabase.com/dashboard) → **Authentication → Providers → Apple**, add your app's **Bundle ID** (e.g. `com.infinitefootball.scanningpro`) under **Client IDs**. No OAuth/Services ID is needed for native-only Apple sign-in.

## 6. Auth: Email and "Safari couldn't connect"

- Email sign-in uses **email + password** in the app; it does not open Safari during sign-in.
- If you see **"Safari can't open the page because it couldn't connect to the server"**, it is usually from:
  1. **Confirmation email link**: Supabase sends a confirmation email with a link. That link goes to the **Site URL** or a **Redirect URL** configured in **Authentication → URL Configuration**. Use a reachable URL (e.g. your production site or a known deep link). Avoid `localhost` or invalid URLs so the link works when opened in Safari.
  2. **Project URL**: Ensure **Project URL** (e.g. `https://YOUR_PROJECT.supabase.co`) is correct and the project is not paused (Supabase Dashboard → Project Settings).
