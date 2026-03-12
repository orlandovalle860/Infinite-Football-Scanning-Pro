-- PBA V2 — Supabase schema for training blocks and decisions.
-- Run this in the Supabase SQL Editor to create the tables.
-- Enable RLS and add policies as needed for your auth model.

-- One row per training activity. Created when activity starts (minimal insert: player_id, created_at). Activity comes from activity_id → activities table (sessions does not have activity_name).
-- pairing_code: 6-digit code (100000–999999) shown on display for coach to pair; set at session start, stored without spaces.
create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid,
  activity_id int,
  block_size int not null default 12,
  decisions_completed int not null default 0,
  decision_speed_score int,
  created_at timestamptz not null default now(),
  pairing_code text
);
create index if not exists sessions_pairing_code_idx on public.sessions(pairing_code) where pairing_code is not null;

-- One row per drill/activity block within a session. Links to session; events and decisions link to session_activity_id.
create table if not exists public.session_activities (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  activity_id text not null,
  block_number int not null default 1,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists session_activities_session_id_idx on public.session_activities(session_id);

-- One row per decision within a block; linked to session_id and optionally to session_activity_id.
create table if not exists public.decisions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  session_activity_id uuid references public.session_activities(id) on delete set null,
  rep_index int not null,
  correct boolean not null,
  decision_time_seconds double precision,
  chosen_direction text not null
);

create index if not exists decisions_session_id_idx on public.decisions(session_id);
create index if not exists sessions_player_id_created_at_idx on public.sessions(player_id, created_at desc);

-- One row per completed training activity: summary stats derived from decisions in that session.
create table if not exists public.session_summary (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  player_id uuid,
  activity_id text not null,
  decisions_total int not null,
  correct_total int not null,
  accuracy double precision,
  avg_reaction_ms double precision,
  fast_count int not null default 0,
  medium_count int not null default 0,
  slow_count int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists session_summary_session_id_idx on public.session_summary(session_id);
create index if not exists session_summary_player_activity_idx on public.session_summary(player_id, activity_id);
-- Migration: if session_summary already exists without accuracy / decision_speed_score:
-- alter table public.session_summary add column if not exists accuracy double precision;
-- alter table public.session_summary add column if not exists decision_speed_score int;

-- Optional: enable RLS and allow anon to insert (if using anon key from app).
-- alter table public.sessions enable row level security;
-- alter table public.decisions enable row level security;
-- create policy "Allow anon insert sessions" on public.sessions for insert to anon with check (true);
-- create policy "Allow anon insert decisions" on public.decisions for insert to anon with check (true);

-- Migration: if sessions already exists without pairing_code / activity_id / decision_speed_score, run:
-- alter table public.sessions add column if not exists pairing_code text;
-- alter table public.sessions add column if not exists activity_id int;
-- alter table public.sessions add column if not exists decision_speed_score int;
-- create index if not exists sessions_pairing_code_idx on public.sessions(pairing_code) where pairing_code is not null;
-- alter table public.sessions alter column decisions_completed set default 0;
-- Minimal insert (player_id, created_at): allow nullable player_id.
-- alter table public.sessions alter column player_id drop not null;
-- If events exists without session_id / session_activity_id:
-- alter table public.events add column if not exists session_id uuid references public.sessions(id) on delete set null;
-- alter table public.events add column if not exists session_activity_id uuid references public.session_activities(id) on delete set null;
-- If decisions exists without session_activity_id:
-- alter table public.decisions add column if not exists session_activity_id uuid references public.session_activities(id) on delete set null;
-- Decisions table columns used by app (reaction-time schema): id, session_id, session_activity_id, player_id (nullable), activity_id (text, e.g. 'away_from_pressure'), activity_name, stimulus_type, decision_direction, decision_type, reaction_time_ms, correct, created_at.
-- alter table public.decisions add column if not exists player_id uuid; alter table public.decisions add column if not exists activity_id text; alter table public.decisions add column if not exists activity_name text; alter table public.decisions add column if not exists stimulus_type text; alter table public.decisions add column if not exists decision_direction text; alter table public.decisions add column if not exists decision_type text; alter table public.decisions add column if not exists reaction_time_ms int; alter table public.decisions add column if not exists created_at timestamptz default now();

-- Coach pairing: if RLS is on, allow reading sessions by pairing_code (coach device lookup).
-- create policy "Allow select sessions by pairing_code" on public.sessions for select using (pairing_code is not null);

-- Analytics: product events for onboarding and training usage (app_opened, two_minute_test_completed, etc.).
-- session_id links event to a training session (iPad or coach device).
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  event_name text not null,
  user_id uuid,
  player_id uuid,
  session_id uuid references public.sessions(id) on delete set null,
  session_activity_id uuid references public.session_activities(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists events_created_at_idx on public.events(created_at desc);
create index if not exists events_event_name_idx on public.events(event_name);
-- Optional RLS: allow anon insert from app
-- alter table public.events enable row level security;
-- create policy "Allow anon insert events" on public.events for insert to anon with check (true);
