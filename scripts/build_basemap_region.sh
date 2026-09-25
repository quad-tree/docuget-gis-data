#!/usr/bin/env bash
# Mexico + border strip basemap: our only vector source, so the DENUE viewer
# and the PDF renderer stop needing OpenFreeMap for anything in the region.
#
# Mexico alone left the other side of every border city EMPTY (Tijuana
# without San Diego), which is why OpenFreeMap still served border tiles.
# This adds, from Geofabrik:
#   · the four US border states, CLIPPED to a strip (STRIP_BBOX) — whole
#     California/Texas would be ~2 GB of data nobody here looks at;
#   · Guatemala and Belize, whole (small).
# osmium (in a throwaway Debian container — nothing installed on the host)
# clips and merges; planetiler builds the OpenMapTiles-schema PMTiles.
#
# Output: dist/basemap/mexico-frontera-<date>.pmtiles
# Then (docuget-devops):
#   varlock run -- deno run -A scripts/publish_basemap_pmtiles.ts \
#     ../docuget-gis-data/dist/basemap/mexico-frontera-<date>.pmtiles --region mexico-frontera --registrar
#
# Re-run quarterly (data freezes on the extract date), like build_basemap_pmtiles.sh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ~150-200 km north of the border, from the Pacific (incl. the Channel
# Islands — a narrower strip left Tijuana's z8 tile half outside the coverage,
# served by OpenFreeMap) to the Gulf. KEEP IN SYNC with the `rects` of
# publish_basemap_pmtiles.ts --region mexico-frontera.
STRIP_BBOX="${STRIP_BBOX:--120.5,25.5,-96.8,34.5}"
XMX="${XMX:-8g}"
IMAGE="${IMAGE:-ghcr.io/onthegomap/planetiler:latest}"
DATE="$(date +%Y%m%d)"
# Override for a same-day rebuild: published archives are `immutable` in R2,
# so a new build must never reuse a name.
NAME="${NAME:-mexico-frontera-$DATE}"
WORK="$ROOT/downloads/basemap"
OUT="$ROOT/dist/basemap"
OWNER="$(stat -c %u "$ROOT"):$(stat -c %g "$ROOT")"
mkdir -p "$WORK/sources" "$WORK/region" "$WORK/tmp" "$OUT"
chown -R "$OWNER" "$WORK" "$OUT" 2>/dev/null || true

GF=https://download.geofabrik.de
declare -A SRC=(
  [mexico]="$GF/north-america/mexico-latest.osm.pbf"
  [california]="$GF/north-america/us/california-latest.osm.pbf"
  [arizona]="$GF/north-america/us/arizona-latest.osm.pbf"
  [new-mexico]="$GF/north-america/us/new-mexico-latest.osm.pbf"
  [texas]="$GF/north-america/us/texas-latest.osm.pbf"
  [guatemala]="$GF/central-america/guatemala-latest.osm.pbf"
  [belize]="$GF/central-america/belize-latest.osm.pbf"
)
for k in "${!SRC[@]}"; do
  f="$WORK/region/$k.osm.pbf"
  if [[ ! -s "$f" ]]; then
    echo "↓ $k"
    curl -sfL -o "$f.part" "${SRC[$k]}" && mv "$f.part" "$f"
  fi
done
ls -la "$WORK/region"/*.osm.pbf

ANON="$(mktemp -d)" # anonymous pulls: a stale ghcr.io login answers "denied"
echo "▶ osmium: recortar EE. UU. a la franja $STRIP_BBOX y fundir"
DOCKER_CONFIG="$ANON" docker run --rm -v "$WORK/region":/r debian:bookworm-slim bash -c "
  set -e
  apt-get update -qq > /dev/null && apt-get install -y -qq osmium-tool > /dev/null
  cd /r
  for s in california arizona new-mexico texas; do
    osmium extract -b $STRIP_BBOX --strategy=complete_ways -O -o \$s-strip.osm.pbf \$s.osm.pbf
  done
  osmium merge -O -o region.osm.pbf mexico.osm.pbf guatemala.osm.pbf belize.osm.pbf \
    california-strip.osm.pbf arizona-strip.osm.pbf new-mexico-strip.osm.pbf texas-strip.osm.pbf
  osmium fileinfo -e region.osm.pbf | grep -E 'Bounding|Number of (nodes|ways)'
  chown $OWNER /r/*.pbf
"

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
  DOCKER_CONFIG="$ANON" docker pull "$IMAGE"
fi
rm -rf "$ANON"

echo "▶ planetiler · región México + franja · → dist/basemap/$NAME.pmtiles"
START=$SECONDS
docker run --rm \
  --user "$OWNER" \
  -e JAVA_TOOL_OPTIONS="-Xmx$XMX" \
  -v "$WORK":/data \
  -v "$OUT":/out \
  "$IMAGE" \
  --download \
  --osm_path=/data/region/region.osm.pbf \
  --download_dir=/data/sources \
  --tmpdir=/data/tmp \
  --output="/out/$NAME.pmtiles" \
  --force

ls -la "$OUT/$NAME.pmtiles"
echo "✓ $(((SECONDS - START) / 60)) min"
