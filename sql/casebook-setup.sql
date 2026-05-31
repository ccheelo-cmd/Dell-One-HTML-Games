-- ══════════════════════════════════════════════════════════════════════════════
-- DEEP DIVES LEADERBOARD — Supabase setup
-- Run this once in your project's SQL Editor (the same project as scores).
-- Creates the casebook_solves table + submit_casebook_solve() RPC + RLS.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Table ──────────────────────────────────────────────────────────────────
create table if not exists public.casebook_solves (
  id             bigint generated always as identity primary key,
  player_key     text    not null,        -- lowercase player name for dedup
  player         text    not null,        -- display name as typed
  case_id        text    not null,        -- 'ck-404', 'ck-405', 'iq', etc.
  case_name      text    not null,
  kind           text    not null check (kind in ('time', 'score')),
  solve_time_ms  bigint,                  -- null for score-kind cases
  result         numeric,                 -- null for time-kind cases
  accuracy       numeric,                 -- score-kind only (e.g. 92.5 %)
  band           text,                    -- score-kind label (e.g. 'Superior')
  false_trails   int     not null default 0,
  leads_logged   int     not null default 0,
  total_leads    int     not null default 0,
  solved_at      bigint,                  -- epoch ms when case was solved
  created_at     timestamptz not null default now()
);

-- One best row per (player, case) — enforced by both constraint and the RPC
alter table public.casebook_solves
  drop constraint if exists casebook_solves_player_case_unique;
alter table public.casebook_solves
  add constraint casebook_solves_player_case_unique unique (player_key, case_id);

-- ── RLS ────────────────────────────────────────────────────────────────────
alter table public.casebook_solves enable row level security;

drop policy if exists "anon read casebook_solves" on public.casebook_solves;
create policy "anon read casebook_solves" on public.casebook_solves
  for select using (true);
-- No client-side insert/update/delete — all writes go through the RPC below.

-- ── RPC ────────────────────────────────────────────────────────────────────
-- Upserts one best solve per (player_key, case_id).
-- time  cases: keeps the lower  solve_time_ms.
-- score cases: keeps the higher result.

create or replace function public.submit_casebook_solve(
  p_player        text,
  p_case_id       text,
  p_case_name     text,
  p_kind          text,
  p_solve_time_ms bigint  default null,
  p_result        numeric default null,
  p_accuracy      numeric default null,
  p_band          text    default null,
  p_false_trails  int     default 0,
  p_leads_logged  int     default 0,
  p_total_leads   int     default 0,
  p_solved_at     bigint  default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_key      text := lower(trim(p_player));
  v_existing record;
begin
  -- Basic validation
  if length(trim(p_player)) = 0 then return; end if;
  if p_kind not in ('time', 'score') then return; end if;
  if p_kind = 'time'  and (p_solve_time_ms is null or p_solve_time_ms <= 0) then return; end if;
  if p_kind = 'score' and p_result is null then return; end if;

  select * into v_existing
    from public.casebook_solves
   where player_key = v_key and case_id = p_case_id;

  if not found then
    insert into public.casebook_solves
      (player_key, player, case_id, case_name, kind,
       solve_time_ms, result, accuracy, band,
       false_trails, leads_logged, total_leads, solved_at)
    values
      (v_key, trim(p_player), p_case_id, p_case_name, p_kind,
       p_solve_time_ms, p_result, p_accuracy, p_band,
       p_false_trails, p_leads_logged, p_total_leads, p_solved_at);
  else
    -- Only overwrite if strictly better
    if (p_kind = 'time'  and p_solve_time_ms < v_existing.solve_time_ms) or
       (p_kind = 'score' and p_result        > v_existing.result) then
      update public.casebook_solves set
        player        = trim(p_player),
        case_name     = p_case_name,
        solve_time_ms = p_solve_time_ms,
        result        = p_result,
        accuracy      = p_accuracy,
        band          = p_band,
        false_trails  = p_false_trails,
        leads_logged  = p_leads_logged,
        total_leads   = p_total_leads,
        solved_at     = p_solved_at,
        created_at    = now()
      where player_key = v_key and case_id = p_case_id;
    end if;
  end if;
end;
$$;

grant execute on function public.submit_casebook_solve to anon;
