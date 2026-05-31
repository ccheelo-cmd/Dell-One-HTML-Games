# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

**Arcadius Hub** — a collection of standalone HTML games built by the Analysts of Arcadius, glued together by [index.html](index.html). The hub iframes each game and auto-captures scores into a shared leaderboard backed by Supabase.

**There is no build system, no package.json, no tests, no framework.** Every game is a self-contained HTML file with inline CSS/JS that runs by opening it in a browser.

The hub has **two sections**:
- **The Games** — quick, replayable arcade games. Score-based or time-based. Compete for league points.
- **Deep Dives** — long-form challenges (~15–40 min). One sitting, one verdict. Currently houses *Database Detective* (SQL murder mystery) Cases I & II, and *IQ Test*. Has its own leaderboard tab (separate from Total Score).

## Repository structure

```
├── index.html                       (the hub — GAMES[] and CASEBOOK[] live here)
├── games/                           (arcade games + a few unregistered files)
│   ├── british-slang-quiz.html
│   ├── cell-chase.html
│   └── ... (10 more registered, 4 intentionally excluded)
├── casebook/                        (non-Chinook Deep Dives)
│   └── iq-test.html
├── Chinook/                         (Database Detective + the Chinook sample DB)
│   ├── chinook-case-file.html       (Case I: CK-404)
│   ├── database-detective-case-2.html (Case II: CK-405)
│   ├── chinook_supabase.sql         (Postgres seed for Supabase)
│   ├── Chinook_Sqlite.sqlite        (original SQLite source DB)
│   └── CHINOOK-SUPABASE-WORKLOG.md  (DB setup history — in docs-archive/)
├── sql/
│   ├── supabase-setup.sql           (creates the scores table + submit_score RPC)
│   └── delete-dual-ship-scores.sql  (one-off cleanup)
├── docs-archive/                    (historical notes, kept for reference)
└── CLAUDE.md                        (this file)
```

## Running it

```powershell
python -m http.server 8000      # then visit http://localhost:8000/index.html
```

Serving over HTTP is needed so iframe sandboxing works consistently. Individual games also work standalone — open any `*.html` directly.

## Architecture: The Games (arcade)

The hub treats each game as a black box. The contract is the `GAMES` array in [index.html](index.html), sorted alphabetically by `name`:

```js
{ id, file, name, art, bg, desc, creator, mode, scoring, extract }
```

- **`scoring`** — two philosophies because forcing a quiz ("out of 10") and an endless game (climbs to infinity) onto one scale is meaningless:
  - `'score'` — endless games. Rank by raw points, higher = better.
  - `'time'` — bounded games everyone can ace. Rank by **accuracy first, then time** (faster breaks ties).
- **`extract()`** returns `{ metric, tiebreak, sig, label }` or `null`.
  - `metric` — primary ranking number, higher = better. `'score'` games → raw score; `'time'` games → accuracy 0–100.
  - `tiebreak` — secondary, lower = better. Only meaningful for `'time'` games (ms); `'score'` games pass `0`.
  - `sig` — unique id for this run (timestamp/hash). The watcher only posts when `sig` changes vs. the baseline captured on iframe open.
  - `label` — human-readable readout (`8/10 · 12.3s`, `142ms`, `3,400 pts`). Shown on the per-game board.
- **`mode`** — `'session'` (poll localStorage; works for games that persist) or `'dom'` (poll iframe DOM; used by Dual-Ship Pilot reading `#bestVal`).
- **`art`** — inline SVG string for the card thumbnail.
- **`bg`** — CSS background for the thumbnail (gradient string).
- **`creator`** — credited on the card.

**Overall standing = league points.** Each game ranks its own players by `metric` (then `tiebreak` for time games), and finishing position awards F1-style points: `LEAGUE_PTS = [25,18,15,12,10,8,6,4,2,1]`, with 1 for 11th+. The "Total Score" tab sums league points across games — the two scoring kinds never get compared directly.

`isBetterRun()` encodes the keep-best rule. `rankRows`/`leagueTable` produce the per-game ordering. The polling loop `startWatching` / `tryCapture` runs every `POLL_INTERVAL_MS` (1200ms) while the overlay is open, plus one final sweep on close.

