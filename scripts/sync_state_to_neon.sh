#!/usr/bin/env bash
# Promote one state's DENUE layer from local Docker → Neon.
# Thin wrapper over docuget-devops/docker/gis/sync_to_neon.sh that translates
# a state code to the layer id from our catalog.
#
# Usage:
#   varlock run -- ./sync_state_to_neon.sh 24
#
# Requires GIS_DATABASE_URL in env (use `varlock run --` from a repo that
# declares it in .env.schema — e.g. /home/docuget/docuget_api).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CODE="${1:?usage: $0 <state-code 01..32>}"
state_ids "$CODE"

DEVOPS_SYNC="$(dirname "$GIS_DATA_ROOT")/docuget-devops/docker/gis/sync_to_neon.sh"
[[ -f "$DEVOPS_SYNC" ]] || fail "devops sync script not found: $DEVOPS_SYNC"

step "Sync ${LAYER_ID} (${STATE_NAME}) → Neon"
"$DEVOPS_SYNC" "$LAYER_ID"
