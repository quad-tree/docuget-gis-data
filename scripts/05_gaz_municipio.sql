-- Migration 05: gis.gaz_municipio — municipality dictionary for fast city resolution
-- Applied: 2026-05-28 on Neon GIS (ep-*-pooler)
-- Context: GIS search — city/municipality resolution (steps 2 & 6 in
--   POST /v1/gis/search) was a Parallel Seq Scan over all 6.1M rows of
--   lyr_denue_mx, computing gis.similarity(search_normalize(municipio), ?)
--   per row. Measured 7.6s for "san luis potosi capital" (fuzzy fallback).
--
-- There are only ~2,476 distinct municipios, so we precompute a dictionary —
-- mirroring the gaz_state / gaz_region pattern — and resolve city names
-- against it instead of the fact table. Resolution drops to sub-millisecond.
--
-- REBUILD this table whenever the national layer (lyr_denue_mx) is reloaded:
-- it is derived from gis_feature and goes stale if the DENUE corpus changes.
--
-- Prerequisites: gis.search_normalize() + pg_trgm (gis schema) from 02_search.sql.

DROP TABLE IF EXISTS gis.gaz_municipio;

CREATE TABLE gis.gaz_municipio (
  id            text PRIMARY KEY,            -- entidad || '|' || municipio
  municipio     text NOT NULL,               -- "San Luis Potosí"
  entidad       text NOT NULL,               -- state name, "San Luis Potosí"
  name_norm     text NOT NULL,               -- gis.search_normalize(municipio)
  centroid      geometry(Point, 4326),       -- mean of member-feature points
  feature_count integer NOT NULL
);

INSERT INTO gis.gaz_municipio (id, municipio, entidad, name_norm, centroid, feature_count)
SELECT
  (props->>'entidad') || '|' || (props->>'municipio'),
  props->>'municipio',
  props->>'entidad',
  gis.search_normalize(props->>'municipio'),
  ST_SetSRID(ST_MakePoint(AVG(ST_X(geom)), AVG(ST_Y(geom))), 4326),
  count(*)::int
FROM gis.gis_feature
WHERE layer_id = 'lyr_denue_mx'
  AND props->>'municipio' IS NOT NULL
  AND props->>'entidad'   IS NOT NULL
GROUP BY props->>'entidad', props->>'municipio';

-- Exact lookup: name_norm = ? (step 2 cityExact).
CREATE INDEX gaz_municipio_name_norm_idx ON gis.gaz_municipio (name_norm);
-- Fuzzy lookup: name_norm % ? / <-> ? (step 6 cityMatch).
CREATE INDEX gaz_municipio_name_trgm ON gis.gaz_municipio
  USING gin (name_norm gis.gin_trgm_ops);

ANALYZE gis.gaz_municipio;
