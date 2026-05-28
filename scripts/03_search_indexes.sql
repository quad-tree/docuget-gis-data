-- Migration: search indexes for business name + city resolution
-- Applied: 2026-05-27 on Neon GIS (ep-*-pooler)
-- Context: GIS search P1.1 — name search fallback + city/municipality resolution
--
-- These indexes support three search paths added to POST /v1/gis/search:
--   1. Business name search (nom_estab ILIKE) — fallback when no SCIAN match
--   2. City exact match (search_normalize(municipio) = ?) — step 2 in place resolution
--   3. City trigram match (municipio similarity) — fuzzy city lookup
--
-- Prerequisites: gis.search_normalize() function + pg_trgm extension in gis schema
--   (both created by 02_search.sql)

-- 1. Business name trigram — supports ILIKE '%name%' on 6M+ rows
--    Without this: seq scan ~minutes. With: bitmap index scan ~50ms.
CREATE INDEX CONCURRENTLY IF NOT EXISTS gis_feature_nom_estab_trgm_idx
  ON gis.gis_feature
  USING gin ((props->>'nom_estab') gis.gin_trgm_ops);

-- 2. City/municipality exact match — btree on normalized (accent-stripped) municipio
--    Supports: gis.search_normalize(props->>'municipio') = 'culiacan'
CREATE INDEX CONCURRENTLY IF NOT EXISTS gis_feature_municipio_norm_idx
  ON gis.gis_feature
  (gis.search_normalize(props->>'municipio'));

-- 3. City/municipality trigram — fuzzy city name lookup
--    Supports: gis.similarity(search_normalize(municipio), 'monterey') > 0.35
CREATE INDEX CONCURRENTLY IF NOT EXISTS gis_feature_municipio_trgm_idx
  ON gis.gis_feature
  USING gin ((lower(props->>'municipio')) gis.gin_trgm_ops);
