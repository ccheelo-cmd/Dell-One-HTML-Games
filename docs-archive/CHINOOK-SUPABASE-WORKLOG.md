# Chinook Case File → Supabase — Work Log & Issues

This document records **everything done** to load the Chinook database into Supabase
and wire the SQL murder-mystery game (`chinook_case_file (1).html`) to query it live,
plus a prioritized list of **issues to fix later**.

_Last updated: 2026-05-29._

---

## 1. Overview / goal

Take the standalone SQL murder-mystery (`Chinook/chinook_case_file (1).html`) — which
previously told players to "query the Chinook database in your own SQL tool" — and:

1. Load the Chinook database into a Supabase Postgres project.
2. Add an in-page **SQL terminal** + **sandbox solver** so players query the live DB
   from the browser and can auto-solve the case from real query results.

---

## 2. The database

- **Source:** `Chinook/Chinook_Sqlite.sqlite` — standard Chinook sample DB.
- **11 tables**, ~16,420 rows total:

  | Table | Rows | | Table | Rows |
  |---|---|---|---|---|
  | Album | 347 | | InvoiceLine | 2240 |
  | Artist | 275 | | MediaType | 5 |
  | Customer | 59 | | Playlist | 18 |
  | Employee | 8 | | PlaylistTrack | 8715 |
  | Genre | 25 | | Track | 3503 |
  | Invoice | 412 | | | |

- **Identifier casing decision:** kept **exact PascalCase, double-quoted**
  (`"Customer"`, `"FirstName"`) to match the game's schema card. **Consequence:** every
  query MUST quote identifiers — unquoted `FROM Customer` fails (Postgres folds to lowercase).

### Seed file
- **`Chinook/chinook_supabase.sql`** (564 KB) — Postgres-ready, generated from the SQLite file.
  - Structure: `begin;` → `drop ... cascade` → `create table` (PK only) → batched multi-row
    `insert`s → 11 `alter table add constraint` foreign keys → `commit;`.
  - FKs added **last** so insert order never trips a constraint (incl. self-referential
    `Employee.ReportsTo`).
  - Apostrophes escaped (`Guns N'' Roses`), UTF-8 preserved (`Holý`, `Rilská`).
- The Python generator script was temporary and **deleted** after producing the file.

---

## 3. Supabase project & connection

- **Project URL:** `https://loivcffoynagskjhgips.supabase.co`
- **Project ref:** `loivcffoynagskjhgips`
- **Region:** `eu-central-1` · **PostgreSQL 17.6**
- **Connection method that works from this network:** the **session pooler**
  - Host `aws-1-eu-central-1.pooler.supabase.com`, port `5432`, user `postgres.loivcffoynagskjhgips`, db `postgres`.
  - The **direct** host `db.loivcffoynagskjhgips.supabase.co` is **IPv6-only** and does not
    resolve here — region was found by probing pooler hostnames.
- **Driver:** `psycopg` (v3) installed via `pip install "psycopg[binary]"` (no `psql`/Supabase CLI available).

### How the data was loaded
- A quote-aware statement splitter (respects single-quote `''` escapes, double-quoted
  identifiers, `--` comments) split the seed into 73 statements, run in one transaction.
- **Committed in ~18 s.** Verified post-load: all 11 row counts exact, 11 FK constraints
  present, UTF-8 intact, and the first lead query returns Helena Holý / Prague / $49.62.

---

## 4. The `run_sql` RPC (how the browser queries safely)

PostgREST can't run arbitrary JOIN/GROUP BY SQL from the client, so a guarded function was created:

```sql
create or replace function public.run_sql(query text)
returns json
language plpgsql
security invoker                 -- runs AS the caller (anon), so writes fail by privilege
set search_path = public
set statement_timeout to '8000'  -- 8s cap
as $$
declare
  result json;
  q text := regexp_replace(btrim(query), ';\s*$', '');
  low text;
begin
  low := lower(q);
  if low !~ '^(select|with)\s' then
    raise exception 'Only SELECT queries are allowed in the case file.';
  end if;
  if position(';' in q) > 0 then
    raise exception 'Run one SELECT statement at a time (no semicolons).';
  end if;
  execute format(
    'select coalesce(json_agg(t), ''[]''::json) from (select * from (%s) _q limit 1000) t',
    q
  ) into result;
  return result;
end;
$$;
```

**Grants applied:**
```sql
grant usage on schema public to anon;
grant select on all tables in schema public to anon;
revoke execute on function public.run_sql(text) from public;
grant execute on function public.run_sql(text) to anon;
```

**Defense layers:** must start with `select`/`with`; no semicolons (no statement chaining);
wrapped in a subquery (blocks non-SELECT and top-level data-modifying CTEs); 1000-row LIMIT;
8s timeout; runs as `anon` which has **no** write privileges.

**Verified live:** `SELECT` works; `delete from "Customer"` → `400 "Only SELECT queries are
allowed"`; data-modifying CTE → blocked by Postgres ("must be at the top level").

---

## 5. Frontend integration (`chinook_case_file (1).html`)

- **SQL Terminal** — full-width noir panel below the case folder. Read-only query box,
  result table, `Ctrl+Enter` to run, connection-status pill.
