#!/bin/bash
set -euo pipefail

echo "=== Minimal post-create start ==="
cd /workspace || { echo "Expected /workspace mount missing"; exit 1; }

# Ensure profile.d is sourced for interactive shells; append to bashrc if missing
if ! grep -q '/workspace/.devcontainer/profile.d' /home/vscode/.bashrc 2>/dev/null; then
    echo 'for f in /workspace/.devcontainer/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done' >> /home/vscode/.bashrc
fi

echo "[1/3] Verifying base environment"
/usr/local/bin/verify-env

echo "[2/3] Installing composer dependencies (if needed)"
if [ -f composer.json ]; then
    if [ ! -d vendor ] || [ ! -f vendor/autoload.php ]; then
        composer install --prefer-dist --no-interaction
    else
        echo "composer vendor already present (skip)"
    fi
else
    echo "No composer.json present (skip)"
fi

echo "[3/3] (Optional steps deferred: exiftool/assets/tests)"
echo "=== Minimal post-create done ==="
