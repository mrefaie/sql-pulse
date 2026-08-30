-- SQL Pulse — large-schema benchmark seed.
-- Creates a database with 500+ relational tables, a 100k-row data table,
-- views, functions and triggers to exercise the app's catalog load,
-- browse list, table detail, data grid, query console and ER diagram.
--
-- Prereqs (run once, as superuser):
--   psql -h 127.0.0.1 -U postgres -d postgres -c "DROP DATABASE IF EXISTS sqlpulse_bench WITH (FORCE)"
--   psql -h 127.0.0.1 -U postgres -d postgres -c "CREATE DATABASE sqlpulse_bench"
--   psql -h 127.0.0.1 -U postgres -d sqlpulse_bench -f benchmark/seed_large_schema.sql
--
-- Size: 500 tables x 10 columns + bench_big_events (100k rows) + 5 views +
--       3 functions + 3 triggers. FK chain links each table to its parent
--       (499 relations for the ER diagram).

\set ON_ERROR_STOP on

-- --- support table the first chain node references -----------------------------
CREATE TABLE bench_refs (
  id    serial PRIMARY KEY,
  label text NOT NULL
);
INSERT INTO bench_refs (label)
SELECT 'ref-' || g FROM generate_series(1, 1000) AS g;

-- --- 500 chained tables, 10 columns each --------------------------------------
DO $$
DECLARE
  i int;
  parent text;
BEGIN
  FOR i IN 1..500 LOOP
    IF i = 1 THEN
      parent := 'bench_refs';
    ELSE
      parent := 'bench_t_' || lpad((i - 1)::text, 4, '0');
    END IF;
    EXECUTE format(
      'CREATE TABLE bench_t_%s (
         id         serial PRIMARY KEY,
         parent_id  int REFERENCES %s(id),
         name       text NOT NULL,
         code       varchar(16),
         amount     numeric(12,2),
         qty        int NOT NULL DEFAULT 0,
         active     bool NOT NULL DEFAULT true,
         created_at timestamptz NOT NULL DEFAULT now(),
         notes      text,
         extra      jsonb
       )',
      lpad(i::text, 4, '0'), parent
    );
    EXECUTE format(
      'CREATE INDEX ix_bench_t_%s_name ON bench_t_%s (name)',
      lpad(i::text, 4, '0'), lpad(i::text, 4, '0')
    );
  END LOOP;
END $$;

-- --- 100k-row data table -------------------------------------------------------
CREATE TABLE bench_big_events (
  id          bigserial PRIMARY KEY,
  event_type  text NOT NULL,
  amount      numeric(14,2) NOT NULL DEFAULT 0,
  happened_at timestamptz NOT NULL DEFAULT now(),
  station_id  int,
  agent_id    bigint,
  ok          bool,
  note        varchar(32),
  payload     jsonb
);
INSERT INTO bench_big_events (event_type, amount, happened_at, station_id, agent_id, ok, payload)
SELECT
  'e' || (g % 17),
  (g * 13.37)::numeric(14,2),
  now() - make_interval(secs => g),
  g % 41,
  g * 7,
  g % 2 = 0,
  jsonb_build_object('seq', g, 'tag', 'g' || (g % 5))
FROM generate_series(1, 100000) AS g;
CREATE INDEX ix_big_events_at   ON bench_big_events (happened_at);
CREATE INDEX ix_big_events_type ON bench_big_events (event_type);

-- --- views ---------------------------------------------------------------------
CREATE VIEW bench_v_events_type AS
  SELECT event_type, count(*) AS n, sum(amount) AS total
  FROM bench_big_events GROUP BY event_type;
CREATE VIEW bench_v_events_ok AS
  SELECT ok, count(*) AS n FROM bench_big_events GROUP BY ok;
CREATE VIEW bench_v_events_daily AS
  SELECT date_trunc('day', happened_at) AS day, count(*) AS n
  FROM bench_big_events GROUP BY 1;
CREATE VIEW bench_v_station_summary AS
  SELECT station_id, avg(amount) AS avg_amount, max(abs(amount)) AS max_amount
  FROM bench_big_events GROUP BY station_id;
CREATE VIEW bench_v_agent_rank AS
  SELECT agent_id, sum(amount) AS total
  FROM bench_big_events GROUP BY agent_id ORDER BY 2 DESC LIMIT 100;

-- --- functions ----------------------------------------------------------------
CREATE FUNCTION bench_fn_avg_amount(from_id bigint) RETURNS numeric LANGUAGE sql AS $$
  SELECT avg(amount) FROM bench_big_events WHERE id >= $1
$$;
CREATE FUNCTION bench_fn_events_on(day date) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM bench_big_events WHERE happened_at::date = $1
$$;
CREATE FUNCTION bench_fn_dispatch() RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
    NEW.note := COALESCE(NEW.note, 'auto-' || NEW.event_type);
    RETURN NEW;
  END
$$;

-- --- triggers ------------------------------------------------------------------
CREATE TRIGGER trg_events_note_bi BEFORE INSERT ON bench_big_events
  FOR EACH ROW EXECUTE FUNCTION bench_fn_dispatch();
CREATE TRIGGER trg_events_note_bu BEFORE UPDATE ON bench_big_events
  FOR EACH ROW EXECUTE FUNCTION bench_fn_dispatch();
CREATE TRIGGER trg_events_payload_bi BEFORE INSERT ON bench_big_events
  FOR EACH ROW EXECUTE FUNCTION bench_fn_dispatch();

ANALYZE;
SELECT 'tables=' || count(*) FROM information_schema.tables
  WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
SELECT 'columns=' || count(*) FROM information_schema.columns
  WHERE table_schema = 'public';
