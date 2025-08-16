# syntax=docker/dockerfile:1
ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/php:1-8.2-bookworm
FROM ${BASE_IMAGE}

ARG INSTALL_NODE="no"

# Install system dependencies & PHP extensions via Debian packages (works with devcontainers/php base)
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    set -eux; \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            git make curl ca-certificates \
            python3 rsync zip unzip tzdata jq \
            imagemagick \
            php-gd php-imagick php-zip; \
        if [ "${INSTALL_NODE}" = "yes" ]; then \
            apt-get install -y --no-install-recommends nodejs npm; \
        fi; \
        # Verify required PHP extensions and tools are available
        php -r 'extension_loaded("gd") || exit(1);'; \
        php -r 'extension_loaded("imagick") || exit(1);'; \
        command -v convert >/dev/null || { echo 'ImageMagick convert missing'; exit 1; }; \
        rm -rf /var/lib/apt/lists/*

# Copy and setup verify-env script
COPY .devcontainer/verify-env.sh /usr/local/bin/verify-env
RUN chmod +x /usr/local/bin/verify-env

# Verify PHP extensions are installed
RUN php -m | grep -q '^gd$' || { echo 'ERROR: gd extension not loaded'; exit 1; }; \
    php -m | grep -q '^imagick$' || { echo 'ERROR: imagick extension not loaded'; exit 1; }; \
    command -v convert >/dev/null || { echo 'ERROR: ImageMagick convert missing'; exit 1; }

# Setup workspace directory
RUN mkdir -p /workspace

# Switch to the existing vscode user from base image
USER vscode
WORKDIR /workspace