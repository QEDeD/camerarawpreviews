#!/usr/bin/env bash
set -euo pipefail
NAME="${NC_NAME:-nc-dev}"
IMAGE="${NC_IMAGE:-nextcloud:31-apache}"
DOCKER_BIN="${DOCKER:-docker}"
APP_ID="camerarawpreviews"
APP_PATH="$(pwd)"
if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  if command -v podman >/dev/null 2>&1; then
    DOCKER_BIN=podman
  else
    echo "No container runtime available (docker/podman)." >&2
    exit 1
  fi
fi
if ! "$DOCKER_BIN" ps -a --format '{{.Names}}' | grep -q "^${NAME}$"; then
  echo "Starting new Nextcloud container ${NAME}..."
  "$DOCKER_BIN" run -d --name ${NAME} -p 8080:80 \
    -e NEXTCLOUD_ADMIN_USER=admin -e NEXTCLOUD_ADMIN_PASSWORD=admin \
    -v "${APP_PATH}":/var/www/html/custom_apps/${APP_ID} \
    ${IMAGE}
  echo "Waiting for initial setup (approx 25s)..."; sleep 25
  "$DOCKER_BIN" exec -u www-data ${NAME} php occ app:enable ${APP_ID} || true
else
  echo "Container ${NAME} already exists. Starting..."
  "$DOCKER_BIN" start ${NAME} >/dev/null
fi
echo "Ensuring app enabled..."
"$DOCKER_BIN" exec -u www-data ${NAME} php occ app:enable ${APP_ID} >/dev/null 2>&1 || true
cat <<EOF
Nextcloud container running at: http://localhost:8080
Admin login: admin / admin
Mounted app path: /var/www/html/custom_apps/${APP_ID}
To tail logs: ${DOCKER_BIN} logs -f ${NAME}
Container name: ${NAME}
Image: ${IMAGE}
Override with: NC_NAME=foo NC_IMAGE=nextcloud:31-apache make run-nc-container
EOF
