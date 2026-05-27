#!/usr/bin/env bash
# Import one state's DENUE shapefile into the local PostGIS container.
# Generalized from docuget-devops/docker/gis/import_denue_slp.sh.
#
# Inputs:
#   $1 — state code (01..32)
#   GIS_DB_PASSWORD env (or DB_PASSWORD via .env)
#
# Idempotent: re-running for the same state drops & reloads the layer.
# Side effects: also upserts the gis_dataset row (one dataset per state).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CODE="${1:?usage: $0 <state-code 01..32>}"
state_ids "$CODE"

mapfile -t ZIPS < <(state_zip_paths "$CODE")
for z in "${ZIPS[@]}"; do
  [[ -f "$z" ]] || fail "zip not found: $z — run ./download_state.sh $CODE first"
done

require_container

WORK_DIR=$(mktemp -d -t denue-${CODE}-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

step "Import DENUE ${CODE} (${STATE_NAME}) → layer ${LAYER_ID} (${#ZIPS[@]} part(s))"

step "Unzip"
for i in "${!ZIPS[@]}"; do
  PART_DIR="$WORK_DIR/p$((i+1))"
  mkdir -p "$PART_DIR"
  unzip -q "${ZIPS[$i]}" -d "$PART_DIR"
done
mapfile -t SHP_PATHS < <(find "$WORK_DIR" -type f -iname '*.shp' | sort)
[[ ${#SHP_PATHS[@]} -gt 0 ]] || fail "no .shp found inside ${ZIPS[*]}"
for p in "${SHP_PATHS[@]}"; do ok "found $(basename "$p")"; done

step "Upsert dataset + layer rows"
psql_in <<SQL
INSERT INTO gis.gis_dataset (id, company_id, slug, name, source, metadata)
VALUES (
  '${DATASET_ID}',
  'public',
  '${DATASET_SLUG}',
  '${DATASET_NAME}',
  'denue',
  jsonb_build_object(
    'license',     'INEGI — Términos de Libre Uso',
    'license_url', 'https://www.inegi.org.mx/inegi/terminos.html',
    'citation',    'INEGI. Directorio Estadístico Nacional de Unidades Económicas (DENUE).',
    'vintage',     '${VINTAGE}',
    'entidad',     ${CODE}::int,
    'entidad_name','${STATE_NAME}',
    'source_url',  '$(state_urls_shp "$CODE" | head -1)',
    'source_zip',  '$(printf "%s " "${ZIPS[@]##*/}" | sed "s/ $//")'
  )
)
ON CONFLICT (company_id, slug) DO UPDATE
   SET name     = EXCLUDED.name,
       metadata = EXCLUDED.metadata;

INSERT INTO gis.gis_layer (id, dataset_id, name, geometry_type, srid)
VALUES ('${LAYER_ID}', '${DATASET_ID}', '${LAYER_NAME}', 'point', 4326)
ON CONFLICT (id) DO UPDATE
   SET dataset_id = EXCLUDED.dataset_id,
       name       = EXCLUDED.name;
SQL
ok "dataset ${DATASET_SLUG} + layer ${LAYER_ID} upserted"

step "Clear prior features for ${LAYER_ID} (idempotent re-import)"
psql_in -c "DELETE FROM gis.gis_feature WHERE layer_id = '${LAYER_ID}';" >/dev/null
psql_in -c "DROP TABLE IF EXISTS ${STAGING_TABLE};" >/dev/null
ok "cleared"

step "ogr2ogr → staging table (dockerized GDAL)"
for i in "${!SHP_PATHS[@]}"; do
  SHP_PATH="${SHP_PATHS[$i]}"
  SHP_DIR="$(dirname "$SHP_PATH")"
  SHP_NAME="$(basename "$SHP_PATH")"
  if [[ $i -eq 0 ]]; then
    MODE_FLAGS=(-overwrite)
  else
    MODE_FLAGS=(-update -append)
  fi
  ok "  loading $SHP_NAME (${MODE_FLAGS[*]})"
  docker run --rm \
    --network "$GIS_DB_NETWORK" \
    -v "$SHP_DIR:/data:ro" \
    -e PGPASSWORD="$GIS_DB_PASSWORD" \
    "$GDAL_IMAGE" \
    ogr2ogr \
      -f PostgreSQL \
      PG:"host=${GIS_DB_HOST_IN_NETWORK} port=5432 dbname=${GIS_DB_NAME} user=${GIS_DB_USER}" \
      "/data/${SHP_NAME}" \
      -oo ENCODING=ISO-8859-1 \
      -nln "${STAGING_TABLE}" \
      -lco GEOMETRY_NAME=geom \
      -lco FID=ogr_fid \
      -lco PRECISION=NO \
      -t_srs EPSG:4326 \
      "${MODE_FLAGS[@]}" \
      --config PG_USE_COPY YES
done
ok "staging populated"

step "Promote staging → gis.gis_feature"
psql_in <<SQL
INSERT INTO gis.gis_feature (layer_id, geom, props)
SELECT
  '${LAYER_ID}',
  ST_Force2D(geom)::geometry(Geometry, 4326),
  to_jsonb(s.*) - 'geom' - 'ogr_fid'
FROM ${STAGING_TABLE} s;

UPDATE gis.gis_layer
   SET feature_count = (SELECT count(*) FROM gis.gis_feature WHERE layer_id = '${LAYER_ID}')
 WHERE id = '${LAYER_ID}';

DROP TABLE ${STAGING_TABLE};
SQL

COUNT=$(psql_in -tA -c "SELECT feature_count FROM gis.gis_layer WHERE id='${LAYER_ID}';")
ok "feature_count = $COUNT"

BBOX=$(psql_in -tA -c "SELECT ST_AsText(ST_Extent(geom)) FROM gis.gis_feature WHERE layer_id='${LAYER_ID}';")
ok "extent: $BBOX"

printf '\n\033[1;32m✓ Import done.\033[0m  state=%s layer=%s rows=%s\n' "$CODE" "$LAYER_ID" "$COUNT"
