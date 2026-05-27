#!/usr/bin/env bash
# Download pre-built DENUE snapshots from the CDN into dist/.
#
# Usage:
#   ./scripts/download.sh 24        # one state
#   ./scripts/download.sh all       # every state
#   ./scripts/download.sh mx        # the national rollup
#   ./scripts/download.sh full      # all 32 states + rollup
#
# Env vars:
#   DATA_VERSION     # e.g. v2025.06  (default: v2025.06)
#   DATA_BASE_URL    # override the CDN base URL
#
# Requires: curl.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

WHAT="${1:?usage: $0 <state-code 01..32 | all | mx | full>}"
DATA_VERSION="${DATA_VERSION:-v2025.06}"
DATA_BASE_URL="${DATA_BASE_URL:-https://mex1co.sfo3.digitaloceanspaces.com/gis-data/${DATA_VERSION}}"
DIST_DIR="$REPO_DIR/dist"
mkdir -p "$DIST_DIR"

fetch_one() {
  local name="$1"
  local url="${DATA_BASE_URL}/${name}"
  local dest="${DIST_DIR}/${name}"

  if [[ -f "$dest" ]]; then
    ok "skip $name (already exists)"
    return
  fi

  step "Downloading $name"
  curl -L --fail --retry 3 --retry-delay 5 --progress-bar -o "$dest" "$url"
  ok "$(du -h "$dest" | cut -f1)"
}

case "$WHAT" in
  all)
    mapfile -t CODES < <(state_codes_all)
    for code in "${CODES[@]}"; do fetch_one "denue_${code}.sql.gz"; done
    ;;
  mx|MX)
    fetch_one "denue_mx.sql.gz"
    ;;
  full)
    mapfile -t CODES < <(state_codes_all)
    for code in "${CODES[@]}"; do fetch_one "denue_${code}.sql.gz"; done
    fetch_one "denue_mx.sql.gz"
    ;;
  [0-9][0-9])
    fetch_one "denue_${WHAT}.sql.gz"
    ;;
  *)
    fail "unknown target '$WHAT' (expected state code 01..32, 'all', 'mx', or 'full')"
    ;;
esac

printf '\n\033[1;32m✓ Download complete. Files in %s\033[0m\n' "$DIST_DIR"
ls -lh "$DIST_DIR"/*.sql.gz 2>/dev/null | tail -5
