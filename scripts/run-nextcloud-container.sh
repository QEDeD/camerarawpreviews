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
  # Create a dedicated volume to store test assets inside the container only
  if ! "$DOCKER_BIN" volume ls --format '{{.Name}}' | grep -q "^${NAME}-assets$"; then
    "$DOCKER_BIN" volume create ${NAME}-assets >/dev/null
  fi
  "$DOCKER_BIN" run -d --name ${NAME} -p 8080:80 \
    -e NEXTCLOUD_ADMIN_USER=admin -e NEXTCLOUD_ADMIN_PASSWORD=admin \
    -e INSIDE_NC_CONTAINER=1 \
    -v "${APP_PATH}":/var/www/html/custom_apps/${APP_ID} \
    -v "${NAME}-assets":/var/www/html/custom_apps/${APP_ID}/tests/assets/cache \
    ${IMAGE}
  echo "Waiting for Nextcloud to complete initial setup..."
  # Healthcheck: wait up to ~120s for status.php to report installed=true
  ready=0
  for i in $(seq 1 120); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/status.php || true)
    if [ "$code" = "200" ]; then
      if curl -s http://localhost:8080/status.php | grep -q '"installed":true'; then
        ready=1
        break
      fi
    fi
    sleep 1
  done
  if [ "$ready" = "1" ]; then
    echo "Nextcloud is ready."
  else
    echo "WARNING: Nextcloud did not report ready within timeout; continuing anyway."
  fi
  # Pre-bake phpunit9 once inside the container for future runs
  if ! "$DOCKER_BIN" exec ${NAME} bash -lc 'command -v phpunit9 >/dev/null 2>&1'; then
    echo "Installing phpunit9 inside container..."
    "$DOCKER_BIN" exec ${NAME} bash -lc 'curl -Ls https://phar.phpunit.de/phpunit-9.phar -o /usr/local/bin/phpunit9 && chmod +x /usr/local/bin/phpunit9' || true
  fi
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
Assets cache (container volume): ${NAME}-assets mounted at /var/www/html/custom_apps/${APP_ID}/tests/assets/cache
To tail logs: ${DOCKER_BIN} logs -f ${NAME}
Container name: ${NAME}
Image: ${IMAGE}
Override with: NC_NAME=foo NC_IMAGE=nextcloud:31-apache make run-nc-container
EOF
