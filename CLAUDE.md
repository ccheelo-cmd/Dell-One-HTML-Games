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
│   ├── casebook-setup.sql           (creates casebook_solves table + submit_casebook_solve RPC)
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
  - `label` — human-readable readout (`8/10 · 12.3s`, `142ms avg`, `3,400 pts`). Shown on the per-game board.
- **`mode`** — `'session'` (poll localStorage; works for games that persist) or `'dom'` (poll iframe DOM; used by Dual-Ship Pilot reading `#bestVal`).
- **`art`** — inline SVG string for the card thumbnail.
- **`bg`** — CSS background for the thumbnail (gradient string).
- **`creator`** — credited on the card.

**Overall standing = league points.** Each game ranks its own players by `metric` (then `tiebreak` for time games), and finishing position awards F1-style points: `LEAGUE_PTS = [25,18,15,12,10,8,6,4,2,1]`, with 1 for 11th+. The "Total Score" tab sums league points across games — the two scoring kinds never get compared directly.

`isBetterRun()` encodes the keep-best rule. `rankRows`/`leagueTable` produce the per-game ordering. The polling loop `startWatching` / `tryCapture` runs every `POLL_INTERVAL_MS` (1200ms) while the overlay is open, plus one final sweep on close.

Scores live in the in-memory `SCORES` cache (read via `loadScores()`). Player name is in `localStorage['hub_player_name']`.

## Architecture: Deep Dives (long-form challenges)

Long-form challenges that don't fit the arcade model — they take a single sitting and have a single verdict. Defined in the `CASEBOOK` array in [index.html](index.html). Has its own watcher, leaderboard tab, and shared Supabase backend (`casebook_solves` table).

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

The hub's `startWatchingCase` / `tryCaptureCase` polls this every `POLL_INTERVAL_MS` while a case overlay is open and calls `autoPostCaseSolve` when `solvedAt` changes. In remote mode this posts to Supabase via `submit_casebook_solve()`; in local-only mode it writes to `localStorage['hub_casebook_scores_v1']`.

## Shared leaderboard (Supabase)

Both boards run in two modes, chosen at load by the `REMOTE` flag (computed from `SUPABASE_URL` / `SUPABASE_ANON_KEY` constants near the top of the `<script>`):

- **Local-only** (placeholder keys) — scores read from localStorage. Everything works offline.
- **Remote** (real keys) — scores fetched from Supabase via PostgREST. Writes go through guarded RPCs, never direct table writes.

### Arcade games — `scores` table

[sql/supabase-setup.sql](sql/supabase-setup.sql) enforces server-side: one best row per `(player_key, game_id)` (case-insensitive); higher `metric` always wins, ties broken by lower `tiebreak` for `kind='time'`; RLS allows `select` with the anon key but **no** client insert/update/delete.

Functions: `syncScores()` (pull), `postRemoteScore()` (RPC write), `refreshAndRender()` (sync + re-render).

Reset a game's board: `DELETE FROM public.scores WHERE game_id = 'your-id';`

### Deep Dives — `casebook_solves` table

[sql/casebook-setup.sql](sql/casebook-setup.sql) enforces: one best row per `(player_key, case_id)`; time cases keep lowest `solve_time_ms`, score cases keep highest `result`; same RLS pattern.

Functions: `syncCasebookScores()` (pull), `postRemoteCaseSolve()` (RPC write), `refreshAndRenderCasebook()` (sync + re-render). Deep Dives board re-pulls on tab switch and every 20s while open; "Clear Scores" button is relabeled "↻ Refresh" in remote mode.

### One-time Supabase setup

1. **https://supabase.com** → New project (free tier). Save the DB password.
2. **SQL Editor** → paste & run [sql/supabase-setup.sql](sql/supabase-setup.sql).
3. **SQL Editor** → paste & run [sql/casebook-setup.sql](sql/casebook-setup.sql).
4. **Project Settings → API** → copy *Project URL* and *anon public* key (NOT the service_role key).
5. Paste both into the `SUPABASE_URL` / `SUPABASE_ANON_KEY` constants in [index.html](index.html). Save.
6. (Optional) Push to GitHub Pages so the team uses one URL.

The anon key is safe to embed — its only superpowers are `select` and calling the two submit RPCs.

## Mobile support

The hub and all playable games are mobile-adapted. Two games require a keyboard and show a full-screen "use desktop" overlay on screens narrower than 768px:

- `games/dual-ship-pilot.html` — two simultaneous keyboard inputs
- `games/impact-runner.html` — WASD + arrow key shooter

Both Database Detective cases (`Chinook/chinook-case-file.html`, `Chinook/database-detective-case-2.html`) also show the overlay because they require typing SQL.

These four are tracked in `DESKTOP_ONLY_GAMES` and `DESKTOP_ONLY_CASES` sets in [index.html](index.html), which adds a "🖥 Keyboard required" badge to their hub cards.

**Key mobile CSS patterns used throughout** (preserve when editing):
- `touch-action: manipulation` on all interactive elements (removes 300ms tap delay)
- `-webkit-tap-highlight-color: transparent` (suppresses tap flash)
- `min-height: 44px` on buttons (Apple/Google minimum touch target)
- `env(safe-area-inset-*)` padding on containers (notch/home-bar clearance)
- Hub cards: 3-column grid on ≤600px with `justify-content: space-between` to pin play buttons to the bottom of each card

## The Chinook database (Database Detective)

The SQL murder mystery casefiles (CK-404, CK-405, and any future Database Detective cases) query a **separate** live Supabase project — not the same one as the leaderboard.

