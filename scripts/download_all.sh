#!/usr/bin/env bash
# Download all 32 DENUE state ZIPs from INEGI.
# Idempotent — skips files whose ETag already matches the remote.
#
# Usage:
#   ./download_all.sh                    # all 32 states
#   ./download_all.sh 01 09 24           # specific states
#   ONLY_MISSING=1 ./download_all.sh     # skip codes with existing zips

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if (( $# > 0 )); then
  CODES=("$@")
else
  mapfile -t CODES < <(state_codes_all)
fi

FAILED=()
for code in "${CODES[@]}"; do
  if [[ "${ONLY_MISSING:-0}" == "1" && -f "$GIS_DOWNLOADS_DIR/denue_${code}_shp.zip" ]]; then
    ok "skip $code (already present)"
    continue
  fi
  if "$SCRIPT_DIR/download_state.sh" "$code"; then
    :
  else
    warn "download failed for state $code"
    FAILED+=("$code")
  fi
done

printf '\n\033[1;32m✓ Downloaded %d states (%d failed).\033[0m\n' \
  $(( ${#CODES[@]} - ${#FAILED[@]} )) "${#FAILED[@]}"
if (( ${#FAILED[@]} > 0 )); then
  printf '  Failed codes: %s\n' "${FAILED[*]}"
  exit 1
fi
