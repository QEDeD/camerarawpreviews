#!/usr/bin/env bash
set -euo pipefail
MODE=${1:-docker}
BASE_URL=${BASE_URL:-http://localhost:8080}
APP_ID=camerarawpreviews
if ! command -v curl >/dev/null 2>&1; then echo 'curl required'; exit 1; fi
status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/status.php" || true)
if [ "$status" != "200" ]; then echo "ERROR: status.php HTTP $status"; exit 1; fi
echo "status.php OK"
filesHtml=$(curl -s "$BASE_URL/apps/files/" || true)
if grep -q 'register-viewer.js' <<<"$filesHtml"; then
  echo 'Viewer script reference detected in files app HTML'
else
  echo 'WARNING: Viewer script reference NOT detected (may still load dynamically)'
fi
# Basic OCC check (docker mode only)
if [ "$MODE" = docker ]; then
  if command -v docker >/dev/null 2>&1; then
    CID=$(docker ps --format '{{.ID}} {{.Names}}' | awk '/nc-dev$/ {print $1}') || true
    if [ -n "$CID" ]; then
      docker exec -u www-data "$CID" php occ app:list | grep -q "$APP_ID" && echo 'App enabled (docker)' || echo 'WARNING: App not listed as enabled (docker)'
    fi
  fi
fi
