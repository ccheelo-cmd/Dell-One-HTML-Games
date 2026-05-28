# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A folder of standalone HTML mini-games built by different team members, glued together by [hub.html](hub.html) — an arcade-style connector that iframes each game and auto-captures their scores into a unified leaderboard. There is **no build system, no package.json, no tests, no framework** — every file is a self-contained HTML document with inline CSS/JS that runs by opening it in a browser.

## Running it

Open `hub.html` in a browser. For development, serve the folder over HTTP so iframe sandboxing works consistently:

```powershell
python -m http.server 8000      # then visit http://localhost:8000/hub.html
```

The games also work standalone — open any `*.html` directly. Each game persists its own history to `localStorage` under a per-game key.

## Architecture: how the hub auto-captures scores

The hub treats each game as a black box and only reads its `localStorage`. The contract lives in the `GAMES` array inside [hub.html](hub.html):

```js
{ id, file, name, art, bg, desc, mode, extract }
```

- **`extract()`** returns `{ points, sig, label }` or `null`.
  - `points` — **must be normalized to 0–1000** so cross-game totals are comparable. The per-game formula (e.g. `accuracy × 10`, grade table, `(400 − bestMs) × 4`) lives inside `extract()`.
  - `sig` — a unique identifier for the run (timestamp or hash). Used to dedupe; the watcher only posts when `sig` changes vs. the baseline captured on iframe open.
  - `label` — human-readable native readout (`8/10`, `250ms`, `Grade A`). Shown next to the normalized score so per-game boards stay readable.
- **`mode`** is `'session'` (poll localStorage; works for games that persist) or `'dom'` (poll the iframe DOM by element id; used for games with no localStorage, currently just Dual-Ship Pilot reading `#bestVal`).
- **`art`** is an inline SVG string rendered into the card thumbnail.

The polling loop (`startWatching` / `tryCapture`) runs every `POLL_INTERVAL_MS` (1200ms) while the overlay is open, plus one final sweep on close to catch scores written at game-end.

Scores are stored in `localStorage['hub_scores_v1']` as a flat array of `{player, gameId, game, score, label, ts}`. Player name is in `localStorage['hub_player_name']`.

## Adding a new game

1. Drop the HTML file in the root with a descriptive kebab-case name (e.g. `reaction-grid-trainer.html`).
2. Add an entry to the `GAMES` array in [hub.html](hub.html). The `extract()` must read from whatever `localStorage` key the game writes to — open the game's source and grep for `localStorage.setItem` to find the key and shape.
3. Pick a normalization formula so a top score lands near 1000 and a poor score near 0. Keep the raw value visible in `label`.
4. Add an SVG to the `SVG` map at the top of the array and reference it as `art: SVG.yourGame`.
5. Update the `13 Games · …` tagline count in the header.

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
