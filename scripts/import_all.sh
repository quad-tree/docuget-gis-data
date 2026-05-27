#!/usr/bin/env bash
# Import all (or specified) DENUE states into the local PostGIS container.
#
# Usage:
#   ./import_all.sh                # all 32
#   ./import_all.sh 01 09 24       # specific states
#   SKIP_EXISTING=1 ./import_all.sh  # skip layers that already have feature_count > 0

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

FAILED=()
for code in "${CODES[@]}"; do
  state_ids "$code"

  if [[ "${SKIP_EXISTING:-0}" == "1" ]]; then
    COUNT=$(psql_in -tA -c "SELECT COALESCE(feature_count,0) FROM gis.gis_layer WHERE id='${LAYER_ID}';" 2>/dev/null || echo 0)
    if [[ "${COUNT:-0}" -gt 0 ]]; then
      ok "skip $code — layer ${LAYER_ID} already has ${COUNT} rows"
      continue
    fi
  fi

  if "$SCRIPT_DIR/import_state.sh" "$code"; then
    :
  else
    warn "import failed for state $code"
    FAILED+=("$code")
  fi
done

printf '\n\033[1;32m✓ Imported %d states (%d failed).\033[0m\n' \
  $(( ${#CODES[@]} - ${#FAILED[@]} )) "${#FAILED[@]}"
if (( ${#FAILED[@]} > 0 )); then
  printf '  Failed codes: %s\n' "${FAILED[*]}"
  exit 1
fi
