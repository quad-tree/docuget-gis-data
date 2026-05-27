#!/usr/bin/env bash
# Download one state's DENUE SHP zip(s) from INEGI's bulk-download endpoint.
#
# Usage:
#   ./download_state.sh 01
#   ./download_state.sh 09
#
# Most states resolve to a single zip; a few large ones (e.g. 15 — Edo. de
# México) are split into multiple parts and have a `url_parts_shp` array
# in catalog/states.json. The loop handles both shapes uniformly.
#
# Idempotent: skips download if file exists and ETag matches the remote.
# Honors Last-Modified for resumable / cache-aware behavior.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

CODE="${1:?usage: $0 <state-code 01..32>}"
state_ids "$CODE"

mapfile -t URLS  < <(state_urls_shp "$CODE")
mapfile -t PATHS < <(state_zip_paths "$CODE")

if [[ ${#URLS[@]} -ne ${#PATHS[@]} ]]; then
  fail "internal: url/path count mismatch for state ${CODE}"
fi

step "Download DENUE state ${CODE} (${STATE_NAME}) — ${#URLS[@]} part(s)"

download_one() {
  local url="$1" out="$2"
  local etag_file="$out.etag"

  ok "part: $(basename "$out") ← $url"

  local HEAD REMOTE_ETAG REMOTE_SIZE REMOTE_LM
  HEAD=$(curl -sI -A "docuget-gis-data/1.0" --max-time 30 "$url")
  REMOTE_ETAG=$(echo "$HEAD" | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r"')
  REMOTE_SIZE=$(echo "$HEAD" | awk -F': ' 'tolower($1)=="content-length"{print $2}' | tr -d '\r')
  REMOTE_LM=$(echo "$HEAD" | awk -F': ' 'tolower($1)=="last-modified"{print $2}' | tr -d '\r')
  [[ -n "$REMOTE_ETAG" ]] || warn "no ETag in response — cache check disabled"
  ok "  remote: $(numfmt --to=iec --suffix=B "$REMOTE_SIZE" 2>/dev/null || echo "${REMOTE_SIZE}B")  last-modified: ${REMOTE_LM:-unknown}"

  if [[ -f "$out" && -f "$etag_file" && "$(cat "$etag_file")" == "$REMOTE_ETAG" ]]; then
    ok "  already up to date ($(du -h "$out" | cut -f1)) — skipping"
    return 0
  fi

  step "  downloading $out"
  curl -L -A "docuget-gis-data/1.0" --retry 3 --retry-delay 5 \
    --progress-bar -o "$out" "$url"

  local LOCAL_SIZE
  LOCAL_SIZE=$(stat -c%s "$out")
  if [[ -n "$REMOTE_SIZE" && "$LOCAL_SIZE" != "$REMOTE_SIZE" ]]; then
    fail "size mismatch: local=$LOCAL_SIZE remote=$REMOTE_SIZE"
  fi
  # INEGI occasionally serves an HTML error page with a matching Content-Length —
  # validate that it actually unzips before declaring success.
  if ! unzip -tq "$out" >/dev/null 2>&1; then
    rm -f "$out" "$etag_file"
    fail "downloaded file is not a valid zip — INEGI likely served an error page (re-run later)"
  fi
  printf '%s' "$REMOTE_ETAG" > "$etag_file"
  ok "  saved $out ($(du -h "$out" | cut -f1))"
}

for i in "${!URLS[@]}"; do
  download_one "${URLS[$i]}" "${PATHS[$i]}"
done
