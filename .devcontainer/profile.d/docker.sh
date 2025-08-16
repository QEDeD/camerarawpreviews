#!/usr/bin/env bash
# Prefer host Docker socket (docker-outside-of-docker) if available
if [ -S /var/run/docker.sock ]; then
  export DOCKER_HOST="unix:///var/run/docker.sock"
  export DOCKER_BUILDKIT=1
fi
