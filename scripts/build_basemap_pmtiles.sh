#!/usr/bin/env bash
# Build the self-hosted vector basemap for Mexico: OpenStreetMap (Geofabrik
# extract) → planetiler → dist/basemap/mexico-<date>.pmtiles, OpenMapTiles
# schema — the SAME schema OpenFreeMap serves, so the styles in
# docuget_api/functions/gis_vector_basemap.ts read it unchanged.
#
# Why (plan docuget-skills/plans/modules/gis/vector-basemaps, V3): on
# 2026-09-23 CARTO started watermarking key-less tiles overnight. OpenFreeMap
# is free and donation-funded too; this file is what keeps the printed maps
# (PaperStudio / gen:denue-map) vector-sharp if it ever changes terms.
#
# The data freezes on the extract date — re-run quarterly, then publish with
#   (docuget-devops) varlock run -- deno run -A scripts/publish_basemap_pmtiles.ts \
#     ../docuget-gis-data/dist/basemap/mexico-<date>.pmtiles --registrar
#
# Usage:
#   ./build_basemap_pmtiles.sh              # mexico
#   AREA=mexico XMX=8g ./build_basemap_pmtiles.sh
#
# Needs Docker. ~700 MB OSM extract + ~1 GB of planetiler's global sources
# (water polygons, Natural Earth, lake centerlines) cached in downloads/basemap.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AREA="${AREA:-mexico}"
XMX="${XMX:-8g}"
IMAGE="${IMAGE:-ghcr.io/onthegomap/planetiler:latest}"
DATE="$(date +%Y%m%d)"
WORK="$ROOT/downloads/basemap"   # sources + planetiler temp (~several GB)
OUT="$ROOT/dist/basemap"
OWNER="$(stat -c %u "$ROOT"):$(stat -c %g "$ROOT")"
mkdir -p "$WORK/sources" "$WORK/tmp" "$OUT"
# The container runs as the repo owner — the dirs must be theirs too (a run as
# root would otherwise leave root-owned dirs the container can't write).
chown -R "$OWNER" "$WORK" "$OUT" 2>/dev/null || true

# Pull anonymously: a stale ghcr.io credential in the caller's docker config
# makes the registry answer "denied" even for this PUBLIC image (seen
# 2026-09-25). A throwaway DOCKER_CONFIG sidesteps it without touching the
# stored login other pipelines may rely on.
if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
  ANON="$(mktemp -d)"
  DOCKER_CONFIG="$ANON" docker pull "$IMAGE"
  rm -rf "$ANON"
fi

echo "▶ planetiler · area=$AREA · heap=$XMX · → dist/basemap/$AREA-$DATE.pmtiles"
START=$SECONDS
docker run --rm \
  --user "$OWNER" \
  -e JAVA_TOOL_OPTIONS="-Xmx$XMX" \
  -v "$WORK":/data \
  -v "$OUT":/out \
  "$IMAGE" \
  --download \
  --area="$AREA" \
  --download_dir=/data/sources \
  --tmpdir=/data/tmp \
  --output="/out/$AREA-$DATE.pmtiles" \
  --force

ls -la "$OUT/$AREA-$DATE.pmtiles"
echo "✓ $(( (SECONDS - START) / 60 )) min"
