-- PBA V2 — Decisions table: one row per decision (rep) within a training block.
-- Run in Supabase SQL Editor. Sessions table is unchanged; this creates/updates decisions only.
-- If you have an existing decisions table with a different schema, drop it first:
--   drop table if exists public.decisions;

create table if not exists public.decisions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  activity_name text not null,
  stimulus_type text not null,
  decision_direction text not null,
  correct boolean not null,
  reaction_time_ms integer not null,
  created_at timestamptz not null default now()
);

create index if not exists decisions_session_id_idx on public.decisions(session_id);
create index if not exists decisions_player_id_idx on public.decisions(player_id);
