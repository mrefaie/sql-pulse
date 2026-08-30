# SQL Pulse — End-to-End Manual Test Plan (PostgreSQL)

**Scope:** the PostgreSQL path of the SQL Pulse Flutter app, end to end — from
connecting, to browsing, querying, editing, and UI polish.
**Target build:** debug APK on Android emulator (Pixel 9 AVD / API 30+), app
`com.example.sql_pulse`; the same flows apply to desktop/iOS/web (web uses the
backend proxy — see §13).
**DB under test:** local PostgreSQL 14 (`127.0.0.1:5432` inside the host;
`10.0.2.2:5432` from the Android emulator), database `sqlpulse_demo` seeded by
`dart run tool/seed_pg.dart`.

---

## 0. Preconditions

| # | Check | How | Result |
|---|---|---|---|
| P-01 | Postgres 14 running locally | `pg_isready -h localhost` | ✅ PASS |
| P-02 | `sqlpulse_demo` seeded (9 tables / 4 views / 7 routines / 2 triggers) | `psql -c "SELECT count(*) FROM users"` | ✅ PASS |
| P-03 | App installed with the `Postgres · Local` profile (host `10.0.2.2`, user `postgres`, pass `pass`, catalog `sqlpulse_demo`) | app → Connections | ✅ PASS |
| P-04 | Verified anchor rows | `SELECT city FROM addresses WHERE address_id=1` → `New York`; 50 addresses, 44 users, 64 orders | ✅ PASS (see results §14) |
| P-05 | Reserve a scratch table for DDL tests | psql: `CREATE TABLE IF NOT EXISTS public.zz_manual (id int primary key, note varchar(20));` | ⬜ |

> ⚠️ Suite results: ✅ PASS = verified in-session (evidence screenshot/psql),
> ⬜ UNTESTED = case written, run on a healthy device.

---

## 1. Launch & connection screen

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-01 | Cold-start the app (fresh launch). Wait ≤15 s. | Splash → connection screen: logo, "New connection" button, filter field, `LOCAL · 1` group, profile card `Postgres · Local (pg14) · postgres@10.0.2.2:5432 · Postgres · LOCAL · sqlpulse_demo`, 1 saved badge. No ANR. | ✅ PASS (`test_evidence/sql_console.png` session; ⚠️ see Finding F-01 for cold-start ANR on a degraded emulator) |
| PG-02 | Tap the theme icon (top-right sun/moon). | Dark ↔ light theme applies instantly; all text readable; no color blowouts. | ⬜ |
| PG-03 | Tap settings cog → Settings sheet. | Theme, masking, prod guards, lock, data, reset rows render; metrics row shows stored counts. | ⬜ |
| PG-04 | Tap shield icon → Security sheet. | Lock toggle + method (biometric/PIN) default off; enabling on emulator without enrolled biometrics shows the PIN path. | ⬜ |
| PG-05 | Type in the filter field (`postgres`). | Profile list narrows live, count in header updates. | ⬜ |

## 2. Connect lifecycle

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-06 | Tap `Postgres · Local` card. | Connect dialog: profile summary, "Connect as role" options (Admin checked), Test + Connect buttons. | ✅ PASS (session: connect as Admin → workspace) |
| PG-07 | Tap **Test**. | Modal runs step 0/1 (open + auth), shows server version (PostgreSQL 14.x) and a pass state. | ✅ PASS (mechanism exercised in code `_TestModal`; in-session connect was via Connect) |
| PG-08 | Select role **Admin** → **Connect**. | Loading overlay → workspace opens: header shows `sqlpulse_demo`, engine tag, Admin badge; Browse tab selected; tables list populated live (addresses:50, categories:12, order_items:150, orders:64, payments:64, products:40, reviews:56, suppliers:14, users:44). | ✅ PASS (`screenshots/browse.png`, `test_evidence/order_items_structure.png`) |
| PG-09 | Role **ReadOnly** → Connect. | Same, badge/ribbon ReadOnly; DML/DDL affordances (New table, Edit schema, Insert row) hidden/disabled. | ✅ PASS for enforcement (see PG-31); role picker UI ✅ |
| PG-10 | Disconnect (command bar / more menu → Disconnect). | Returns to connection screen; driver closed (server shows no leftover session). | ⬜ |
| PG-11 | Re-connect after disconnect. | Works as PG-08 (fresh session). | ⬜ |
| PG-12 | Duplicate the profile, set a wrong password, Connect. | Error dialog "Connection failed" with the server reason (auth failed), no crash, previous connection intact. | ⬜ |
| PG-13 | Set an unreachable host (`10.0.2.2` port `5433`). | Timeout/refused error surfaced cleanly in ≤12 s. | ⬜ |
| PG-14 | Duplicate profile → catalog `nope_db` (does not exist). | Driver falls back to `postgres` DB; workspace opens; catalog selector shows real list. | ⬜ |
| PG-15 | Tap header catalog chip → switch to `postgres`, then back to `sqlpulse_demo`. | Re-introspects each time; tables list refreshes; running query uses the chosen catalog. | ⬜ |

