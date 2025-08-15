#!/usr/bin/env bash
set -euo pipefail
CACHE_DIR="${1:-tests/assets/cache}"
if [ ! -d "$CACHE_DIR" ]; then exit 0; fi
shift || true
if [ $# -eq 0 ]; then
  echo "Removing all cached assets in $CACHE_DIR"; rm -f "$CACHE_DIR"/*; exit 0;
fi
formats=$(echo "$*" | tr ' ' '\n')
for fmt in $formats; do
  fmt_lc=$(echo "$fmt" | tr '[:upper:]' '[:lower:]')
  find "$CACHE_DIR" -maxdepth 1 -type f -iname "*.${fmt_lc}" -print -delete || true
done
exit 0
