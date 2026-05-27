#!/usr/bin/env bash
# End-to-end local batch: for every state in the catalog, download (if missing),
# import (if not yet loaded), and dump to dist/. State-by-state checkpointing
# so a partial run is easy to resume.
#
# Usage:
#   ./batch_local.sh                 # all 32 states
#   ./batch_local.sh 02 03 04        # specific states
#   FORCE_REIMPORT=1 ./batch_local.sh  # ignore SKIP_EXISTING on imports

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_container

if (( $# > 0 )); then
  CODES=("$@")
else
  mapfile -t CODES < <(state_codes_all)
fi

SKIP_EXISTING="${SKIP_EXISTING:-1}"
if [[ "${FORCE_REIMPORT:-0}" == "1" ]]; then SKIP_EXISTING=0; fi

TOTAL=${#CODES[@]}
i=0
FAILED=()
START_ALL=$SECONDS

for code in "${CODES[@]}"; do
  i=$((i+1))
  state_ids "$code"
  echo
  echo "============================================================"
  printf "▶ [%d/%d] State %s — %s\n" "$i" "$TOTAL" "$code" "$STATE_NAME"
  echo "============================================================"
  STATE_START=$SECONDS

  # Stage 1: download
  if "$SCRIPT_DIR/download_state.sh" "$code"; then :; else
    warn "download failed for $code — skipping rest of pipeline"
    FAILED+=("$code:download")
    continue
  fi

  # Stage 2: import (skip if layer already populated, unless FORCE_REIMPORT)
  if [[ "$SKIP_EXISTING" == "1" ]]; then
    COUNT=$(psql_in -tA -c "SELECT COALESCE(feature_count,0) FROM gis.gis_layer WHERE id='${LAYER_ID}';" 2>/dev/null || echo 0)
    if [[ "${COUNT:-0}" -gt 0 ]]; then
      ok "import skipped — layer ${LAYER_ID} already has ${COUNT} rows"
    else
      if "$SCRIPT_DIR/import_state.sh" "$code"; then :; else
        warn "import failed for $code"
        FAILED+=("$code:import")
        continue
      fi
    fi
  else
    if "$SCRIPT_DIR/import_state.sh" "$code"; then :; else
      warn "import failed for $code"
      FAILED+=("$code:import")
      continue
    fi
  fi

  # Stage 3: dump
  if "$SCRIPT_DIR/export_state_dump.sh" "$code" gz; then :; else
    warn "export failed for $code"
    FAILED+=("$code:export")
    continue
  fi

  printf "✓ state %s done in %ds\n" "$code" "$((SECONDS-STATE_START))"
done

echo
echo "============================================================"
printf "✓ Batch complete in %ds  (%d states, %d failures)\n" \
  "$((SECONDS-START_ALL))" "$TOTAL" "${#FAILED[@]}"
echo "============================================================"
if (( ${#FAILED[@]} > 0 )); then
  echo "Failures:"
  printf '  - %s\n' "${FAILED[@]}"
fi
echo
echo "Artifacts:"
ls -lh "$GIS_DIST_DIR"/*.sql.gz 2>/dev/null || echo "(none yet)"

# Non-zero exit so CI / wrappers can tell when stages failed.
if (( ${#FAILED[@]} > 0 )); then
  exit 1
fi
