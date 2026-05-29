-- ════════════════════════════════════════════════════════════════════
--  Arcade Hub — shared leaderboard schema (Supabase / Postgres)
--  Run this ONCE in your Supabase project:  Dashboard → SQL Editor → New query
--  → paste this whole file → Run.
--
--  ⚠ If you ran an EARLIER version of this file, the columns changed.
--    Run this first to start clean:   drop table if exists public.scores cascade;
--
--  Two scoring types live side by side (because a quiz "out of 10" and an
--  endless game that climbs to infinity can't share one scale):
--    • kind = 'score' → endless games. Rank by metric (raw points), higher better.
--    • kind = 'time'  → bounded games. Rank by metric (accuracy 0–100) first,
--                       then tiebreak (time in ms) — faster wins ties.
--  The overall standing is computed in the hub from finishing position
--  (F1-style league points), so the two metrics never get added together.
--
--  Guard rails (unchanged): one best row per player per game, server-set
--  timestamps, read-only with the public key, all writes via submit_score().
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.scores (
  id          bigint generated always as identity primary key,
  player      text        not null,
  player_key  text        not null,           -- lower(trim(player)), case-insensitive uniqueness
  game_id     text        not null,
  game        text        not null,
  kind        text        not null default 'score',  -- 'score' | 'time'
  metric      int         not null,           -- primary rank value, higher = better
  tiebreak    int         not null default 0, -- secondary (time games: ms, lower = better)
  label       text,                           -- native readout, e.g. "8/10 · 12.3s", "142ms"
  created_at  timestamptz not null default now()
);

-- One row per (player, game) → automatically a "personal best" board.
create unique index if not exists scores_player_game_uniq
  on public.scores (player_key, game_id);

alter table public.scores enable row level security;

-- READ: anyone holding the public anon key can see the leaderboard.
drop policy if exists "scores readable by anyone" on public.scores;
create policy "scores readable by anyone"
  on public.scores for select
  to anon
  using (true);

-- WRITE: intentionally no insert/update/delete policy for anon.
-- All writes go through submit_score() (security definer) so the public key
-- can't be used to forge or delete scores.

create or replace function public.submit_score(
  p_player   text,
  p_game_id  text,
  p_game     text,
  p_kind     text,
  p_metric   int,
  p_tiebreak int,
  p_label    text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player text := nullif(btrim(p_player), '');
  v_key    text;
  v_kind   text := case when p_kind = 'time' then 'time' else 'score' end;
  v_metric int  := greatest(0, coalesce(p_metric, 0));
  v_tie    int  := greatest(0, coalesce(p_tiebreak, 0));
begin
  if v_player is null then
    raise exception 'player name required';
  end if;
  if char_length(v_player) > 20 then
    v_player := left(v_player, 20);
  end if;
  v_key := lower(v_player);

  if p_game_id is null or btrim(p_game_id) = '' then
    raise exception 'game_id required';
  end if;

  insert into public.scores (player, player_key, game_id, game, kind, metric, tiebreak, label, created_at)
  values (v_player, v_key, btrim(p_game_id), coalesce(p_game, p_game_id),
          v_kind, v_metric, v_tie, left(coalesce(p_label, ''), 60), now())
  on conflict (player_key, game_id) do update
    set kind       = excluded.kind,
        metric     = excluded.metric,
        tiebreak   = excluded.tiebreak,
        label      = excluded.label,
        player     = excluded.player,   -- refresh display casing
        game       = excluded.game,
        created_at = now()
    -- Only overwrite when the new run is genuinely better:
    --  • any game: higher metric wins
    --  • time games: equal metric (accuracy) → lower tiebreak (time) wins
    where excluded.metric > public.scores.metric
       or (excluded.kind = 'time'
           and excluded.metric = public.scores.metric
           and excluded.tiebreak < public.scores.tiebreak);
end;
$$;

-- Let the public anon role CALL the write function (but nothing else).
grant execute on function public.submit_score(text, text, text, text, int, int, text) to anon;

-- ── Handy admin queries (run manually in the SQL Editor when needed) ──
-- See the whole board:      select game, player, metric, tiebreak, label from public.scores order by game_id, metric desc;
-- Reset everyone:           truncate public.scores;
-- Remove one bad entry:     delete from public.scores where player ilike 'name' and game_id = 'reaction';
