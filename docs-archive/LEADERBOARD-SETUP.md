# Shared Leaderboard Setup

The Arcade Hub can run in two modes:

- **Local-only (default out of the box):** scores stay in your own browser's `localStorage`. Good for testing or playing offline.
- **Shared team board (this guide):** every teammate's scores land in one cloud database (Supabase) and everyone competes on the same leaderboard.

You only have to do this **once**. Total time: ~10 minutes. No servers to run, no build step — the hub talks to Supabase directly from the browser.

---

## 1. Create a free Supabase project

1. Go to **https://supabase.com** → sign up (free tier is plenty).
2. Click **New project**. Give it a name (e.g. `arcade-hub`), set a database password (save it somewhere), pick a region near your team.
3. Wait ~1 minute for it to provision.

## 2. Create the database table + rules

1. In your project, open **SQL Editor** (left sidebar) → **New query**.
2. Open the file [`supabase-setup.sql`](supabase-setup.sql) from this repo, copy its **entire** contents, paste into the editor.
3. Click **Run**. You should see "Success. No rows returned."

This creates the `scores` table and the guard rails:
- one best row per player per game (case-insensitive names),
- timestamps set by the server (can't be backdated),
- reads allowed with the public key, but all writes go through a validated function — so the public key **can't** be used to delete or forge scores.

> Already ran an earlier version of this file? The columns changed when two scoring types were added. Run `drop table if exists public.scores cascade;` once, then paste and run the file again.

**How games are scored:** each game ranks its own way — endless games (Dual-Ship, Bomb Defusal, Cipher…) by raw points, and timed/quiz games (British Slang, Stroop, Probability, F1 Reaction) by **accuracy first, then speed**. Your finishing position in each game earns **league points** (1st = 25, 2nd = 18, 3rd = 15…), and the "Total Score" tab adds those up for the overall standing. Nothing to configure — it's all in the hub.

## 3. Grab your two keys

1. Go to **Project Settings** (gear icon) → **API**.
2. Copy two values:
   - **Project URL** — looks like `https://abcdefgh.supabase.co`
   - **anon public** key (under *Project API keys*) — a long string starting with `eyJ...`

> The **anon public** key is safe to put in client-side HTML — that's what it's designed for. Do **not** use the `service_role` key here; that one is secret.

## 4. Paste the keys into the hub

Open [`hub.html`](hub.html), find this block near the top of the `<script>`:

```js
const SUPABASE_URL      = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_PUBLIC_ANON_KEY';
```

Replace both placeholder strings with your real Project URL and anon public key. Save.

That's it — the hub auto-detects valid keys and switches into shared mode. (If the values are still placeholders or look invalid, it quietly falls back to local-only mode.)

## 5. Host the folder at one URL (GitHub Pages)

So the whole team uses the same link instead of copying files around:

1. Commit and push your changes (including the keyed `hub.html`):
   ```powershell
   git add hub.html supabase-setup.sql LEADERBOARD-SETUP.md
   git commit -m "Add shared Supabase leaderboard"
   git push
   ```
2. On GitHub, go to the repo → **Settings** → **Pages**.
3. Under **Build and deployment** → **Source**, choose **Deploy from a branch**.
4. Branch: **`main`**, folder: **`/ (root)`** → **Save**.
5. After a minute, your hub is live at:
   ```
   https://ccheelo-cmd.github.io/Dell-One-HTML-Games/hub.html
   ```
   Share that link with the team. Everyone types their name, plays, and climbs the same board.

---

## How scores flow

```
teammate plays a game in the hub
        │  (hub watches the game's localStorage)
        ▼
hub calls submit_score() on Supabase  ──►  scores table (best-per-player-per-game)
        ▲                                            │
        └──────────  everyone's hub reads  ◄─────────┘
```

The board auto-refreshes when you open the Leaderboard / Total Score tabs and every 20s while one is open, so the competition stays live.

## Admin / housekeeping

Run these in the Supabase **SQL Editor** when needed:

- See the whole board: `select game, player, metric, tiebreak, label from public.scores order by game_id, metric desc;`
- Reset everyone (new season): `truncate public.scores;`
- Remove one bad entry: `delete from public.scores where player ilike 'somename' and game_id = 'reaction';`

## Troubleshooting

- **"Can't reach the leaderboard server" toast** — the URL/key is wrong, or the SQL hasn't been run. Re-check steps 2–4. Open the browser console (F12) for the exact HTTP error.
- **Scores save but don't appear for others** — make sure everyone is on the hosted URL (step 5) with the same keys, not their own local copy with placeholder keys.
- **A new game was added** — no DB change needed; new `game_id`s are accepted automatically.