- **Project URL:** `https://loivcffoynagskjhgips.supabase.co`
- **Region:** `eu-central-1` · **PostgreSQL 17.6**
- **Anon key** is embedded in the Chinook HTML files as `SB_ANON` (public-safe; read-only).
- **Read endpoint:** `POST /rest/v1/rpc/run_sql` with `{"query": "SELECT ..."}` (only `SELECT`/`WITH`, no semicolons, 1000-row cap, 8s timeout).
- **Schema:** identifiers are PascalCase and **double-quoted**: `"Customer"`, `"FirstName"`. Postgres folds unquoted identifiers to lowercase, so unquoted queries fail.

The Database Detective HTML files include a client-side `rewriteSQL()` that recognises the Chinook schema dictionary and auto-quotes bare identifiers. They also have an autocomplete popup (keywords + tables + columns).

**Chinook schema** (11 tables, ~16,420 rows): Album, Artist, Customer, Employee, Genre, Invoice, InvoiceLine, MediaType, Playlist, PlaylistTrack, Track. Full column list lives in the schema dictionary inside each Database Detective HTML.

To **verify a canonical answer** when designing a new case, hit the live RPC with curl:

```bash
curl -s -X POST "https://loivcffoynagskjhgips.supabase.co/rest/v1/rpc/run_sql" \
  -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT \"FirstName\" FROM \"Customer\" LIMIT 3"}'
```

DB setup history is in [docs-archive/CHINOOK-SUPABASE-WORKLOG.md](docs-archive/CHINOOK-SUPABASE-WORKLOG.md).

## Game-specific notes

### Dual-Ship Pilot (`drift`)
Progressive difficulty — baseSpeed 2.2 (3.5 for medium start), `speed = baseSpeed + (baseSpeed * 0.0008) * frame` capped at 7.5. Spawn interval tightens from 70 down to 30.
Reset scores: `DELETE FROM public.scores WHERE game_id = 'drift';`

### F1 Reaction Test (`reaction`)
- **Anti-mash rule:** any reaction under 100ms triggers a false-start penalty (FIA threshold — sub-100ms is physically impossible without pre-empting the lights).
- **Scoring:** the leaderboard tiebreak is the **session average** across all valid laps, not the single best lap. The `extract()` reads `e.avg` (falls back to `e.best` for pre-change records).
- Reset scores: `DELETE FROM public.scores WHERE game_id = 'reaction';`

## Adding a new arcade game

1. **Create the HTML** in [games/](games/) (kebab-case filename). Inline CSS/JS, no external deps.
2. **Persist a best score** to localStorage on game-over so the hub can read it.
3. **Register in `GAMES[]`** in [index.html](index.html) (alphabetical by `name`).
4. **Add an SVG icon** to the `SVG` object (100×100 viewBox).
5. **Add a color** to the `gameColors` map in `setupFilter()`.
6. **Mobile:** add `touch-action: manipulation`, `min-height: 44px` on buttons, and responsive layout. If the game requires a keyboard, add it to `DESKTOP_ONLY_GAMES` and add the `__mobile_gate` overlay (copy from `dual-ship-pilot.html`).
7. **Test:** serve via `python -m http.server 8000`, play, confirm score appears.

No database changes needed — `submit_score()` accepts new `game_id`s automatically.

## Adding a new Deep Dives entry

1. **Create the HTML** in `casebook/` or `Chinook/`. Persist progress to `localStorage['chinook_casebook_v1'][id]`.
2. **Register in `CASEBOOK[]`** in [index.html](index.html).
3. **Mobile:** if it requires a keyboard (e.g. a SQL terminal), add it to `DESKTOP_ONLY_CASES` and add the `__mobile_gate` overlay (copy from `chinook-case-file.html`).
4. **Test** the card, watcher, and leaderboard headers.

No database changes needed — `submit_casebook_solve()` accepts new `case_id`s automatically.

### Adding a Database Detective case (Case III+)

Copy [Chinook/database-detective-case-2.html](Chinook/database-detective-case-2.html) and modify the `SPINE` array, `CASE_ID`, case number, in-fiction copy, and the killer reveal. Reuse the SQL terminal, auto-quoter, autocomplete, and persistence code verbatim. Every canonical answer **must be verified against the live DB** via `run_sql` before shipping.

## Intentionally excluded from the hub

In [games/](games/) but **not** in `GAMES[]`:

- `Wildlife Shot - Henry.html` — personality quiz, no skill metric.
- `curiosity-codex.html` — fact-reaction logger, no score.
- `focus_tracker_pro.html` — self-rated Pomodoro, trivially gameable.
- `reaction_time_tester.html` — superseded by `f1-reaction-test.html`.

Don't add these back without revisiting why.

## Conventions

- **One game = one HTML file.** No external assets, no shared CSS/JS.
- **Filenames are kebab-case.** Display names live in `GAMES[].name` / `CASEBOOK[].name`.
- **localStorage keys are per-game and arbitrary.** Read the game's source — don't assume a convention.
- **History array order varies:** some games `unshift` (newest first), others `push` (newest last). Check before writing an `extract()`.
- **Alphabetical order in `GAMES[]`** by display name. `CASEBOOK[]` is in insertion order.
- **Don't commit secrets.** The two anon keys in the source are public-safe by design.

## Working with this repo

- Commits should be small and focused. Use `gh` CLI if available for PRs; otherwise the GitHub web UI.
- For destructive operations (truncating Supabase tables, force-pushing, etc.), confirm with the user first.
- When adding to or reorganizing this file, keep it under ~300 lines so it stays readable.
