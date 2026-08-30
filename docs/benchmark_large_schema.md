# Large-schema benchmark (500+ tables)

Measures the app's real UI latency against two Postgres catalogs: the 9-table demo
and the 502-table `sqlpulse_bench` seed (500 chained tables + a 100k-row data
table + 5 views + 3 functions + 3 triggers; see `benchmark/seed_large_schema.sql`).

Server: macOS Postgres 14 @ `192.168.1.120:5432` (LAN) / `127.0.0.1` (desktop).
Harness: `integration_test/bench_large_schema_test.dart` (integration test driving
the real app UI; wall-clock stopwatches; `-d macos` at forced 1400×1400).

## Results (2026-08-30, desktop macOS M1 Pro)

| Metric | 9 tables | 502 tables | Delta |
|---|---|---|---|
| connect → workspace ready | 921 ms | **8 227 ms** | ×8.9 |
| browse list settle | 264 ms | 264 ms | — |
| structure open (from catalog) | 0 ms | **1 ms** | — |
| grid: first-page data load | 167 ms | 165 ms | — |
| grid: Data view render | 0 ms | 531 ms | +531 ms |
| query: `SELECT count(*)` | 160 ms | 343 ms | ×2.1 |
| query: 44-row vs 1 000-row result | 396 ms | 2 107 ms | ×5.3 |
| ER diagram (9 vs 502 nodes + 499 edges) | 161 ms | 1 346 ms | ×8.4 |
| browse list: 5 × 600 px fling sequence | 5 437 ms | 950 ms | — |

Baseline run: `connectToWorkspace=921 browseSettle=264 structureOpen=0 gridDataLoad=167
gridRender=0 queryAggregate=160 queryLimit44=396 diagramPaint=161 browseFling5=5437`.
Large run: `connectToWorkspace=8227 browseSettle=264 structureOpen=1 gridDataLoad=165
gridRender=531 queryAggregate=343 queryLimit1000=2107 diagramPaint=1346 browseFling5=950`.

## Where the 8.2 s connect goes

Server-side inventory queries the driver runs at connect (`lib/db/postgres_driver.dart`),
timed with psql at 502 tables (9-table demo ≈ 30–100 ms):

| Query | Cost |
|---|---|
| `information_schema.columns` × `tables` (5 011 rows) | **3 821 ms** |
| PKs via `table_constraints` + `key_column_usage` | 10 ms |
| FKs via `key_column_usage` + `constraint_column_usage` (500 rows) | **2 100 ms** |
| `pg_stat_user_tables` counts | 50 ms |
| views + routines + triggers | ~8 ms |
| **Total server-side** | **~6.1 s** |
| Client parse + catalog build (5 023 columns, 500 tables, relations, ER layout) | ~2.1 s |

The two slow queries are the well-known `information_schema` cross-join cost; they
grow worse than linearly with table count (9 tables: <150 ms total).

## Findings

1. **Connect time is the only real P1 at 500 tables:** 8.2 s on a spinning overlay
   with a `Connecting…` dialog. The app is otherwise healthy at this scale.
2. **Structure opens instantly (1 ms)** because columns are already in the in-memory
   catalog — good design; the cost was paid at connect.
3. **Grid data load is unchanged (165 ms)** for the 100k-row table — the 60-row
   first page + PK-ordered `LIMIT` is cheap; rendering the 60×9-cell grid costs
   531 ms (vs 0 ms demo) — still acceptable.
4. **Diagram is the second-hot spot:** 1 346 ms to mount 502 `_Node` widgets (each
   ~10 column rows) + 499 relation lines in one Stack; pan/zoom hit-testing over
   500 nodes will degrade further; no virtualization or culling.
5. **1 000-row results: 2.1 s** (network + parse + 1 000 rows built into the
   results list on one frame) — acceptable, but rows are not chunked.
6. Browse list scrolling is smooth (950 ms for 5 flings at 502 cards; the 5 437 ms
   demo number is dominated by the harness's settle overhead on the smaller list,
   not a regression).
7. **Flakiness note:** the app connect at 500 tables occasionally exceeds 90 s on
   a freshly-seeded server — autovacuum activity on 500 new tables. Run
   `VACUUM ANALYZE; CHECKPOINT;` on `sqlpulse_bench` after seeding before benchmarking.

## Recommendations (if this matters at scale)

1. **Decouple the catalog load:** fetch table names + estimates + PK/FK graph at
   connect (fast paths), and lazy-load per-table columns on first structure open —
   turns the 8.2 s into ~300–500 ms. This is the single highest-value change.
2. **Replace the two slow queries** with `pg_class`/`pg_attribute`/`pg_constraint`
   catalogs (×10+ faster) or cache the `information_schema` join result.
3. **Diagram:** render only the visible window (pan/zoom ranges) or cluster
   low-degree nodes; cap relations drawn.
4. **Results list:** chunk rows (e.g. 200/frame) for >1k result sets.

## Re-run

```bash
# seed (once)
psql -h 127.0.0.1 -U postgres -d postgres -c "DROP DATABASE IF EXISTS sqlpulse_bench WITH (FORCE)"
psql -h 127.0.0.1 -U postgres -d postgres -c "CREATE DATABASE sqlpulse_bench"
psql -h 127.0.0.1 -U postgres -d sqlpulse_bench -f benchmark/seed_large_schema.sql
psql -h 127.0.0.1 -U postgres -d sqlpulse_bench -c "VACUUM ANALYZE" -c "CHECKPOINT"

# benchmark (desktop)
flutter test integration_test/bench_large_schema_test.dart -d macos \
  --dart-define=DB_HOST=127.0.0.1 --dart-define=DB_NAME=sqlpulse_bench --dart-define=BENCH_BIG=true

# baseline (9 tables)
flutter test integration_test/bench_large_schema_test.dart -d macos \
  --dart-define=DB_HOST=127.0.0.1 --dart-define=DB_NAME=sqlpulse_demo --dart-define=BENCH_BIG=false

# phone (real device, LAN host; phone must be plugged in / wireless debugging on)
flutter test integration_test/bench_large_schema_test.dart -d "<serial>" \
  --dart-define=DB_HOST=192.168.1.120 --dart-define=DB_NAME=sqlpulse_bench \
  --dart-define=BENCH_BIG=true --dart-define=VIEW_1400=false
```

Note: `bool.fromEnvironment` accepts only `'true'`/`'false'` — `BENCH_BIG=1` is `false`.
