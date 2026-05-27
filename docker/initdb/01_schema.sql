-- Base schema for the loader. The same tables get embedded in every
-- denue_XX.sql.gz artifact via CREATE TABLE IF NOT EXISTS, so this file
-- only matters when bringing up an *empty* loader from scratch.

CREATE SCHEMA IF NOT EXISTS gis;

CREATE TABLE IF NOT EXISTS gis.gis_dataset (
  id          text PRIMARY KEY,
  company_id  text NOT NULL DEFAULT 'public',
  slug        text NOT NULL,
  name        text NOT NULL,
  source      text NOT NULL,
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, slug)
);

CREATE TABLE IF NOT EXISTS gis.gis_layer (
  id              text PRIMARY KEY,
  dataset_id      text NOT NULL REFERENCES gis.gis_dataset(id) ON DELETE CASCADE,
  name            text NOT NULL,
  geometry_type   text NOT NULL,
  srid            int  NOT NULL DEFAULT 4326,
  schema          jsonb NOT NULL DEFAULT '{}'::jsonb,
  feature_count   bigint NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gis.gis_feature (
  id          bigserial PRIMARY KEY,
  layer_id    text NOT NULL REFERENCES gis.gis_layer(id) ON DELETE CASCADE,
  geom        geometry(Geometry, 4326),
  props       jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS gis_feature_geom_gix  ON gis.gis_feature USING GIST (geom);
CREATE INDEX IF NOT EXISTS gis_feature_layer_idx ON gis.gis_feature (layer_id);