Scores live in the in-memory `SCORES` cache (read via `loadScores()`). Player name is in `localStorage['hub_player_name']`.

## Architecture: Deep Dives (long-form challenges)

Long-form challenges that don't fit the arcade model — they take a single sitting and have a single verdict. Defined in the `CASEBOOK` array in [index.html](index.html). Has its own watcher, leaderboard tab, and persistence (no Supabase yet — **local-only**).

```js
{ id, file, name, code?, desc, creator, estMin,
  scoring, resultLabel?, formatResult?, cta?, theme? }
```

Per-case scoring kind:
- **`scoring: 'time'`** — solve-time ranking (lower = better). Used by SQL casefiles. Leaderboard columns: *Rank · Player · Solve Time · False Trails · Date*.
- **`scoring: 'score'`** — best-result ranking (higher = better). Used by IQ Test. Leaderboard columns: *Rank · Player · {resultLabel} · Accuracy · Date*. The card status and per-row label use `formatResult(value)` (e.g. `r => 'IQ ' + r`).

Optional fields:
- **`code`** — case number for the stamp (e.g. `'CK-404'`). Omit to hide the stamp entirely (IQ Test does this).
- **`cta`** — button label. Defaults to `'▶ Open Case File'`; IQ Test uses `'▶ Begin Test'`.
- **`theme`** — object of CSS custom properties applied inline to the card. Variables: `--card-bg`, `--card-border`, `--card-border-hi`, `--card-shadow`, `--card-stamp`, `--card-stamp-border`, `--card-name`, `--card-text`, `--card-muted`, `--card-meta`, `--card-open`, `--card-closed`, `--card-btn`, `--card-btn-text`, `--card-btn-glow`. **Omit `theme` for the default noir/brown** (which the Database Detective cases use). The IQ Test entry shows a complete light-blue override.

### Deep Dives progress contract