- **Sandbox solver** — lead chips `I`–`X` (load + run each exhibit's canonical query) and a
  **`Solve Whole Case ▸`** button that runs all 10 in sequence and prints the solution chain.
- **Connection constants (top of terminal script):**
  - `SB_URL = "https://loivcffoynagskjhgips.supabase.co"`
  - `SB_ANON = "eyJ…"` — the **public anon key** (safe to embed; read-only). POSTs to
    `/rest/v1/rpc/run_sql` with `apikey` + `Authorization: Bearer` headers.
- The anon key was verified end-to-end against the live REST endpoint before embedding.

### The 10 solver queries (all verified live)
Built on two CTEs: `victim` (top lifetime spender) and `last_inv` (victim's final invoice).

| # | Lead | Live answer |
|---|---|---|
| I | The Victim | Helena Holý ($49.62) |
| II | The Scene | Prague |
| III | The Night | 2013-11-13 |
| IV | The Haul | 14 line items |
| V | The Obsession | TV Shows (6 plays) |
| VI | The Calling Card | "So Cruel" (two-word taunt in the title list) |
| VII | The Plant | sold **1×** store-wide |
| VIII | Prime Suspect | Steve Johnson |
| IX | The Reach | 18 customers |
| X | **The Culprit** | **Nancy Edwards** |

---

## 6. The date discrepancy (resolved on the game side)

- The game was authored for a Chinook **shifted +12 years** (last invoice `2025-11-13`,
  first invoice `2021-07-11`). The loaded file is the **original** (`2013-11-13` / `2009-07-11`).
  Every other fact — including all false-trail flavor facts — matched the DB exactly.
- **Resolution:** aligned the **game to the data** (HTML edits only, DB untouched):
  - Exhibit III: `accept:["20251113"]→["20131113"]`, `reveal:"2025-11-13"→"2013-11-13"`.
  - Exhibit III dead-end flavor: `11 July 2021 → 11 July 2009`.
- An attempt to shift the DB dates `+12 years` was **intentionally blocked** (unrequested
  mutation of shared data) — see Issues.

---

## 7. Git / GitHub status

- **Branch:** `Emmanuel` · **Commit:** `fbe4750` — "Add Chinook SQL murder mystery wired to live Supabase".
- Pushed to `origin` = `https://github.com/ccheelo-cmd/Dell-One-HTML-Games.git`.
- **PR #1** opened (`Emmanuel` → `main`), **NOT merged**:
  https://github.com/ccheelo-cmd/Dell-One-HTML-Games/pull/1
- Files committed: `Chinook/Chinook_Sqlite.sqlite`, `Chinook/chinook_supabase.sql`,
  `Chinook/chinook_case_file (1).html`.
- Pre-push check confirmed **no DB password / service_role key** in any committed file (only the public anon key).
- `gh` CLI is not installed; PR was created via the GitHub API using git's stored credentials.

---

## 8. ISSUES TO FIX LATER

### 🔴 Critical
1. **Rotate the database password.** The DB password (`AITSummer2026!`) was shared in the
   working session. Rotate it: Dashboard → Project Settings → Database → Reset database
   password. The committed page uses the anon key, **not** the password, so rotating breaks nothing.

### 🟠 Should address
2. **Decide the date story (2013 vs 2025).** Currently the game was edited down to 2013 to
   match the DB. If the intended narrative is 2025, instead: revert the two HTML edits in §6
   **and** shift the data with
   `update "Invoice" set "InvoiceDate" = "InvoiceDate" + interval '12 years';`
   (requires explicit approval — it was blocked before as an unrequested change).
3. **RLS is disabled on all Chinook tables.** Combined with the `grant select ... to anon`,
   anyone with the public anon key can also hit tables directly via PostgREST
   (e.g. `GET /rest/v1/Track`), not just through `run_sql`. Acceptable for public sample data,
   but if you want queries to go **only** through `run_sql`, enable RLS with no anon select
   policy and switch `run_sql` to `security definer` (owned by a role that can read the tables).

### 🟡 Nice to clean up
4. **Anon key is committed in a public repo.** This is by design (public client key), but it
   means the read-only Chinook data is queryable by anyone who finds the repo. Fine for a game;
   noted for awareness.
5. **Exhibit VI isn't a pure-SQL solve.** Identifying the "two-word taunt" needs human
   judgment ("sold once store-wide" matches 11 of 14 tracks). The sandbox lists the titles and
   picks `So Cruel` by name match. Consider a more deterministic clue if full auto-solve matters.
6. **Awkward filename:** `chinook_case_file (1).html` has a space and `(1)`. Consider renaming
   to `chinook-case-file.html` (kebab-case, matches repo convention) — update any references.
7. **Repo now carries binaries:** `Chinook_Sqlite.sqlite` (~1 MB) + `chinook_supabase.sql`
   (564 KB). Fine, but heavy for a repo of inline-HTML games.
8. **Not registered in the hub.** This game is standalone (not in `index.html`'s `GAMES`
   array) — intentional, since it has no localStorage score to capture. Revisit only if you
   want it on the leaderboard.
9. **`grant select on all tables`** only covered tables existing at run time. If new tables are
   added later, re-run the grant (or use `alter default privileges`).

---

## 9. How to reproduce / reset

- **Recreate the DB:** open `chinook_supabase.sql` in Supabase → SQL Editor → Run (drops and rebuilds).
- **Reconnect a fresh project:** re-run the `run_sql` function + grants from §4, paste the new
  project's anon key into `SB_ANON` and the URL into `SB_URL` in the HTML.
- **Reset just the dates:** see issue #2.
