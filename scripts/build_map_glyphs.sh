#!/usr/bin/env bash
# Map label glyphs (SDF .pbf ranges) for Inter — the font the PDF renderer
# already uses — so the live map (MapLibre) and the printed map share letters,
# and the front stops fetching glyphs from a third party.
#
# Output: dist/glyphs/{Inter Regular,Inter Bold,Inter Italic}/{0-255..65280-65535}.pbf
# Publish: (docuget-devops) varlock run -- deno run -A scripts/publish_map_glyphs.ts ../docuget-gis-data/dist/glyphs
#
# fontnik's build-glyphs ships prebuilt binaries for Node 14 — hence the image.
# Inter (OFL) comes from the official release zip, pinned.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INTER_ZIP="${INTER_ZIP:-https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip}"
WORK="$ROOT/downloads/glyphs"
OUT="$ROOT/dist/glyphs"
mkdir -p "$WORK" "$OUT"
OWNER="$(stat -c %u "$ROOT"):$(stat -c %g "$ROOT")"
chown -R "$OWNER" "$WORK" "$OUT" 2>/dev/null || true # the container runs as the repo owner

[[ -f "$WORK/inter.zip" ]] || curl -sL -o "$WORK/inter.zip" "$INTER_ZIP"
for f in Regular Bold Italic; do
  unzip -o -j -q "$WORK/inter.zip" "extras/ttf/Inter-$f.ttf" -d "$WORK"
done

ANON="$(mktemp -d)" # anonymous pulls — see build_basemap_pmtiles.sh
DOCKER_CONFIG="$ANON" docker run --rm \
  --user "$OWNER" -e HOME=/tmp \
  -v "$WORK":/in -v "$OUT":/out node:14-bullseye bash -c '
    cd /tmp && npm i fontnik@0.7.2 > /dev/null 2>&1
    for f in Regular Bold Italic; do
      mkdir -p "/out/Inter $f"
      ./node_modules/.bin/build-glyphs "/in/Inter-$f.ttf" "/out/Inter $f"
    done'
rm -rf "$ANON"
for d in "$OUT"/*; do echo "✓ $(basename "$d"): $(ls "$d" | wc -l) rangos"; done
