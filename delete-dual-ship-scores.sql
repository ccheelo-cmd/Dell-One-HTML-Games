-- Delete all Dual-Ship Pilot scores so everyone uses the new progressive difficulty system
delete from public.scores where game_id = 'drift';
