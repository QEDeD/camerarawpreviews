#!/usr/bin/env bash
set -euo pipefail
# /usr/local/bin/bootstrap-workspace

WORKDIR="/workspace"
DEVUSER="vscode"
DEVGROUP="vscode"
MARKER=".workspace_initialized"

# Helpers
is_dir_present() { [ -d "$WORKDIR" ]; }
is_empty() {
  is_dir_present || return 1
  # shellcheck disable=SC2012
  [ -z "$(ls -A "$WORKDIR" 2>/dev/null)" ]
}

# Ensure workspace directory exists
if ! is_dir_present; then
  if [ "$(id -u)" -eq 0 ]; then
    mkdir -p "$WORKDIR"
    chown "$DEVUSER:$DEVGROUP" "$WORKDIR" || true
  else
    mkdir -p "$WORKDIR"
  fi
fi

cd "$WORKDIR"

# Skip heavy ops if previously initialized
if [ -e "$WORKDIR/$MARKER" ]; then
  echo "Workspace already initialized (marker present)."
else
  if is_empty; then
    echo "Workspace empty: performing first-run ownership and optional clone."
    if [ "$(id -u)" -eq 0 ]; then
      chown -R "$DEVUSER:$DEVGROUP" "$WORKDIR" || true
    else
      if command -v sudo >/dev/null 2>&1; then
        sudo chown -R "$DEVUSER:$DEVGROUP" "$WORKDIR" || true
      else
        echo "Warning: cannot chown $WORKDIR (no sudo, not root). Continuing."
      fi
    fi

    if [ -n "${GIT_REMOTE_URL:-}" ]; then
      echo "Cloning ${GIT_REMOTE_URL} (branch: ${CLONE_BRANCH:-master}) into $WORKDIR"
      if [ "$(id -u)" -eq 0 ]; then
        su -s /bin/bash -c "git clone --branch \"${CLONE_BRANCH:-master}\" --depth 1 \"${GIT_REMOTE_URL}\" \"$WORKDIR\"" "$DEVUSER" || true
      else
        git clone --branch "${CLONE_BRANCH:-master}" --depth 1 "${GIT_REMOTE_URL}" "$WORKDIR" || true
      fi
    fi

    # Create marker
    if [ "$(id -u)" -eq 0 ]; then
      touch "$WORKDIR/$MARKER"
      chown "$DEVUSER:$DEVGROUP" "$WORKDIR/$MARKER" || true
    else
      touch "$WORKDIR/$MARKER" || true
    fi
  else
    echo "Workspace not empty; skipping first-run chown/clone."
    touch "$WORKDIR/$MARKER" || true
  fi
fi

# Run verify and post-create steps as dev user
if [ "$(id -u)" -eq 0 ]; then
  echo "Running verify/post-create as $DEVUSER"
  su -s /bin/bash -c "/usr/local/bin/verify-env || true" "$DEVUSER"
  if [ -x /usr/local/bin/post-create-inner ]; then
    su -s /bin/bash -c "/usr/local/bin/post-create-inner || true" "$DEVUSER"
  fi
else
  /usr/local/bin/verify-env || true
  [ -x /usr/local/bin/post-create-inner ] && /usr/local/bin/post-create-inner || true
fi

echo "bootstrap-workspace complete."