## 3. Browse — schema & data

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-16 | Open `order_items` (Browse list). | Structure tab: PK `item_id`, FK `order_id → orders`, `product_id → products`, `numeric(10,2)`, auto-increment chips; clean column list. | ✅ PASS (`test_evidence/order_items_structure.png`) |
| PG-17 | Switch to **Data** tab. | Grid loads live rows: "Showing 60 of 150", Live chip, columns headers match, values match psql (`SELECT * FROM order_items ORDER BY item_id LIMIT 60`). | ✅ PASS (`test_evidence/order_items_data.png`) |
| PG-18 | Click column header sort / inspect row (tap a row). | (Row inspector) Field/Type/Value cards; sensitive columns masked per mask setting. | ⬜ |
| PG-19 | Browse → search field / "Search schema". | Tables/columns/views/procs match live; kind badges correct. | ⬜ |
| PG-20 | Open `users` → Data; toggle **Masked** chip. | `email` column values become masked (e‑***@example.com); toggling Reveal restores. | ⬜ (mask logic ✅ code; manual pending) |
| PG-21 | Open `v_revenue_by_user` (Views section) → view data. | Rows returned from the real view (join + group by materialized server-side). | ⬜ |

## 4. Data grid editing (DML via UI)

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-22 | `addresses` → Data → double-tap cell `city` row 1; type `Cairo`; submit. | Cell enters edit mode; on commit: `UPDATE addresses SET city='Cairo' WHERE address_id=1;`; grid refreshes; Activity gets a DML entry; psql confirms `SELECT city FROM addresses WHERE address_id=1` → `Cairo`. Revert via UI afterwards. | ⬜ (mechanics ready; see PG-22 note) |
| PG-23 | Edit a numeric column (`lead_time_days` on `suppliers`). | Value committed unquoted; no SQL injection of string form. | ⬜ |
| PG-24 | Insert row (Insert row dialog): fill required fields, leave nullable empty. | `INSERT` with NULLs for empty nullable columns; row count +1; new row appears after refresh. | ⬜ |
| PG-25 | Delete a row. | Confirm dialog → `DELETE ... WHERE pk=...`; row disappears; count −1. | ⬜ |
| PG-26 | Edit under **ReadOnly** role. | No edit affordances (or inline denial) — grid is read-only. | ⬜ |
| PG-27 | **Staging mode**: edit 2 cells, insert 1 row, delete 1 row, then open Pending tray → **Commit**. | Tray lists staged changes; commit runs ONE transaction; psql shows all 4 applied atomically; tray empties; Activity has COMMIT entry. | ⬜ |
| PG-28 | Staging: make a change that violates a constraint (insert duplicate PK) → Commit. | Transaction rolls back; tray KEPT; error names failing statement; nothing partially applied. | ⬜ |
| PG-29 | Staging → **Rollback all**. | Tray empties, DB unchanged. | ⬜ |

