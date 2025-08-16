#!/usr/bin/env bash
# Auto-detect TZ inside container if not provided via env.
if [ -z "${TZ:-}" ]; then
  if [ -r /etc/timezone ]; then
    export TZ="$(cat /etc/timezone 2>/dev/null | tr -d '\r' | xargs)"
  elif [ -L /etc/localtime ]; then
    zone=$(readlink -f /etc/localtime | sed -n 's#^/usr/share/zoneinfo/##p')
    [ -n "$zone" ] && export TZ="$zone"
  fi
fi
