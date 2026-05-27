#!/usr/bin/env bash
# End-user quickstart: download a pre-built snapshot and restore it into a
# local PostgreSQL/PostGIS database.
#
# Usage:
#   ./quickstart.sh 24            # one state
#   ./quickstart.sh all           # every state (sequentially, ~5 min)
#   ./quickstart.sh mx            # the rolled-up national snapshot
#
# Env vars:
#   PGURL                          # full libpq URL (overrides the rest)
#   PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD   # standard libpq env
#   DATA_VERSION                   # e.g. v2025.06  (default: v2025.06)
#   DATA_BASE_URL                  # override the CDN base URL
#
# Requires: curl, gunzip, psql.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

WHAT="${1:?usage: $0 <state-code 01..32 | all | mx>}"
DATA_VERSION="${DATA_VERSION:-v2025.06}"
DATA_BASE_URL="${DATA_BASE_URL:-https://mex1co.sfo3.digitaloceanspaces.com/gis-data/${DATA_VERSION}}"

if [[ -n "${PGURL:-}" ]]; then
  PSQL=(psql "$PGURL" -v ON_ERROR_STOP=1)
else
  PSQL=(psql -v ON_ERROR_STOP=1)
fi

asset_url() {
  printf '%s/%s' "$DATA_BASE_URL" "$1"
}

restore_one() {
  local name="$1"
  local url
  url=$(asset_url "$name")
  step "Download + restore $name"
  ok "url: $url"
  curl -L --fail --retry 3 --retry-delay 5 -o "/tmp/$name" "$url"
  ok "downloaded $(du -h "/tmp/$name" | cut -f1)"
  gunzip -c "/tmp/$name" | "${PSQL[@]}"
  rm -f "/tmp/$name"
}

case "$WHAT" in
  all)
    mapfile -t CODES < <(state_codes_all)
    for code in "${CODES[@]}"; do restore_one "denue_${code}.sql.gz"; done
    ;;
  mx|MX)
    restore_one "denue_mx.sql.gz"
    ;;
  [0-9][0-9])
    restore_one "denue_${WHAT}.sql.gz"
    ;;
  *)
    fail "unknown target '$WHAT' (expected state code 01..32, 'all', or 'mx')"
    ;;
esac

printf '\n\033[1;32m✓ Restore complete.\033[0m\n'
"${PSQL[@]}" -c "SELECT id, feature_count FROM gis.gis_layer ORDER BY id;"