Each Deep Dive writes its own progress to `localStorage['chinook_casebook_v1']` (legacy key name — it's the **shared** map for all Deep Dives, not just Chinook):

```js
localStorage['chinook_casebook_v1'][caseId] = {
  leadsLogged, totalLeads, falseTrails, startedAt, solvedAt,
  result?,      // numeric metric for scoring:'score' cases (e.g. IQ value)
  accuracy?,    // optional context for scoring:'score' (e.g. %)
  band?         // optional label for scoring:'score' (e.g. "Superior")
}
```

The hub's `startWatchingCase` / `tryCaptureCase` polls this every `POLL_INTERVAL_MS` while a case overlay is open and posts a new entry when `solvedAt` changes. `autoPostCaseSolve` keeps one best row per `(player, caseId)` in `localStorage['hub_casebook_scores_v1']`.

## Shared leaderboard (Supabase) — for arcade games only

The arcade scores can run in two modes, chosen at load by the `REMOTE` flag (computed from `SUPABASE_URL` / `SUPABASE_ANON_KEY` constants near the top of the `<script>`):

- **Local-only** (placeholder keys) — `SCORES` is read from `localStorage['hub_scores_v1']`. Games work offline.
- **Remote** (real keys) — `SCORES` is fetched from a Supabase `scores` table via PostgREST. Writes go through a guarded `submit_score()` RPC, never a direct table write.

[sql/supabase-setup.sql](sql/supabase-setup.sql) enforces server-side: one best row per `(player_key, game_id)` (case-insensitive); higher `metric` always wins, ties broken by lower `tiebreak` for `kind='time'`; server-set `created_at`; RLS allows `select` with the anon key but **no** client insert/update/delete.

Resetting the board is an admin `truncate public.scores;` in Supabase's SQL editor.

Functions: `syncScores()` (pull), `postRemoteScore()` (RPC write), `refreshAndRender()` (sync + re-render). In remote mode, boards re-pull on tab switch and every 20s while open; the "Clear All" button is relabeled "↻ Refresh".

**Deep Dives scores are local-only.** A Supabase table (`casebook_solves` or similar) is a future addition.

### One-time Supabase setup (arcade games only)

1. **https://supabase.com** → New project (free tier is fine). Save the DB password.
2. **SQL Editor** → paste & run [sql/supabase-setup.sql](sql/supabase-setup.sql). Creates the `scores` table + `submit_score()` RPC + RLS.
3. **Project Settings → API** → copy *Project URL* and *anon public* key (NOT the service_role key).
4. Paste both into the `SUPABASE_URL` / `SUPABASE_ANON_KEY` constants in [index.html](index.html). Save.
5. (Optional) Push to GitHub Pages so the team uses one URL.

The anon key is safe to embed — its only superpower is `select` and calling `submit_score()`.

## The Chinook database (Database Detective)

The SQL murder mystery casefiles (CK-404, CK-405, and any future Database Detective cases) query a **separate** live Supabase project — not the same one as the leaderboard.

- **Project URL:** `https://loivcffoynagskjhgips.supabase.co`
- **Region:** `eu-central-1` · **PostgreSQL 17.6**
- **Anon key** is embedded in the Chinook HTML files as `SB_ANON` (public-safe; read-only).
- **Read endpoint:** `POST /rest/v1/rpc/run_sql` with `{"query": "SELECT ..."}` (only `SELECT`/`WITH`, no semicolons, 1000-row cap, 8s timeout).
- **Schema:** identifiers are PascalCase and **double-quoted**: `"Customer"`, `"FirstName"`. Postgres folds unquoted identifiers to lowercase, so unquoted queries fail.

The Database Detective HTML files include a client-side `rewriteSQL()` that recognises the Chinook schema dictionary and auto-quotes bare identifiers, so players can type natural SQL (`SELECT firstname FROM customer`) and the rewriter sends the quoted form. They also have an autocomplete popup (keywords + tables + columns).

**Chinook schema** (11 tables, ~16,420 rows): Album, Artist, Customer, Employee, Genre, Invoice, InvoiceLine, MediaType, Playlist, PlaylistTrack, Track. Full column list lives in the schema dictionary inside each Database Detective HTML.

To **verify a canonical answer** when designing a new case, hit the live RPC with curl:

```bash
curl -s -X POST "https://loivcffoynagskjhgips.supabase.co/rest/v1/rpc/run_sql" \
  -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT \"FirstName\" FROM \"Customer\" LIMIT 3"}'
```

(Get `SB_ANON` from any of the Chinook HTML files.)

DB setup history (how the Chinook data was loaded into Supabase, the `run_sql` RPC definition, RLS choices) is in [docs-archive/CHINOOK-SUPABASE-WORKLOG.md](docs-archive/CHINOOK-SUPABASE-WORKLOG.md).

## Dual-Ship Pilot: progressive difficulty

Dual-Ship Pilot (`drift`) progressively accelerates instead of having difficulty levels:
- baseSpeed 2.2 by default, 3.5 if "Start at Medium Speed" is selected
- `speed = baseSpeed + (baseSpeed * 0.0008) * frame`, capped at 7.5
- Spawn interval tightens from 70 (or 55 for medium start) down to a minimum of 30
- Reset scores: `delete from public.scores where game_id = 'drift';`

## Adding a new arcade game

1. **Create the HTML** in [games/](games/) (kebab-case filename). Inline CSS/JS, no external deps.
2. **Persist a best score** to localStorage on game-over so the hub can read it:
   ```js
   localStorage.setItem('my_game_v1', JSON.stringify([{ score: 150, date: Date.now() }]));
   ```
3. **Register in `GAMES[]`** in [index.html](index.html) (alphabetical by `name`):
   ```js
   {
     id: 'my-game', file: 'games/memory-tiles.html', name: 'Memory Tiles',
     art: SVG.yourGameIcon, bg: 'linear-gradient(135deg,#00bcd4,#3f51b5)',
     desc: 'Match pairs of tiles. Speed wins.',
     creator: 'Your Name',
     mode: 'session', scoring: 'score',
     extract: () => {
       const arr = safeJson(localStorage.getItem('my_game_v1'), []);
       if (!arr.length) return null;
       const e = arr[0];
       return { metric: e.score || 0, tiebreak: 0, sig: e.date,
                label: `${(e.score||0).toLocaleString()} pts` };
     }
   }
   ```
4. **Add an SVG icon** to the `SVG` object near the top of [index.html](index.html) (100×100 viewBox), reference as `art: SVG.yourGameIcon`.
5. **Add a color** to the `gameColors` map in `setupFilter()` (for the leaderboard tab tint).
6. **Test:** serve via `python -m http.server 8000`, play, confirm the score appears.

The hub auto-detects new games — **no database changes needed** for the shared board. New `game_id`s are accepted by `submit_score()` automatically.

## Adding a new Deep Dives entry

1. **Create the HTML** somewhere appropriate: `casebook/` for standalone challenges, `Chinook/` for Database Detective cases (since they share the Chinook DB).
2. **Persist progress** to `localStorage['chinook_casebook_v1']` keyed by your `id`. Set `startedAt` when the player begins an attempt, then update `leadsLogged` / `falseTrails` as they play, and write `solvedAt` (plus `result` for score-kind cases) on completion. See `chinook-case-file.html`'s `saveCaseRec`/`startNewAttempt` for the pattern.
3. **Register in `CASEBOOK[]`** in [index.html](index.html):
   ```js
   {
     id: 'my-dive', file: 'casebook/my-dive.html', name: 'My Deep Dive',
     code: 'MD-001',                     // omit to hide the stamp
     desc: 'Short hook for the card.',
     creator: 'Your Name',
     estMin: 20,
     cta: '▶ Begin Challenge',           // omit for default "▶ Open Case File"
     scoring: 'time',                    // or 'score'
     // For scoring:'score' only:
     // resultLabel: 'IQ',
     // formatResult: r => 'IQ ' + r,
     // theme: { '--card-bg': '...', '--card-border': '...', ... }  // omit for noir default
   }
   ```
4. **Test** in a browser and verify the card appears, the watcher posts on completion, and the leaderboard headers swap correctly (score vs. time).

### Adding a Database Detective case (Case III+)

Easiest path: **copy** [Chinook/database-detective-case-2.html](Chinook/database-detective-case-2.html) and modify the `SPINE` array, `CASE_ID`, case number, in-fiction copy, and the killer reveal at the end. Reuse the SQL terminal, auto-quoter, autocomplete, and persistence code verbatim.

Every canonical answer **must be verified against the live DB** via the `run_sql` RPC before shipping. False-trail branches (the dead-end flavor) don't need verification — they're just prose.

## Intentionally excluded from the hub

In [games/](games/) but **not** in `GAMES[]`:

- `Wildlife Shot - Henry.html` — personality quiz, no skill metric.
- `curiosity-codex.html` — fact-reaction logger, no score.
- `focus_tracker_pro.html` — self-rated Pomodoro, trivially gameable.
- `reaction_time_tester.html` — superseded by `f1-reaction-test.html`. Different localStorage key (`reflex_history_v2` vs `f1_reaction_v1`).

Don't add these back without revisiting why.

## Conventions

- **One game = one HTML file.** No external assets, no shared CSS/JS. Self-contained is the whole point.
- **Filenames are kebab-case.** Display names live in `GAMES[].name` / `CASEBOOK[].name`, not in filenames.
- **localStorage keys are per-game and arbitrary** (`f1_reaction_v1`, `stroop_history_v1`, `cell_chase_v1`, …). Read the game's source — don't assume a convention.
- **History array order varies:** some games `unshift` (newest first, `[0]`), others `push` (newest last, `[arr.length - 1]`). Check before writing an `extract()`.
- **Alphabetical order in `GAMES[]`** by display name. Deep Dives in `CASEBOOK[]` are in insertion order.
- **Don't commit secrets.** The two anon keys in the source are public-safe by design. The service_role key, DB passwords, and any private credentials must never be committed.

## Working with this repo

- Commits should be small and focused. Use `gh` CLI if available for PRs; otherwise the GitHub web UI.
- For destructive operations (truncating Supabase tables, force-pushing, etc.), confirm with the user first.
- When adding to or reorganizing this file, keep it under ~300 lines so it stays readable.
