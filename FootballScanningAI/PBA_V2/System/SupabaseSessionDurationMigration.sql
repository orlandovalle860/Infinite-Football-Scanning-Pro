-- PBA V2 — Session duration + mode columns for timed/multi-activity sessions.
-- Run in Supabase SQL Editor after SupabaseSchema.sql.

alter table public.sessions add column if not exists started_at timestamptz;
alter table public.sessions add column if not exists ended_at timestamptz;
alter table public.sessions add column if not exists duration_seconds int;
alter table public.sessions add column if not exists mode text;

-- Backfill started_at from created_at for existing rows.
update public.sessions
set started_at = created_at
where started_at is null and created_at is not null;
