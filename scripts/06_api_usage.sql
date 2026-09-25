-- Migration 06: gis.api_usage — per-key monthly request counters for api-gis
-- Applied: 2026-09-25 on Neon GIS (owner go-ahead in session)
-- Context: api-gis was open to anyone (P1: "every route is open against the
--   public DENUE corpus"). To offer it outside docuget, requests carry an API
--   key — the platform's existing `apikey` table, role `gis`, limits in
--   `config.gis.monthly_limit` — and every request is counted HERE, in the GIS
--   database, not in the platform's: a map pan fires several requests, and
--   those writes don't belong on the main Neon project.
--
-- One row per (key, calendar month UTC, route): the quota check is a SUM over
-- the key's current month (≤ a handful of rows); the write is one upsert.
-- `apikey_id = 'anon'` counts keyless calls while auth runs in soft mode, so
-- the switch to enforce is taken on data ("anon went to ~0"), not on hope.
--
-- Reversible: DROP TABLE gis.api_usage; (api-gis tolerates its absence —
-- counting is best-effort and the quota reads 0 when the table is missing.)

CREATE TABLE IF NOT EXISTS gis.api_usage (
  apikey_id  text        NOT NULL,           -- apikey.id, or 'anon'
  month      date        NOT NULL,           -- first day of the month, UTC
  route      text        NOT NULL,           -- 'features', 'search', 'density', …
  count      bigint      NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (apikey_id, month, route)
);

COMMENT ON TABLE gis.api_usage IS
  'api-gis request counters per API key / month (UTC) / route. Written by api-gis on every /v1/gis request; read for the monthly quota.';
