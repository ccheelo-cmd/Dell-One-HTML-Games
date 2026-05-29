# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Arcadius Hub** — a collection of 10 standalone HTML mini-games built by the Analysts of Arcadius, glued together by [index.html](index.html) — an arcade-style connector that iframes each game from the [games/](games/) folder and auto-captures their scores into a unified leaderboard. There is **no build system, no package.json, no tests, no framework** — every file is a self-contained HTML document with inline CSS/JS that runs by opening it in a browser.

**Repository structure:**
```
├── index.html                    (main hub)
├── games/                        (all 14 game files)
│   ├── british-slang-quiz.html
│   ├── bomb-defusal.html
│   └── ... (12 more games)
├── sql/                          (database scripts)
│   ├── supabase-setup.sql        (initial database schema)
│   └── delete-dual-ship-scores.sql
├── CLAUDE.md                     (this file)
└── LEADERBOARD-SETUP.md          (Supabase setup guide)
```

## Running it

Open `index.html` in a browser. For development, serve the folder over HTTP so iframe sandboxing works consistently:

```powershell
python -m http.server 8000      # then visit http://localhost:8000/index.html
```

The games also work standalone — open any `*.html` directly. Each game persists its own history to `localStorage` under a per-game key.

## Architecture: how the hub auto-captures scores

The hub treats each game as a black box and only reads its `localStorage`. The contract lives in the `GAMES` array inside [index.html](index.html), ordered alphabetically by game name:

```js
{ id, file, name, art, bg, desc, mode, scoring, extract }
```

- **`scoring`** is the game's scoring philosophy — there are two, because forcing a quiz ("out of 10") and an endless game (climbs to infinity) onto one scale was meaningless:
  - `'score'` — endless games. Rank by raw points, higher = better.
  - `'time'` — bounded games everyone can ace. Rank by **accuracy first, then time** (faster breaks ties).
- **`extract()`** returns `{ metric, tiebreak, sig, label }` or `null`.
  - `metric` — primary ranking number, higher = better. For `'score'` games it's the raw score; for `'time'` games it's accuracy 0–100.
  - `tiebreak` — secondary, lower = better. Only used by `'time'` games (elapsed/avg ms); `'score'` games pass `0`.
  - `sig` — a unique identifier for the run (timestamp or hash). Used to dedupe; the watcher only posts when `sig` changes vs. the baseline captured on iframe open.
  - `label` — human-readable native readout (`8/10 · 12.3s`, `142ms`, `3,400 pts`). This is what the per-game board shows.
- **`mode`** is `'session'` (poll localStorage; works for games that persist) or `'dom'` (poll the iframe DOM by element id; used for games with no localStorage, currently just Dual-Ship Pilot reading `#bestVal`).
- **`art`** is an inline SVG string rendered into the card thumbnail.

**Overall standing = league points.** No normalized scale anywhere. Each game ranks its own players (by `metric`, then `tiebreak` for time games — see `rankRows`/`leagueTable`), and finishing position awards F1-style points (`LEAGUE_PTS = [25,18,15,12,10,8,6,4,2,1]`, then 1 for 11th+). The "Total Score" tab sums league points across games, so the two metrics are never compared directly. `isBetterRun()` encodes the "which run is better" rule used for keeping a player's best.

The polling loop (`startWatching` / `tryCapture`) runs every `POLL_INTERVAL_MS` (1200ms) while the overlay is open, plus one final sweep on close to catch scores written at game-end.

Scores live in the in-memory `SCORES` cache that all render functions read via `loadScores()`. The cache is populated from one of two sources depending on `REMOTE` (see next section). Player name is in `localStorage['hub_player_name']`.

## Shared leaderboard (Supabase) vs. local-only

The hub has an optional remote backend so a whole team competes on **one** board. The mode is decided at load by the `REMOTE` flag, computed from the `SUPABASE_URL` / `SUPABASE_ANON_KEY` constants at the top of the `<script>`:

- **Local-only (placeholders left in place):** `SCORES` is read from `localStorage['hub_scores_v1']` (a flat array of `{player, gameId, game, kind, metric, tiebreak, label, ts}`). Games still work opened standalone/offline. Local mode also keeps one best row per player per game (mirrors the server rule via `isBetterRun()`).
- **Remote (real keys pasted in):** `SCORES` is fetched from a Supabase `scores` table via PostgREST (`GET /rest/v1/scores`). Writes go through a guarded `submit_score()` RPC (`POST /rest/v1/rpc/submit_score`), never a direct table write.

Guard rails enforced server-side by [supabase-setup.sql](supabase-setup.sql): one best row per `(player_key, game_id)` (case-insensitive). The keep-best comparison is metric-aware — higher `metric` always wins, and for `kind = 'time'` an equal metric falls back to lower `tiebreak`. Plus server-set `created_at` and RLS that allows `select` with the anon key but **no** client insert/update/delete — so the public key can't forge or wipe scores. Resetting the board is an admin `truncate` in the Supabase SQL editor.

Data-layer functions: `syncScores()` (pull into cache), `postRemoteScore()` (write via RPC, sends `kind/metric/tiebreak`), `refreshAndRender()` (sync + re-render). `autoPostScore()` branches on `REMOTE`. In remote mode the boards re-pull on tab switch and every 20s while open; the "Clear All" button is relabeled "↻ Refresh" since clients can't wipe the shared board.

Full one-time setup (create project, run SQL, paste 2 keys, host on GitHub Pages) is in [LEADERBOARD-SETUP.md](LEADERBOARD-SETUP.md). Note: the `scores` table columns changed when the two scoring types were introduced — if a project ran the older schema, drop the table first (the SQL file says how).

