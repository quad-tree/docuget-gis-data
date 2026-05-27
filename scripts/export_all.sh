#!/usr/bin/env bash
# Export all (or specified) DENUE state layers as portable .sql.gz dumps in dist/.
#
# Usage:
#   ./export_all.sh                # all 32
#   ./export_all.sh 01 09 24       # specific states
#   FORMAT=plain ./export_all.sh   # leave uncompressed

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

FORMAT="${FORMAT:-gz}"
FAILED=()
for code in "${CODES[@]}"; do
  if "$SCRIPT_DIR/export_state_dump.sh" "$code" "$FORMAT"; then
    :
  else
    warn "export failed for state $code"
    FAILED+=("$code")
  fi
done

printf '\n\033[1;32m✓ Exported %d states (%d failed).\033[0m\n' \
  $(( ${#CODES[@]} - ${#FAILED[@]} )) "${#FAILED[@]}"
ls -lh "$GIS_DIST_DIR"
if (( ${#FAILED[@]} > 0 )); then
  printf '  Failed codes: %s\n' "${FAILED[*]}"
  exit 1
fi
