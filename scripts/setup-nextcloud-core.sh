#!/usr/bin/env bash
set -euo pipefail
VER="${NC_VERSION:-31.0.0}"
NC_DIR="nextcloud"
DATA_DIR="${NC_DATA_DIR:-$NC_DIR/data}"
APP_ID="camerarawpreviews"
if [ ! -d "$NC_DIR" ]; then
  echo "Downloading Nextcloud $VER... (override with NC_VERSION=X.Y.Z)"
  curl -L "https://download.nextcloud.com/server/releases/nextcloud-${VER}.tar.bz2" | tar -xj
fi
if [ ! -L "${NC_DIR}/apps/${APP_ID}" ]; then
  echo "Symlinking app into core: ${NC_DIR}/apps/${APP_ID}";
  ln -s "$(pwd)" "${NC_DIR}/apps/${APP_ID}" || true
fi
CONFIG_FILE="${NC_DIR}/config/config.php"
if [ -f "$CONFIG_FILE" ] && [ ! -s "$CONFIG_FILE" ]; then
  echo "Removing empty stale config.php to allow fresh install";
  rm -f "$CONFIG_FILE";
fi
mkdir -p "$DATA_DIR" || true
touch "$DATA_DIR/.ocdata" || true
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Installing Nextcloud (sqlite) with data dir: $DATA_DIR";
  ABS_DATA_DIR="$(cd "$(dirname "$DATA_DIR")" && pwd)/$(basename "$DATA_DIR")";
  php -d memory_limit=512M "${NC_DIR}/occ" maintenance:install \
    --admin-user=admin --admin-pass=admin \
    --database=sqlite --data-dir="$ABS_DATA_DIR" || { echo 'Install failed'; exit 1; }
else
  echo "Config already present (skipping install)";
fi
php -d memory_limit=512M "${NC_DIR}/occ" app:enable ${APP_ID} || true
cat <<EOF
Nextcloud core ready.
Serve for manual testing:
  php -S 0.0.0.0:8080 -t ${NC_DIR}/
Login: admin / admin
EOF
