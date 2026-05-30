# Changes Made on Choolwe Branch

This document captures all changes made on the `choolwe` branch that need to be replicated on the main branch.

## Summary
- Added creator credits to all 10 game cards on the hub
- Added spacebar support to the F1 Reaction Test game
- Merged `origin/Emmanuel`: Chinook SQL murder mystery wired to live Supabase

---

## Change 1: Add Creator Credits to Game Cards (index.html)

### What Changed
Added a `creator` field to each game in the GAMES array and updated the card rendering template to display the creator credit below the game title.

### Files Modified
- `index.html`

### Changes Detail

#### 1.1 Add Creator Field to Each Game in GAMES Array (around line 875-1015)

Add `creator: '[Name]',` after the `desc` line for each game:

```javascript
// British Slang Quiz
{
  id: 'british', file: 'games/british-slang-quiz.html', name: 'British Slang Quiz',
  art: SVG.britishSlang, bg: 'linear-gradient(135deg,#e040fb,#ff69b4)',
  desc: 'Decode Britain\'s slang — 10 rounds. Get them right, fastest time wins.',
  creator: 'Joanna',  // ADD THIS LINE
  mode: 'session', scoring: 'time',
  ...
}

// Cipher Codebreaker
{
  id: 'code', file: 'games/cipher-codebreaker.html', name: 'Cipher Codebreaker',
  art: SVG.cipher, bg: 'linear-gradient(135deg,#00bcd4,#3f51b5)',
  desc: 'Mastermind-style deduction — crack the secret code for the biggest score.',
  creator: 'Emmanuel',  // ADD THIS LINE
  mode: 'session', scoring: 'score',
  ...
}

// Bomb Defusal
{
  id: 'defuse', file: 'games/bomb-defusal.html', name: 'Bomb Defusal',
  art: SVG.bomb, bg: 'linear-gradient(135deg,#ff5252,#b71c1c)',
  desc: 'Snip the right wires under pressure — chain correct cuts for a combo multiplier.',
  creator: 'Enos',  // ADD THIS LINE
  mode: 'session', scoring: 'score',
  ...
}

// Dual-Ship Pilot
{
  id: 'drift', file: 'games/dual-ship-pilot.html', name: 'Dual-Ship Pilot',
  art: SVG.dualShip, bg: 'linear-gradient(135deg,#5b8cff,#ff9966)',
  desc: 'Pilot two ships simultaneously on mirrored lanes — split-attention dodging.',
  creator: 'Elizaberth',  // ADD THIS LINE
  mode: 'dom', scoring: 'score',
  ...
}

// F1 Reaction Test
{
  id: 'reaction', file: 'games/f1-reaction-test.html', name: 'F1 Reaction Test',
  art: SVG.reaction, bg: 'linear-gradient(135deg,#ffd54f,#ff5722)',
  desc: 'F1 lights-out start — five lights, then GO. How few milliseconds can you hit?',
  creator: 'Chibesa',  // ADD THIS LINE
  mode: 'session', scoring: 'time',
  ...
}

// Grid Pattern Memory
{
  id: 'pattern', file: 'games/grid-pattern-memory.html', name: 'Grid Pattern Memory',
  art: SVG.gridPattern, bg: 'linear-gradient(135deg,#00e5ff,#a3ff57)',
  desc: 'Cells light up across a grid — memorise the pattern and tap them back.',
  creator: 'Boyd',  // ADD THIS LINE
  mode: 'session', scoring: 'score',
  ...
}

// Probability Intuition
{
  id: 'probability', file: 'games/probability-intuition.html', name: 'Probability Intuition',
  art: SVG.probability, bg: 'linear-gradient(135deg,#ffb43c,#bd8526)',
  desc: 'Gut-check the odds — accuracy first, then your average answer speed.',
  creator: 'Choolwe',  // ADD THIS LINE
  mode: 'session', scoring: 'time',
  ...
}

// Stroop Color Conflict
{
  id: 'stroop', file: 'games/stroop-color-conflict.html', name: 'Stroop Color Conflict',
  art: SVG.stroop, bg: 'linear-gradient(135deg,#ab47bc,#7e57c2)',
  desc: 'Classic Stroop — pick the ink colour, ignore the word. Accuracy then speed.',
  creator: 'Boldwin',  // ADD THIS LINE
  mode: 'session', scoring: 'time',
  ...
}

// Symbol Sequence Recall
{
  id: 'symbol', file: 'games/symbol-sequence-recall.html', name: 'Symbol Sequence Recall',
  art: SVG.symbolSeq, bg: 'linear-gradient(135deg,#c8f564,#7a9c3a)',
  desc: 'Watch the symbols flash in order, then reproduce the sequence from memory.',
  creator: 'Sarudzai',  // ADD THIS LINE
  mode: 'session', scoring: 'score',
  ...
}

// Working Memory Span
{
  id: 'wordspan', file: 'games/working-memory-span.html', name: 'Working Memory Span',
  art: SVG.memorySpan, bg: 'linear-gradient(135deg,#7ee8a2,#5bc4f5)',
  desc: 'Hold the list in your head — how many words can you recall back in order?',
  creator: 'Ronald',  // ADD THIS LINE
  mode: 'session', scoring: 'score',
  ...
}
```

