#!/usr/bin/env bash
# Shared helpers for the docuget-gis-data pipeline.
#
# Pipeline stages (download → import → sync → export) all source this file
# for the state catalog lookup, env defaults, and logging primitives.
#
# Env vars (defaults shown):
#   GIS_DB_CONTAINER=docuget-gis-db   # docker container name running PostGIS
#   GIS_DB_NETWORK=gis_default        # docker network the container is on
#   GIS_DB_NAME=docuget_gis           # database
#   GIS_DB_USER=docuget               # role
#   GIS_DB_PASSWORD                   # required (no default)
#   GIS_DB_HOST_IN_NETWORK=docuget-gis-db   # hostname used by sibling containers (e.g. GDAL)
#   GIS_DATA_ROOT=...                 # root of this repo (auto-detected from script location)
#   GIS_DOWNLOADS_DIR=$GIS_DATA_ROOT/downloads
#   GIS_DIST_DIR=$GIS_DATA_ROOT/dist
#   GDAL_IMAGE=ghcr.io/osgeo/gdal:alpine-small-latest
#   POSTGIS_IMAGE=postgis/postgis:18-3.6-alpine

set -euo pipefail

# ---- paths ------------------------------------------------------------------
GIS_DATA_ROOT="${GIS_DATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export GIS_DATA_ROOT
GIS_DOWNLOADS_DIR="${GIS_DOWNLOADS_DIR:-$GIS_DATA_ROOT/downloads}"
GIS_DIST_DIR="${GIS_DIST_DIR:-$GIS_DATA_ROOT/dist}"
GIS_CATALOG="$GIS_DATA_ROOT/catalog/states.json"
mkdir -p "$GIS_DOWNLOADS_DIR" "$GIS_DIST_DIR"

# ---- env --------------------------------------------------------------------
# Source .env from (in order): repo .env, then docuget-devops/docker/gis/.env
# (so Enrique gets zero-config when the devops container is already up).
for envfile in \
  "$GIS_DATA_ROOT/.env" \
  "$GIS_DATA_ROOT/scripts/.env" \
  "$(dirname "$GIS_DATA_ROOT")/docuget-devops/docker/gis/.env"
do
  if [[ -f "$envfile" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$envfile"; set +a
    break
  fi
done

: "${GIS_DB_CONTAINER:=docuget-gis-db}"
: "${GIS_DB_NETWORK:=gis_default}"
: "${GIS_DB_NAME:=docuget_gis}"
: "${GIS_DB_USER:=docuget}"
: "${GIS_DB_HOST_IN_NETWORK:=docuget-gis-db}"
: "${GDAL_IMAGE:=ghcr.io/osgeo/gdal:alpine-small-latest}"
: "${POSTGIS_IMAGE:=postgis/postgis:18-3.6-alpine}"

# Accept DB_PASSWORD as a back-compat alias for GIS_DB_PASSWORD
: "${GIS_DB_PASSWORD:=${DB_PASSWORD:-}}"

# ---- logging ----------------------------------------------------------------
step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '  \033[1;33m⚠ %s\033[0m\n' "$*"; }
fail() { printf '  \033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---- catalog lookup ---------------------------------------------------------
# state_field <code> <field>   → prints the catalog value (uses jq)
state_field() {
  local code="$1" field="$2"
  command -v jq >/dev/null 2>&1 || fail "jq not installed (apt-get install jq)"
  [[ -f "$GIS_CATALOG" ]] || fail "catalog not found: $GIS_CATALOG"
  local v
  v=$(jq -r --arg c "$code" --arg f "$field" \
    '.states[] | select(.code == $c) | .[$f] // empty' "$GIS_CATALOG")
  [[ -n "$v" ]] || fail "state code '$code' field '$field' not found in catalog"
  printf '%s' "$v"
}

# state_codes_all  → prints "01\n02\n...\n32"
state_codes_all() {
  jq -r '.states[].code' "$GIS_CATALOG"
}

# state_url_shp <code>  → prints the canonical INEGI SHP download URL
state_url_shp() {
  local code="$1" pattern
  pattern=$(jq -r '.source.url_pattern_shp' "$GIS_CATALOG")
  printf '%s' "${pattern//\{code\}/$code}"
}

# state_urls_shp <code>  → prints one or more URLs, one per line.
# If the catalog row has `url_parts_shp`, returns that array (multi-zip states
# like 15 — Edo. de México). Otherwise returns the single pattern URL.
state_urls_shp() {
  local code="$1" parts
  parts=$(jq -r --arg c "$code" \
    '.states[] | select(.code == $c) | .url_parts_shp // [] | .[]' \
    "$GIS_CATALOG")
  if [[ -n "$parts" ]]; then
    printf '%s\n' "$parts"
  else
    state_url_shp "$code"
    printf '\n'
  fi
}

# state_zip_paths <code>  → prints expected local zip paths (one per part), in URL order.
# Single-part states keep the original `denue_{code}_shp.zip` name.
# Multi-part states get `denue_{code}_p{n}_shp.zip` (1-indexed).
state_zip_paths() {
  local code="$1"
  local urls=()
  mapfile -t urls < <(state_urls_shp "$code")
  if [[ ${#urls[@]} -le 1 ]]; then
    printf '%s\n' "$GIS_DOWNLOADS_DIR/denue_${code}_shp.zip"
  else
    local i
    for i in "${!urls[@]}"; do
      printf '%s\n' "$GIS_DOWNLOADS_DIR/denue_${code}_p$((i+1))_shp.zip"
    done
  fi
}

# state_ids <code>  → exports DATASET_ID, DATASET_SLUG, DATASET_NAME, LAYER_ID, STAGING_TABLE, STATE_NAME, STATE_SLUG
# Vintage comes from the catalog (source.vintage). Single source of truth, no per-script drift.
state_ids() {
  local code="$1"
  STATE_NAME=$(state_field "$code" name)
  STATE_SLUG=$(state_field "$code" slug)
  VINTAGE=$(jq -r '.source.vintage' "$GIS_CATALOG")
  DATASET_ID="ds_denue_${STATE_SLUG}_${VINTAGE}"
  DATASET_SLUG="denue-${STATE_SLUG}-${VINTAGE}"
  DATASET_NAME="DENUE — ${STATE_NAME} (${VINTAGE})"
  LAYER_ID="lyr_denue_${STATE_SLUG}"
  LAYER_NAME="DENUE points — ${STATE_NAME}"
  STAGING_TABLE="gis.gis_feature_staging_${STATE_SLUG}"
  export STATE_NAME STATE_SLUG VINTAGE DATASET_ID DATASET_SLUG DATASET_NAME LAYER_ID LAYER_NAME STAGING_TABLE
}

# ---- container helpers ------------------------------------------------------
require_container() {
  docker inspect -f '{{.State.Status}}' "$GIS_DB_CONTAINER" >/dev/null 2>&1 \
    || fail "container '$GIS_DB_CONTAINER' not running — bring it up: cd docuget-devops/docker/gis && docker compose up -d"
}

psql_in() {
  : "${GIS_DB_PASSWORD:?GIS_DB_PASSWORD not set}"
  docker exec -i -e PGPASSWORD="$GIS_DB_PASSWORD" "$GIS_DB_CONTAINER" \
    psql -U "$GIS_DB_USER" -d "$GIS_DB_NAME" -v ON_ERROR_STOP=1 "$@"
}
