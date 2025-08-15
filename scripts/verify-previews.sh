#!/usr/bin/env bash
set -euo pipefail
# Simple preview endpoint verification.
# Requirements: running Nextcloud at http://localhost:8080 with admin user existing.
# The script expects assets to have been uploaded already OR will attempt upload via WebDAV.

NC_BASE="http://localhost:8080"
USER="admin"
PASS="admin"
ASSET_DIR="tests/assets/cache"
REPORT_JSON="build/preview-verify-report.json"
mkdir -p build

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not available" >&2; exit 1; fi

if [ ! -d "$ASSET_DIR" ] || ! ls "$ASSET_DIR"/* >/dev/null 2>&1; then
  echo "No cached assets found. Run: make fetch-assets" >&2; exit 1; fi

# WebDAV upload base (Nextcloud default)
DAV_BASE="$NC_BASE/remote.php/dav/files/$USER/raw-test"

json_escape() { echo -n "$1" | sed 's/"/\\"/g'; }

UPLOAD_ERRORS=0
PREVIEW_RESULTS=()

# Ensure directory exists
curl -su "$USER:$PASS" -X MKCOL "$DAV_BASE" >/dev/null 2>&1 || true

for f in "$ASSET_DIR"/*; do
  name=$(basename "$f")
  # Upload file (PUT idempotent)
  resp=$(curl -su "$USER:$PASS" -T "$f" -w '%{http_code}' -o /dev/null "$DAV_BASE/$name") || resp=000
  if [ "$resp" -ge 400 ]; then
    echo "Upload failed: $name (HTTP $resp)" >&2
    UPLOAD_ERRORS=$((UPLOAD_ERRORS+1))
    continue
  fi
  # Request preview (100x100) – Nextcloud preview endpoint pattern
  # NOTE: the exact endpoint may vary by NC version; attempt generic /index.php/apps/files/api/v1/preview
  qname=$(python3 - <<PY
import urllib.parse,sys; print(urllib.parse.quote('raw-test/'+sys.argv[1]))
PY "$name")
  preview_url="$NC_BASE/index.php/apps/files/api/v1/preview?file=$qname&x=100&y=100"
  ct=$(curl -su "$USER:$PASS" -I "$preview_url" 2>/dev/null | awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}' | tr -d '\r')
  size=$(curl -su "$USER:$PASS" -s "$preview_url" | wc -c)
  status="ok"
  if [[ ! "$ct" =~ image/jpeg ]] || [ "$size" -lt 200 ]; then
    status="fail"
  fi
  PREVIEW_RESULTS+=("{\"file\":\"$(json_escape "$name")\",\"contentType\":\"$(json_escape "$ct")\",\"bytes\":$size,\"status\":\"$status\"}")
  echo "$name -> $status ($ct, $size bytes)"
Done

done

# Build JSON report
printf '[%s]\n' "$(IFS=,; echo "${PREVIEW_RESULTS[*]}")" > "$REPORT_JSON"

if [ "$UPLOAD_ERRORS" -gt 0 ]; then
  echo "WARN: $UPLOAD_ERRORS upload errors encountered" >&2
fi

FAILS=$(grep -c '"status":"fail"' "$REPORT_JSON" || true)
if [ "$FAILS" -gt 0 ]; then
  echo "Preview verification completed with $FAILS failures. See $REPORT_JSON" >&2
  exit 2
else
  echo "Preview verification successful. Report: $REPORT_JSON"
fi
