-- Run this in the Supabase SQL Editor if you see:
--   "new row violates row-level security policy for table \"sessions\"" (42501)
--   "new row violates row-level security policy for table \"session_activity_segments\"" (42501)
--
-- These policies allow the app (anon or authenticated) to insert and update the tables
-- used for session sync. Adjust for your auth model (e.g. restrict to authenticated only).
-- Re-run safe: segment policies use DROP POLICY IF EXISTS before CREATE.

-- Sessions: allow insert (so the app can create a session when a drill starts or on retry)
create policy "Allow insert sessions"
  on public.sessions for insert
  with check (true);

-- Sessions: allow update (so the app can set decision_speed_score etc. when a block completes)
create policy "Allow update sessions"
  on public.sessions for update
  using (true)
  with check (true);

-- Sessions: allow select (e.g. for fetchDecisionSpeedScores, coach pairing)
create policy "Allow select sessions"
  on public.sessions for select
  using (true);

-- Decisions: allow insert/upsert (so the app can save decision rows)
create policy "Allow insert decisions"
  on public.decisions for insert
  with check (true);

create policy "Allow update decisions"
  on public.decisions for update
  using (true)
  with check (true);

-- session_activities: allow insert and update (drill block start/end)
create policy "Allow insert session_activities"
  on public.session_activities for insert
  with check (true);

create policy "Allow update session_activities"
  on public.session_activities for update
  using (true)
  with check (true);

-- session_summary: allow insert (when a drill finishes)
create policy "Allow insert session_summary"
  on public.session_summary for insert
  with check (true);

-- session_activity_segments: allow insert, update, select (activity stint per switch in timed sessions)
alter table public.session_activity_segments enable row level security;

drop policy if exists "Allow insert session_activity_segments" on public.session_activity_segments;
create policy "Allow insert session_activity_segments"
  on public.session_activity_segments for insert
  with check (true);

drop policy if exists "Allow update session_activity_segments" on public.session_activity_segments;
create policy "Allow update session_activity_segments"
  on public.session_activity_segments for update
  using (true)
  with check (true);

drop policy if exists "Allow select session_activity_segments" on public.session_activity_segments;
create policy "Allow select session_activity_segments"
  on public.session_activity_segments for select
  using (true);
