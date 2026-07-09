-- PBA V2 — Multi-activity session segments (one row per activity stint within a session).
-- Run in Supabase SQL Editor after SupabaseSchema.sql.
--
-- If the app logs:
--   [SEGMENT ERROR] ... row-level security policy for table "session_activity_segments" (42501)
-- run the RLS block below (or SupabaseRLSPolicies.sql segment policies).

create table if not exists public.session_activity_segments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  activity_id text not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  rep_count int not null default 0
);

create index if not exists session_activity_segments_session_id_idx
  on public.session_activity_segments(session_id);

create index if not exists session_activity_segments_activity_id_idx
  on public.session_activity_segments(activity_id);

-- RLS: required when the table has RLS enabled but no insert/update policies (42501 on insert).
alter table public.session_activity_segments enable row level security;

drop policy if exists "Allow insert session_activity_segments" on public.session_activity_segments;
create policy "Allow insert session_activity_segments"
  on public.session_activity_segments
  for insert
  with check (true);

drop policy if exists "Allow update session_activity_segments" on public.session_activity_segments;
create policy "Allow update session_activity_segments"
  on public.session_activity_segments
  for update
  using (true)
  with check (true);

drop policy if exists "Allow select session_activity_segments" on public.session_activity_segments;
create policy "Allow select session_activity_segments"
  on public.session_activity_segments
  for select
  using (true);
