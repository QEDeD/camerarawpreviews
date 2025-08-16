# syntax=docker/dockerfile:1
ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/php:1-8.2-bookworm
FROM ${BASE_IMAGE}

ARG INSTALL_NODE="no"

# Install build deps, compile PHP extensions (gd, zip) and install imagick via PECL
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    set -eux; \
    apt-get update; \
    # Note: jq removed (no project scripts depend on it) to reduce vuln surface
    RUNTIME_PACKAGES="git make curl ca-certificates python3 rsync zip unzip tzdata imagemagick sudo libzip4"; \
    BUILD_PACKAGES="build-essential autoconf pkg-config libjpeg62-turbo-dev libpng-dev libwebp-dev libfreetype6-dev libzip-dev libmagickwand-dev"; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $RUNTIME_PACKAGES $BUILD_PACKAGES; \
        if [ "${INSTALL_NODE}" = "yes" ]; then \
            apt-get install -y --no-install-recommends nodejs npm; \
        fi; \
        docker-php-ext-configure gd --with-jpeg --with-freetype --with-webp; \
        docker-php-ext-install -j"$(nproc)" gd zip; \
        pecl install imagick-3.8.0 || pecl install imagick; \
        docker-php-ext-enable imagick; \
    # Remove build-time dependencies to reduce surface area \
    apt-get purge -y --auto-remove $BUILD_PACKAGES; \
    # Upgrade runtime packages to latest security patches within Debian release \
    apt-get update; apt-get -y upgrade; \
                # Drop web server bits we don't need (present in base image variants) \
                apt-get purge -y apache2-utils apache2-bin apache2-data || true; \
                apt-get autoremove -y; \
                # Harden ImageMagick: disable risky coders (MNG/EXR) to mitigate known CVEs \
                policy=/etc/ImageMagick-6/policy.xml; \
                if [ -f "$policy" ] && ! grep -q 'pattern="MNG"' "$policy"; then \
                    sed -i 's#</policymap>#  <policy domain="coder" rights="none" pattern="MNG" />\n</policymap>#' "$policy"; \
                fi; \
                if [ -f "$policy" ] && ! grep -q 'pattern="EXR"' "$policy"; then \
                    sed -i 's#</policymap>#  <policy domain="coder" rights="none" pattern="EXR" />\n</policymap>#' "$policy"; \
                fi; \
        # Verify required PHP extensions and tools are available
    php -r 'extension_loaded("gd") || exit(1);'; \
    php -r 'extension_loaded("zip") || exit(1);'; \
    php -r 'extension_loaded("imagick") || exit(1);'; \
        command -v convert >/dev/null || { echo 'ImageMagick convert missing'; exit 1; }; \
        rm -rf /tmp/pear ~/.pearrc /var/lib/apt/lists/*

# Copy and setup verify-env script
COPY .devcontainer/verify-env.sh /usr/local/bin/verify-env
RUN chmod +x /usr/local/bin/verify-env

# Bootstrap scripts: install inner post-create and robust bootstrap wrapper
COPY .devcontainer/post-create.sh /usr/local/bin/post-create-inner
COPY .devcontainer/bootstrap-workspace.sh /usr/local/bin/bootstrap-workspace
RUN chmod +x /usr/local/bin/post-create-inner /usr/local/bin/bootstrap-workspace

# Verify PHP extensions are installed
RUN php -m | grep -q '^gd$' || { echo 'ERROR: gd extension not loaded'; exit 1; }; \
    php -m | grep -q '^zip$' || { echo 'ERROR: zip extension not loaded'; exit 1; }; \
    php -m | grep -q '^imagick$' || { echo 'ERROR: imagick extension not loaded'; exit 1; }; \
    command -v convert >/dev/null || { echo 'ERROR: ImageMagick convert missing'; exit 1; }

# Setup workspace directory
RUN mkdir -p /workspace

# Disable Xdebug by default for CLI to avoid noisy step-debug attempts
ENV XDEBUG_MODE=off

# Switch to the existing vscode user from base image
USER vscode
WORKDIR /workspace