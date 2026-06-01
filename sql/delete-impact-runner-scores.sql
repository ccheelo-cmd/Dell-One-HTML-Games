-- Clear all Impact Runner scores after the rework to 30-second survival waves
-- (timed waves, energy-as-ammo, distance + kills scoring) so the leaderboard
-- starts fresh and old, non-comparable runs are removed.
-- Run this in the Supabase SQL Editor (leaderboard project).
delete from public.scores where game_id = 'impact';
