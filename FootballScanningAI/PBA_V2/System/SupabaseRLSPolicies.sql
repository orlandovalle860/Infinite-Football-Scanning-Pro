-- Run this in the Supabase SQL Editor if you see:
--   "new row violates row-level security policy for table \"sessions\"" (42501)
--
-- These policies allow the app (anon or authenticated) to insert and update the tables
-- used for session sync. Adjust for your auth model (e.g. restrict to authenticated only).

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