## Leaderboard structure

The **Leaderboard** tab shows tabbed game boards — click a game name to see its top 10 finishers. Each tab is colored to match the game's visual theme.

The **Total Score** tab displays the cumulative league points across all games, with an explanation of how league points work (F1-style: 1st = 25 pts, 2nd = 18, etc.). This is the overall ranking.

## Dual-Ship Pilot: progressive difficulty

Dual-Ship Pilot (`drift`) no longer has difficulty levels. Instead, the game progressively accelerates:
- Starts at very slow (baseSpeed 2.2) by default, or medium (3.5) if "Start at Medium Speed" checkbox is selected
- Speed increases gradually each frame: `speed = baseSpeed + (baseSpeed * 0.0008) * frame`, capped at 7.5
- Spawn interval tightens as speed increases, from 70 (or 55 for medium start) down to a minimum of 30
- To reset scores when changing the difficulty system, run: `delete from public.scores where game_id = 'drift';`

## Adding a new game

**Step 1: Create the game HTML**
- Write your game as a standalone HTML file with inline CSS/JS (no external dependencies).
- Save it in the [games/](games/) folder with a descriptive **kebab-case** filename (e.g., `memory-tiles.html`).
- The game should persist its best score to `localStorage` so the hub can auto-capture it. Example:
  ```js
  localStorage.setItem('my_game_v1', JSON.stringify({ score: 150, date: Date.now() }));
  ```

**Step 2: Register the game in [index.html](index.html)**
Open [index.html](index.html) and find the `GAMES` array (around line 858). Add an entry following this template:
```js
{
  id: 'my-game',                      // unique lowercase id for leaderboard
  file: 'games/memory-tiles.html',    // path to your HTML file
  name: 'Memory Tiles',               // display name (will appear on cards & tabs)
  art: SVG.yourGameIcon,              // SVG icon (see step 4)
  bg: 'linear-gradient(135deg,#00bcd4,#3f51b5)',  // card background color
  desc: 'Match pairs of tiles. Speed wins.',       // short description
  mode: 'session',                    // 'session' = poll localStorage during play
  scoring: 'score',                   // see step 3
  extract: () => {
    const arr = JSON.parse(localStorage.getItem('my_game_v1') || '[]');
    if (!arr.length) return null;
    const e = arr[0];  // or arr[arr.length - 1] if using push instead of unshift
    return { 
      metric: e.score || 0,           // ranking number (higher = better)
      tiebreak: 0,                    // 0 for score games, ms for time games
      sig: e.date,                    // unique identifier (timestamp or hash)
      label: `${e.score} pts`         // human-readable display
    };
  }
}
```
Keep the `GAMES` array **sorted alphabetically by `name`**.

**Step 3: Choose your scoring type**
- **`'score'`** — endless games that climb to infinity. Rank by raw points (higher = better).
  - Return: `metric` = raw score, `tiebreak` = 0, `label` = e.g. "1,250 pts"
  - Examples: Bomb Defusal, Cipher Codebreaker
- **`'time'`** — bounded games everyone can ace (e.g., quizzes, accuracy challenges). Rank by accuracy first, then speed.
  - Return: `metric` = accuracy 0–100, `tiebreak` = ms (lower = better), `label` = e.g. "8/10 · 5.2s"
  - Examples: British Slang Quiz, Stroop Color Conflict

**Step 4: Add an SVG icon**
- Create a simple SVG icon (100×100 viewBox).
- Add it to the `SVG` object near the top of [index.html](index.html):
  ```js
  yourGameIcon: `<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
    <!-- your SVG content here -->
  </svg>`,
  ```
- Reference it in your GAMES entry as `art: SVG.yourGameIcon`.

**Step 5: Test & debug**
1. Open [index.html](index.html) in a browser.
2. Serve via HTTP: `python -m http.server 8000`, then visit `http://localhost:8000`
3. Play your game and verify the score is captured in the leaderboard.
4. Open browser DevTools → Application → Local Storage to verify your game's key is being written.

**Step 6: Commit & push**
```powershell
git add games/your-game.html index.html
git commit -m "Add Your Game Name"
git push
```

**Notes:**
- The hub auto-detects new games from the GAMES array—no database changes needed.
- League points are awarded automatically by finishing position, so don't worry about normalization.
- If you need to reset scores for a game later, add a SQL cleanup script to [sql/](sql/) following the pattern in `delete-dual-ship-scores.sql`.

## Intentionally excluded from the hub

These files exist in the folder but are **not** registered in `GAMES` and should not be added back without revisiting why:

- `Wildlife Shot - Henry.html` — personality quiz, no skill metric.
- `curiosity-codex.html` — fact-reaction logger, no score.
- `focus_tracker_pro.html` — self-rated Pomodoro, trivially gameable.
- `reaction_time_tester.html` — superseded by `f1-reaction-test.html` (the F1 lights-out variant). Different localStorage key (`reflex_history_v2` vs `f1_reaction_v1`).

## Conventions

- One game = one HTML file. No external assets, no shared CSS/JS files. Self-contained is the whole point.
- Filenames are lowercase kebab-case. Game display names live in the hub's `GAMES[].name`, not in filenames.
- Score keys in localStorage are per-game and arbitrary (`f1_reaction_v1`, `stroop_history_v1`, `defuse_pro_v2`, …). Don't assume a convention — read the game's source.
- Some games store history as `unshift` (newest first, index `[0]`); others use `push` (newest last, index `[arr.length - 1]`). Check before writing an `extract()`.