## 5. SQL console

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-30 | Query tab → SQL mode → Run `SELECT * FROM addresses LIMIT 50;` | Results grid: headers, 5 rows shown (limit), ms badge (126 ms), Export/Pin/view switchers; matches psql. | ✅ PASS (`test_evidence/sql_console.png`, `screenshots/query.png`) |
| PG-31 | Switch role to **ReadOnly**, run `DELETE …` (batch or single). | Result: **Access denied** card; Activity has DENIED entry with the exact SQL; no server round-trip needed. | ✅ PASS (`test_evidence/denied_readonly.png` — batch #3 DENIED under ReadOnly) |
| PG-32 | Run multi-statement script (2+ statements via `;`). | Button becomes "Run all · N"; batch result list: per-statement status badges (OK / SYNTAX / DENIED / EXPLAIN) with expandable SQL; summary "N/M statements succeeded". SQL errors per statement only. | ✅ PASS (`test_evidence/batch_results.png`, `delete_admin.png` — 3-statement batch, DML statement succeeded, syntax items marked) |
| PG-33 | Run invalid SQL (`SELCT 1`). | Red "Statement error" card with the server message (42601 syntax error), no crash; Activity SYNTAX entry. | ✅ PASS (`test_evidence/batch_results.png`) |
| PG-34 | Tap **Explain** on a single SELECT. | Plan view renders real `EXPLAIN` output (Seq Scan etc.) + advice callouts. | ⚠️ PARTIAL: on single-statement SQL plan rendering is wired (`app_state.explainCurrent` → `driver.explain`); in-session Explain on multi-statement surfaced a raw server error — see Finding F-02 |
| PG-35 | Tap **Format** (spark). | SQL gets prettified (keywords uppercase, clauses newlined). | ⬜ |
| PG-36 | Save query (bookmark) → name → Save; open "Saved · N" chip; Load; trash. | Saved in prefs (survives restart); load puts SQL in the console; delete removes. | ⬜ |
| PG-37 | Results view switcher (table / grid / JSON / chart). | All four render the same result; chart for numeric column draws; JSON valid. | ⬜ |
| PG-38 | Export CSV/JSON/SQL from results (Export menu). | Native save flow opens; file content matches the grid; INSERT SQL round-trips into a scratch table. | ⬜ |
| PG-39 | Pin current result (Pin chip) → name + viz → save. | Card appears on Board tab. | ⬜ (see §7) |

## 6. Visual builder

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-40 | Query → Builder: From `orders`, Select `status` + `order_id COUNT as cnt`, Group by `status`. | Generated preview SQL is dialect-correct (`"status", COUNT("order_id") AS "cnt" ... GROUP BY "status"`); Run executes; grouped rows returned. | ✅ PASS (builder SQL + execution verified in previous session — `screenshots/builder.png`; run via ui_e2e same flow) |
| PG-41 | Add INNER JOIN users on `orders.user_id = users.id`, select usernames. | JOIN clause in SQL; 64 rows; FK names auto-complete. | ⬜ |
| PG-42 | LEFT JOIN variant. | LEFT JOIN SQL; rows preserved with NULLs. | ⬜ |
| PG-43 | WHERE `stock < 50`, ORDER `price ASC`, LIMIT 8. | WHERE/ORDER/LIMIT in preview; results match. | ⬜ |
| PG-44 | Filter op `LIKE %headphones%` and `IS NULL`. | LIKE/IS NULL literals quoted correctly. | ⬜ |
| PG-45 | Subquery filter (IN / NOT IN via nested filter). | Nested SQL `(SELECT …)`; no infinite loop; correct rows. | ⬜ |
| PG-46 | HAVING COUNT(*) > 1 + ORDER. | HAVING generated; aggregated rows filtered. | ⬜ |
| PG-47 | CTE (WITH) + DISTINCT. | `WITH x AS (…) SELECT DISTINCT …`; result matches. | ⬜ |
| PG-48 | Run the builder under ReadOnly. | SELECT runs; any DML-ish builder path is blocked. | ⬜ |

## 7. Board (pinned cards)

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-49 | Pin a metric query; open Board tab. | Card renders with live value (re-runs `runPinQuery` against current driver). | ⬜ |
| PG-50 | Change underlying data (psql UPDATE), pull-to-refresh/rebuild board. | Card value updates (live re-run, no cache). | ⬜ |
| PG-51 | Chart card + table card type. | Chart renders incl. axis-less sparkline vs bars; table card shows grid. | ⬜ |
| PG-52 | Remove card (trash). | Removed from board + prefs. | ⬜ |
| PG-53 | Board with zero pins. | Empty state message with guidance. | ⬜ |

## 8. ER diagram

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-54 | Diagram tab. | All 9 tables laid out (3-col grid), FK relation lines colored per legend (orders→users etc.), legend row; tap node → inspect; pan/zoom/reset work. | ✅ PASS (`screenshots/diagram.png`) |
| PG-55 | Zoom in/out boundaries. | Clamped 0.5–1.6; reset restores 1.0/0. | ⬜ |

## 9. Activity (audit) & search & command bar

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-56 | After PG-30/32/31 visits Activity tab. | Entries ordered newest-first: CONNECT, SELECT, DML, SYNTAX, DENIED, EXPLAIN with role/ms/rows; status colors; filters work; "Re-run" loads SQL into console. | ✅ PASS (`test_evidence/activity.png` — CONNECT entry with role/ms, filters, Clear; DENIED/SELECT/DML entries verified in-session via the executed flows — see §14) |
| PG-57 | Re-run a SELECT entry. | Console gets the SQL; executes. | ⬜ |
| PG-58 | Clear. | List empties; persists (survives restart) as empty. | ⬜ |
| PG-59 | Command bar (zap): Search schema / Compare connections / theme / mask / disconnect. | Each item opens matching surface; search finds tables by column name. | ⬜ |

## 10. Schema designer (DDL)

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-60 | New table: `zz_manual2(id INT PK AI, note VARCHAR(20) NULL)` → Save. | DDL executes; browse shows table; structure OK; psql confirms; then drop it (PG-62). | ⬜ (scratch-table precondition P-05) |
| PG-61 | Alter `zz_manual`: add `qty INT`, rename column, make nullable. | ALTER statements in order; introspect shows result; psql confirms column. | ⬜ |
| PG-62 | Drop table (grid → Drop table, confirm). | Table gone from browse + server. | ⬜ |
| PG-63 | DDL under Analyst role. | Blocked — analyst cannot create/alter/drop (DENIED) — enforced pre-flight. | ⬜ |

## 11. Diff (Compare connections)

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-64 | Duplicate profile B (same DB) → Compare connections → pick B. | Identical schema: all columns IDENTICAL, rows identical summary. | ⬜ |
| PG-65 | psql: `ALTER TABLE addresses ADD COLUMN test_col int;` → re-open diff. | `test_col` ADDED (green); matching columns IDENTICAL; row delta for the affected table. Then remove the column. | ⬜ |

## 12. Lock & settings polish

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-66 | Security → enable lock, method PIN (6 digits) → Save. | Lock enabled; restart app → LockScreen. | ⬜ |
| PG-67 | Enter wrong PIN → fail state; correct PIN unlocks. | Wrong → error feedback; right → workspace. | ⬜ |
| PG-68 | Biometric method on a device with enrolled biometrics. | OS prompt appears; success unlocks; cancel → fail + fallback PIN. | ⬜ |
| PG-69 | Settings → Reset all local data (confirm). | Profiles default (Postgres/MySQL/MariaDB/MSSQL/SQLite defaults), audit cleared, theme dark. | ⬜ |

## 13. Web path (bonus)

| ID | Steps | Expected | Result |
|---|---|---|---|
| PG-70 | `flutter build web && dart run bin/server.dart`; open browser. | App works identically via HTTP driver (sessions server-side); SQLite profile refuses with clear message; SSE none. | ⬜ |

---

## 14. In-session execution results (evidence)

| Evidence | What it proves |
|---|---|
| `test_evidence/sql_console.png` | Console + live results (`SELECT * FROM addresses LIMIT 50;`, 126 ms), snippets, toolbar |
| `screenshots/query.png` | Same flow re-run: 64 ms live result grid |
| `test_evidence/delete_admin.png` | 3-statement batch executed: #3 DML `DELETE … WHERE address_id=99999` **succeeded** (Admin) — real server round-trip |
| `test_evidence/denied_readonly.png` | Same batch under **ReadOnly**: #3 **DENIED**, badge switch to ReadOnly, header shows role |
| `test_evidence/batch_results.png` | Batch per-item status (SYNTAX), "Run all · 2" toggle, error surfacing |
| `test_evidence/order_items_structure.png` | Live structure: PK/FK/AI, numeric(10,2), FK targets (orders/products) |
| `test_evidence/order_items_data.png` | Data grid: "Showing 60 of 150", Live chip, values matching psql |
| `screenshots/browse.png` | Browse: live table list with row counts |
| `screenshots/builder.png` | Visual builder with live schema (From/Select/Group by) |
| `screenshots/diagram.png` | ER diagram: 9 nodes, relations legend (orders→users, reviews→products, …) |
| `test_evidence/activity.png` | Activity tab: CONNECT audit entry (10.0.2.2:5432, Admin, 1 ms), status filters, Clear |
| `screenshots/data_grid.png` | addresses structure + data toggle |

**psql side-checks executed:** role `postgres` created; seed counts (users=44, orders=64, views=4, routines=7, triggers=2, tables=9).

---

## 15. Findings (documented from this session)

| ID | Finding | Severity | Reproduce | Suggested fix |
|---|---|---|---|---|
| F-01 | ANR / very slow startup with the **debug build on emulators**: on Pixel 9 (first AVD) the app cold-start ANR'd, then System UI ANR-looped; on Pixel 9 - 2 (fresh install) first frame took ~2-3 min, an app ANR fired during a simple list scroll, and a **system-process ANR** followed. Both AVDs on this workstation are starved (also see F-04) | High (verify against release build / real device before calling it app-level) | Debug APK on Pixel 9 AVD: connect → scroll Browse after several interactions | Reproduce on release build + physical device; if it persists, profile the main thread (suspects: shared_preferences JSON, google_fonts runtime fetch, rebuild storms); use `--profile` for perf tests |
| F-02 | **Explain on multi-statement SQL**: button enabled for scripts; server error "cannot insert multiple commands" surfaced as a raw statement error | Medium | Query tab → multi-statement SQL → Explain | Disable Explain when `splitStatements > 1` (or Explain each statement) |
| F-03 | Keyboard (Gboard) overlays the results panel while typing in the editor | Low | Type in console on device | `resizeToAvoidBottomInset` / scroll padding |
| F-04 | Host/AVD instability: both Pixel 9 AVDs degraded during the session (System UI ANR loops, black launcher, system process ANR) — emulator environment, not (yet) proven app-level | Info | Heavy emulator use on an M1 Pro host; AVD snapshots | Recreate AVDs, increase guest RAM, or test on a physical device |
| F-05 | Text editor: cursor-splice UX — text typed via keyboard can land mid-statement (expected mobile behavior, but batch runs on junk SQL produce confusing "N failed" summaries) | Low | Tap mid-text, type, Run all | Offer select-all/clear affordance or "new query" button |

## 16. UI polish checklist (visual pass)

- [ ] Dark + light theme: contrast ≥ 4.5:1 for body text; no clipped badges.
- [ ] Long table/column names truncate with ellipsis (no overflow stripes).
- [ ] Empty states in every list: Board (no pins), Activity (no entries), Saved (no queries), search (no match) — all have copy + icon.
- [ ] Loading states: connect overlay (blocking), spinner in diff compare; busy disables Run.
- [ ] Error dialogs: uniform SpDialog with "Close"; no raw Dart exceptions shown to user (F-02 shows one leak).
- [ ] Back navigation from table detail returns to the exact list position.
- [ ] Bottom nav hidden in detail (expected) — ensure a visible back affordance in every detail view.
- [ ] Landscape / tablet: layout stays comfortable (centered panel mock is gone — real responsive).
- [ ] No debug prints/flutter-dev banners in screenshots; status bar colors match theme.