#### 1.2 Add CSS Styling for .game-creator (around line 270)

Insert after `.game-name` CSS block:

```css
.game-creator {
  font-size: 11px;
  color: var(--muted);
  letter-spacing: 0.2px;
  font-weight: 500;
}
```

#### 1.3 Update Game Card Template (around line 1297)

In the `renderGames()` function, update the card template to include the creator element:

```javascript
return `
  <div class="game-card" data-id="${g.id}">
    <div class="game-thumb" style="background:${g.bg}">
      <div class="art">${g.art}</div>
    </div>
    <div class="game-body">
      <div class="game-name">${escapeHtml(g.name)}</div>
      <div class="game-creator">by ${escapeHtml(g.creator)}</div>  <!-- ADD THIS LINE -->
      <div class="game-desc">${escapeHtml(g.desc)}</div>
      ${bestHtml}
      <div class="auto-indicator">Auto-capture enabled</div>
      <button class="play-btn" data-play="${g.id}">▶ Play</button>
    </div>
  </div>
`;
```

---

## Change 2: Add Spacebar Support to F1 Reaction Test (games/f1-reaction-test.html)

### What Changed
Added keyboard event listener to allow pressing the spacebar as an alternative to clicking the button for starting and reacting.

### Files Modified
- `games/f1-reaction-test.html`

### Changes Detail

#### 2.1 Add Spacebar Event Listener (around line 753)

At the end of the script, before the closing `</script>` tag, add this code in the INIT section:

```javascript
// ── INIT ──
renderHistory();
document.getElementById('scale-bar').style.display='block';

// Spacebar support for reaction trigger
document.addEventListener('keydown', (e) => {
  if(e.code === 'Space' || e.key === ' ') {
    e.preventDefault();
    handleBtn();
  }
});
```

This allows players to:
- Press spacebar to start the engine (instead of clicking "START ENGINE")
- Press spacebar to register their reaction when the GO signal appears
- The `preventDefault()` prevents page scrolling when spacebar is pressed

---

## Implementation Checklist

- [ ] Open `index.html` and add `creator` field to all 10 games in the GAMES array
- [ ] Add `.game-creator` CSS styling after `.game-name` in index.html
- [ ] Update the game card template in `renderGames()` function to display creator
- [ ] Open `games/f1-reaction-test.html` and add spacebar event listener at the end of the script
- [ ] Test both changes in a browser (open index.html and verify creators display, play F1 test with spacebar)
- [ ] Commit changes with message: "Add creator credits and F1 spacebar support"

---

## Git Commits Made on Choolwe Branch

1. `53eb0b9` - Add creator credits to game cards on the hub
2. `dcbf702` - Add spacebar support to F1 Reaction Test

---

## Change 3: Merge `origin/Emmanuel` — Chinook SQL Murder Mystery

### What Changed
Merged the `Emmanuel` branch into `main`. This brings in a new SQL-themed murder
mystery game (`Chinook/chinook_case_file (1).html`) that queries a live Supabase
Postgres database seeded with the Chinook sample dataset, plus the worklog/issues
documentation for how that setup was done.

### Files Added (from `origin/Emmanuel`)
- `Chinook/chinook_case_file (1).html` — the playable murder-mystery game with an
  in-page SQL terminal that submits queries to Supabase over PostgREST.
- `Chinook/chinook_supabase.sql` — Postgres-ready seed (564 KB) generated from the
  SQLite file: `drop` → `create table` (PK only) → batched multi-row `insert`s →
  `alter table add constraint` FKs added last so insert order never trips a constraint.
- `Chinook/Chinook_Sqlite.sqlite` — original SQLite source DB (~1 MB, 11 tables,
  ~16,420 rows: Album, Artist, Customer, Employee, Genre, Invoice, InvoiceLine,
  MediaType, Playlist, PlaylistTrack, Track).
- `Chinook/CHINOOK-SUPABASE-WORKLOG.md` — full setup record: identifiers were kept
  PascalCase + double-quoted (`"Customer"`, `"FirstName"`) to match the game's
  schema card, so every query MUST quote identifiers (unquoted `FROM Customer`
  fails — Postgres folds to lowercase). Also documents the Supabase project
  (`loivcffoynagskjhgips`, `eu-central-1`, PG 17.6), the session-pooler connection
  workaround (direct host is IPv6-only), and the remaining issues to fix.

### Merge Detail
- **Merge base:** `4d946cd` — branched off before any choolwe changes landed on main.
- **No conflicts.** Emmanuel only added files under `Chinook/`; choolwe touched
  `index.html`, `games/f1-reaction-test.html`, and `CHANGES_CHOOLWE.md`. Disjoint
  trees → clean three-way merge.
- **Note:** Chinook is **not** registered in the hub's `GAMES` array in
  [index.html](index.html), so it does not appear as a card on the Arcadius hub and
  is not part of the leaderboard. It is played by opening the HTML file directly.
  Adding it to the hub would require choosing a `scoring` mode and writing an
  `extract()` (see step 2 of "Adding a new game" in [CLAUDE.md](CLAUDE.md)).

### Commits Brought In
1. `fbe4750` - Add Chinook SQL murder mystery wired to live Supabase
2. `8b99610` - Add Chinook/Supabase work log and issues doc
3. `e33bc41` - Merge commit on `main`

