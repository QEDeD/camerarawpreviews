# This file is licensed under the Affero General Public License version 3 or
# later. See the COPYING file.
# @author Bernhard Posselt <dev@bernhard-posselt.com>
# @copyright Bernhard Posselt 2016

# Generic Makefile for building and packaging a Nextcloud app which uses npm and
# Composer.
#
# Dependencies:
# * make
# * which
# * curl: used if phpunit and composer are not installed to fetch them from the web
# * tar: for building the archive
# * npm: for building and testing everything JS
#
# If no composer.json is in the app root directory, the Composer step
# will be skipped. The same goes for the package.json which can be located in
# the app root or the js/ directory.
#
# The npm command by launches the npm build script:
#
#    npm run build
#
# The npm test command launches the npm test script:
#
#    npm run test
#
# The idea behind this is to be completely testing and build tool agnostic. All
# build tools and additional package managers should be installed locally in
# your project, since this won't pollute people's global namespace.
#
# The following npm scripts in your package.json install and update the bower
# and npm dependencies and use gulp as build system (notice how everything is
# run from the node_modules folder):
#
#    "scripts": {
#        "test": "node node_modules/gulp-cli/bin/gulp.js karma",
#        "prebuild": "npm install && node_modules/bower/bin/bower install && node_modules/bower/bin/bower update",
#        "build": "node node_modules/gulp-cli/bin/gulp.js"
#    },

app_name=$(notdir $(CURDIR))
build_tools_directory=$(CURDIR)/build/tools
vendor_directory=$(CURDIR)/vendor
source_build_directory=$(CURDIR)/build/artifacts/source
source_package_name=$(source_build_directory)/$(app_name)
appstore_build_directory=$(CURDIR)/build/artifacts/appstore
appstore_package_name=$(appstore_build_directory)/$(app_name)
composer=$(shell which composer 2> /dev/null)
DOCKER ?= docker
PHP_OPTIONS ?= -d memory_limit=512M

all: build

# Fetches the PHP and JS dependencies and compiles the JS. If no composer.json
# is present, the composer step is skipped, if no package.json or js/package.json
# is present, the npm step is skipped
.PHONY: build
build:
ifneq (,$(wildcard $(CURDIR)/composer.json))
	make composer
endif
ifneq (,$(wildcard $(CURDIR)/package.json))
	make npm
endif

# Installs and updates the composer dependencies. If composer is not installed
# a copy is fetched from the web
.PHONY: composer
composer:
ifeq (, $(composer))
	@echo "No composer command available, downloading a copy from the web"
	mkdir -p $(build_tools_directory)
	curl -sS https://getcomposer.org/installer | php
	mv composer.phar $(build_tools_directory)
	php $(build_tools_directory)/composer.phar install --prefer-dist
	php $(build_tools_directory)/composer.phar update --prefer-dist
else
	composer install --prefer-dist
	composer update --prefer-dist
endif

# Removes the appstore build
.PHONY: clean
clean:
	rm -rf ./build/artifacts
	rm -rf ./build/camerarawpreviews*tar.gz

# Builds the source and appstore package
.PHONY: dist
dist:
	composer install --prefer-dist
	make tests
	make appstore

# Builds the source package
.PHONY: perl
perl:
	@bash $(build_tools_directory)/perl-build/build.sh || true
	@$(MAKE) ensure-exiftool-bin

# Ensure exiftool.bin exists, building via Docker if available, else a perl wrapper
.PHONY: ensure-exiftool-bin
ensure-exiftool-bin:
	@if [ ! -s $(vendor_directory)/exiftool/exiftool/exiftool.bin ]; then \
		if command -v $(DOCKER) >/dev/null 2>&1; then \
			echo "Building exiftool.bin via $$($(DOCKER) --version | head -1)..."; \
			DOCKER=$(DOCKER) bash $(build_tools_directory)/perl-build/build.sh; \
		elif command -v podman >/dev/null 2>&1; then \
			echo "Docker not found. Using podman to build exiftool.bin..."; \
			DOCKER=podman bash $(build_tools_directory)/perl-build/build.sh; \
		elif command -v perl >/dev/null 2>&1; then \
			echo "Docker not found. Creating a lightweight perl wrapper for exiftool.bin..."; \
			mkdir -p $(vendor_directory)/exiftool/exiftool; \
			printf '%s\n' '#!/usr/bin/env sh' 'DIR=$$(cd -- "$$(dirname "$$0")" >/dev/null 2>&1 && pwd)' 'exec perl "$$DIR/exiftool" "$$@"' > $(vendor_directory)/exiftool/exiftool/exiftool.bin; \
			chmod +x $(vendor_directory)/exiftool/exiftool/exiftool.bin; \
		else \
			echo "Error: neither docker nor perl available to create exiftool.bin" >&2; \
			exit 1; \
		fi; \
	fi

# Builds the source package for the app store, ignores php and js tests
.PHONY: appstore
appstore: ensure-exiftool-bin
	@if [ -z "$$SKIP_EXIFTOOL_CHECK" ]; then \
		test -s $(vendor_directory)/exiftool/exiftool/exiftool.bin; \
	else \
		echo "Warning: Skipping exiftool.bin check"; \
	fi
	rm -rf $(appstore_build_directory)
	mkdir -p $(appstore_build_directory)
	rsync -r ../$(app_name)/ $(appstore_build_directory)/$(app_name) \
		--exclude ".git" \
		--exclude="build" \
		--exclude="tests" \
		--exclude="Makefile" \
		--exclude="*.log" \
		--exclude="phpunit*xml" \
		--exclude="composer.*" \
		--exclude="package.json" \
		--exclude=".*" \
		--exclude="sign-*.sh"
	# Make signing optional - check if certificates exist
	@if [ -f ~/.nextcloud/certificates/camerarawpreviews.key ] && [ -f ~/.nextcloud/certificates/camerarawpreviews.crt ]; then \
		$(DOCKER) run --rm -v $(appstore_build_directory)/$(app_name):/$(app_name) -v ~/.nextcloud/certificates:/certs nextcloud:27-apache php /usr/src/nextcloud/occ integrity:sign-app --path=/$(app_name) --privateKey="/certs/camerarawpreviews.key" --certificate="/certs/camerarawpreviews.crt"; \
	else \
		echo "Warning: Skipping signing - certificates not found"; \
	fi
	mkdir -p build
	tar -czf build/$(app_name)_nextcloud.tar.gz -C "$(appstore_build_directory)" $(app_name)

# Builds the source package for the app store, ignores php and js tests
.PHONY: tests
tests:
	test -s $(vendor_directory)/exiftool/exiftool/exiftool.bin
	# Run tests inside running Nextcloud container (expects run-nc-container executed). Attempts to find or install phpunit.
	CID=$$($(DOCKER) ps --format '{{.ID}} {{.Names}}' | awk '/nc-dev$$/{print $$1}'); \
	if [ -z "$$CID" ]; then echo 'Nextcloud container not running (run make run-nc-container)'; exit 1; fi; \
	if ! $(DOCKER) exec $$CID bash -c 'command -v phpunit9 >/dev/null 2>&1'; then \
		echo 'Installing phpunit9 inside container...'; \
		$(DOCKER) exec $$CID bash -c 'curl -Ls https://phar.phpunit.de/phpunit-9.phar -o /usr/local/bin/phpunit9 && chmod +x /usr/local/bin/phpunit9'; \
	fi; \
	$(DOCKER) exec --workdir /var/www/html/custom_apps/camerarawpreviews --user www-data $$CID phpunit9 --do-not-cache-result --stop-on-failure --bootstrap tests/bootstrap.php tests/

.PHONY: integration-docker
integration-docker: ensure-exiftool-bin run-nc-container
	# Run only integration tests (unit tests already covered by test-fast locally)
	CID=$$($(DOCKER) ps --format '{{.ID}} {{.Names}}' | awk '/nc-dev$$/{print $$1}'); \
	if [ -z "$$CID" ]; then echo 'Nextcloud container not running (run make run-nc-container)'; exit 1; fi; \
	# Preflight: ensure Imagick TIFF support when enforcing full coverage
	if [ -n "$$ENFORCE_FULL_COVERAGE" ] && [ "$$ENFORCE_FULL_COVERAGE" = "1" ]; then \
		if ! $(DOCKER) exec $$CID bash -lc "php -r 'exit((int)!(extension_loaded(\\\"imagick\\\") && count(\\\\Imagick::queryformats(\\\"TIFF\\\"))>0));'"; then \
			echo 'ERROR: Imagick TIFF support not available in container; cannot enforce full coverage.' >&2; exit 1; \
		fi; \
	else \
		$(DOCKER) exec $$CID bash -lc "php -r 'exit((int)!(extension_loaded(\\\"imagick\\\") && count(\\\\Imagick::queryformats(\\\"TIFF\\\"))>0));'" || echo 'WARNING: Imagick TIFF not available; TIFF tests may skip.'; \
	fi; \
	# Fetch and validate assets INSIDE container so they don't live on host
	$(DOCKER) exec --workdir /var/www/html/custom_apps/camerarawpreviews $$CID bash -lc 'chmod +x scripts/fetch-assets.sh scripts/validate-assets.sh && ./scripts/fetch-assets.sh && ./scripts/validate-assets.sh'; \
	# Report format coverage (includes INDD) without failing the build yet
	if [ -n "$$ENFORCE_FULL_COVERAGE" ] && [ "$$ENFORCE_FULL_COVERAGE" = "1" ]; then \
		$(DOCKER) exec --workdir /var/www/html/custom_apps/camerarawpreviews $$CID bash -lc 'php -d memory_limit=256M scripts/check-format-coverage.php FULL=1 INCLUDE_INDD=1'; \
	else \
		$(DOCKER) exec --workdir /var/www/html/custom_apps/camerarawpreviews $$CID bash -lc 'php -d memory_limit=256M scripts/check-format-coverage.php FULL=1 INCLUDE_INDD=1 || true'; \
	fi; \
	if ! $(DOCKER) exec $$CID bash -c 'command -v phpunit9 >/dev/null 2>&1'; then \
		echo 'Installing phpunit9 inside container...'; \
		$(DOCKER) exec $$CID bash -c 'curl -Ls https://phar.phpunit.de/phpunit-9.phar -o /usr/local/bin/phpunit9 && chmod +x /usr/local/bin/phpunit9'; \
	fi; \
	$(DOCKER) exec --workdir /var/www/html/custom_apps/camerarawpreviews --user www-data $$CID phpunit9 --bootstrap tests/bootstrap.php tests/integration || true

.PHONY: integration-smoke-docker
integration-smoke-docker: run-nc-container
	CID=$$($(DOCKER) ps --format '{{.ID}} {{.Names}}' | awk '/nc-dev$$/{print $$1}'); \
	if [ -z "$$CID" ]; then echo 'Nextcloud container not running (run make run-nc-container)'; exit 1; fi; \
	if ! $(DOCKER) exec $$CID bash -c 'command -v phpunit9 >/dev/null 2>&1'; then \
		echo 'Installing phpunit9 inside container...'; \
		$(DOCKER) exec $$CID bash -c 'curl -Ls https://phar.phpunit.de/phpunit-9.phar -o /usr/local/bin/phpunit9 && chmod +x /usr/local/bin/phpunit9'; \
	fi; \
	$(DOCKER) exec --workdir /var/www/html/custom_apps/camerarawpreviews --user www-data $$CID phpunit9 --bootstrap tests/bootstrap.php tests/integration/EnvSanityTest.php

.PHONY: coverage-all
coverage-all:
	php -d memory_limit=256M scripts/check-format-coverage.php FULL=1 INCLUDE_INDD=1

.PHONY: scaffold-assets
scaffold-assets:
	@mkdir -p build; \
	php scripts/scaffold-missing-assets.php > build/missing-assets.template.json; \
	echo "Scaffolded missing format stubs to build/missing-assets.template.json. Fill URLs and sha1, then merge into tests/assets/manifest.json";

.PHONY: clean-docker-assets
clean-docker-assets:
	@NAME=$${NC_NAME:-nc-dev}; \
	if ! $(DOCKER) volume ls --format '{{.Name}}' | grep -q "^$$NAME-assets$$"; then \
		echo "No volume $$NAME-assets to remove."; \
		exit 0; \
	fi; \
	echo "Removing container volume: $$NAME-assets"; \
	$(DOCKER) volume rm $$NAME-assets >/dev/null || true; \
	echo "Done. Next run will recreate and re-download assets inside container."

# Auto-detect best integration flow: prefer Docker/Podman, else fall back to core checkout flow
.PHONY: integration
integration:
	@if [ -n "$$FORCE_CORE" ]; then \
		echo 'FORCE_CORE set; running core integration flow...'; \
		$(MAKE) integration-full; \
	elif [ -n "$$FORCE_DOCKER" ]; then \
		echo 'FORCE_DOCKER set; attempting container flow...'; \
		if command -v $(DOCKER) >/dev/null 2>&1; then \
			$(MAKE) integration-docker; \
		elif command -v podman >/dev/null 2>&1; then \
			echo '$(DOCKER) not found; using podman...'; \
			DOCKER=podman $(MAKE) integration-docker; \
		else \
			echo 'ERROR: No container runtime found (docker/podman).'; exit 1; \
		fi; \
	else \
		if command -v $(DOCKER) >/dev/null 2>&1; then \
			echo 'Detected container runtime ($(DOCKER)); running integration-docker...'; \
			$(MAKE) integration-docker; \
		elif command -v podman >/dev/null 2>&1; then \
			echo 'Detected podman; running integration-docker with DOCKER=podman...'; \
			DOCKER=podman $(MAKE) integration-docker; \
		else \
			echo 'No container runtime found; falling back to core flow (integration-full).'; \
			$(MAKE) integration-full; \
		fi; \
	fi

.PHONY: docker-health
docker-health:
	CID=$$($(DOCKER) ps --format '{{.ID}} {{.Names}}' | awk '/nc-dev$$/{print $$1}'); \
	if [ -z "$$CID" ]; then echo 'Nextcloud container not running'; exit 1; fi; \
	set -e; \
	resp=$$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/status.php || true); \
	if [ "$$resp" != "200" ]; then echo 'ERROR: status.php not returning 200 (got' $$resp')'; exit 1; fi; \
	echo 'status.php OK'; \
	grepScript=$$(curl -s http://localhost:8080/apps/files/ | grep -c 'register-viewer.js' || true); \
	if [ $$grepScript -lt 1 ]; then echo 'WARNING: Viewer script not yet detected in files app HTML'; else echo 'Viewer script reference detected.'; fi

.PHONY: health-core
health-core:
	@if [ ! -d nextcloud ]; then echo 'Nextcloud core not set up (run make setup-core)'; exit 1; fi
	BASE_URL=http://localhost:8080 bash scripts/health-check.sh core || true

.PHONY: integration-core-all
integration-core-all: ensure-exiftool-bin fetch-assets setup-core
	@if ! pgrep -f "php -S 0.0.0.0:8080 -t nextcloud/" >/dev/null 2>&1; then \
		echo 'Starting built-in PHP server for core (background)...'; \
		( php $(PHP_OPTIONS) -S 0.0.0.0:8080 -t nextcloud/ >/dev/null 2>&1 & echo $$! > .php_server_pid ); \
		sleep 5; \
	fi
	@if [ ! -x vendor/bin/phpunit ]; then composer install --prefer-dist; fi
	php $(PHP_OPTIONS) vendor/bin/phpunit --bootstrap tests/bootstrap.php tests/integration || true
	$(MAKE) health-core || true

.PHONY: stop-core-server
stop-core-server:
	@if [ -f .php_server_pid ]; then kill $$(cat .php_server_pid) || true; rm .php_server_pid; echo 'Stopped core PHP server.'; else echo 'No core server pid file.'; fi

.PHONY: integration-tests-core
integration-tests-core: ensure-exiftool-bin
	@if [ ! -d nextcloud ]; then echo 'Nextcloud core not set up. Run: make setup-core'; exit 1; fi
	@if [ ! -x vendor/bin/phpunit ]; then composer install --prefer-dist; fi
	# Execute integration subset requiring core (skips unit-only tests automatically if core classes missing)
	php -d memory_limit=512M vendor/bin/phpunit --bootstrap tests/bootstrap.php tests/integration || true

# Full integration harness: provider listing + focused 3FR selection test + general integration tests
.PHONY: integration-full
integration-full: ensure-exiftool-bin fetch-assets setup-core
	@if [ ! -x vendor/bin/phpunit ]; then composer install --prefer-dist; fi
	@echo "[integration-full] Listing providers for 3FR..."; \
	php -d memory_limit=512M scripts/list-providers.php > build/providers_3fr.json 2> build/providers_3fr.log || true; \
	if [ -s build/providers_3fr.json ]; then echo "Provider listing written to build/providers_3fr.json"; else echo "WARNING: provider listing JSON missing"; fi
	@echo "[integration-full] Running focused 3FR selection test (expected failing until fixed)..."; \
	php -d memory_limit=512M vendor/bin/phpunit --bootstrap tests/bootstrap.php tests/integration/Preview3frSelectionTest.php || true
	@echo "[integration-full] Running remaining integration tests..."; \
	php -d memory_limit=512M vendor/bin/phpunit --bootstrap tests/bootstrap.php tests/integration/PreviewFlowTest.php || true
	@echo "[integration-full] Summary:"; \
	grep -E 'FAILURES|OK|WARNING' build/providers_3fr.log || true; \
	(if grep -q 'preview_generated"\s*:\s*"yes"' build/providers_3fr.json 2>/dev/null; then echo 'Provider listing: preview_generated=yes'; else echo 'Provider listing: preview_generated!=yes'; fi)

.PHONY: test-local
test-local: ensure-exiftool-bin
	@if [ ! -x vendor/bin/phpunit ]; then echo 'Installing dev dependencies (phpunit)...'; composer install --prefer-dist; fi
	@if [ -n "$$CRP_STANDALONE_SKIP" ]; then echo 'Skipping integration tests (standalone)'; exit 0; fi
	vendor/bin/phpunit || true

.PHONY: setup-core
setup-core:
	chmod +x scripts/setup-nextcloud-core.sh; ./scripts/setup-nextcloud-core.sh

.PHONY: run-nc-container
run-nc-container:
	chmod +x scripts/run-nextcloud-container.sh; ./scripts/run-nextcloud-container.sh

.PHONY: fetch-assets
fetch-assets:
	chmod +x scripts/fetch-assets.sh; ./scripts/fetch-assets.sh

.PHONY: verify-assets
verify-assets: fetch-assets
	chmod +x scripts/verify-previews.sh; ./scripts/verify-previews.sh

.PHONY: validate-assets
validate-assets: fetch-assets
	chmod +x scripts/validate-assets.sh; ./scripts/validate-assets.sh

.PHONY: coverage-key
coverage-key:
	php -d memory_limit=256M scripts/check-format-coverage.php KEY_FORMATS=cr2,cr3,nef,arw,dng

.PHONY: coverage-full
coverage-full:
	php -d memory_limit=256M scripts/check-format-coverage.php FULL=1

.PHONY: annotate-tags
annotate-tags: fetch-assets ensure-exiftool-bin
	chmod +x scripts/annotate-tags.sh; ./scripts/annotate-tags.sh

.PHONY: test-fast
test-fast: ensure-exiftool-bin fetch-assets
	@echo "Selecting fast subset..."; \
	python3 scripts/select-fast-subset.py; \
	if [ ! -x vendor/bin/phpunit ]; then echo 'Installing dev dependencies (phpunit)...'; composer install --prefer-dist; fi; \
	echo "Running fast subset tests (unit + manifest tag checks only)"; \
	CRP_STANDALONE_SKIP=1 vendor/bin/phpunit --bootstrap tests/bootstrap.php tests/RawPreviewBaseTagTest.php || true; \
	echo "(Optional) To run integration preview tests on subset manually, copy listed files into a Nextcloud test instance."

# Iterative per-format integration run: fetch a format, run key integration tests, then clean cache and continue.
.PHONY: integration-iterate
integration-iterate: ensure-exiftool-bin setup-core
	@fmts=$${FORMATS:-"cr2 nef dng arw cr3"}; \
	for f in $$fmts; do \
		echo "=== Format: $$f (fetch) ==="; \
		FORMATS=$$f $(MAKE) fetch-assets; \
		echo "=== Format: $$f (test) ==="; \
		php -d memory_limit=512M vendor/bin/phpunit --bootstrap tests/bootstrap.php tests/integration/PreviewKeyFormatsSelectionTest.php || true; \
		echo "=== Format: $$f (clean) ==="; \
		bash scripts/clean-assets.sh tests/assets/cache $$f; \
	done

# Build devcontainer image locally and run verify-env (offline replacement for removed GitHub Actions workflow)
.PHONY: dev-env-verify
dev-env-verify:
	@set -e; \
	RUNTIME=$$(command -v $${DOCKER:-docker} >/dev/null 2>&1 && echo $${DOCKER:-docker} || (command -v podman >/dev/null 2>&1 && echo podman || echo none)); \
	if [ "$$RUNTIME" = none ]; then echo 'No container runtime (docker/podman) found on host.'; exit 1; fi; \
	echo "Building devcontainer image with $$RUNTIME (INSTALL_NODE=no) ..."; \
	"$$RUNTIME" build --build-arg INSTALL_NODE=no -f .devcontainer/Dockerfile -t camerarawpreviews-dev-local .; \
	echo "Running verify-env inside container..."; \
	"$$RUNTIME" run --rm camerarawpreviews-dev-local verify-env; \
	echo "Extracting vendor hash (if present)..."; \
	CID=$$("$$RUNTIME" create camerarawpreviews-dev-local bash -lc 'test -f /workspace/.vendor-built-from && cat /workspace/.vendor-built-from || true'); \
	"$$RUNTIME" cp $$CID:/workspace/.vendor-built-from .vendor-built-from.image 2>/dev/null || true; \
	"$$RUNTIME" rm $$CID >/dev/null || true; \
	if [ -f .vendor-built-from.image ]; then echo "Image vendor hash:"; cat .vendor-built-from.image; fi; \
	echo "dev-env-verify completed.";

.PHONY: install-hooks
install-hooks:
	chmod +x scripts/install-git-hooks.sh; ./scripts/install-git-hooks.sh

.PHONY: lint lint-php lint-js lint-json phpcs
lint: lint-php lint-js lint-json phpcs
	@echo "Lint complete."

lint-php:
	@echo "PHP syntax check (php -l) for tracked files..."; \
	rc=0; \
	for f in $$(git ls-files "*.php"); do php -l "$$f" >/dev/null || rc=1; done; \
	[ $$rc -eq 0 ] || (echo "PHP syntax errors detected" >&2); \
	exit $$rc

lint-js:
	@echo "JS lint (eslint) if available..."; \
	ESLINT_BIN=$$( [ -x node_modules/.bin/eslint ] && echo node_modules/.bin/eslint || command -v eslint || true ); \
	if [ -n "$$ESLINT_BIN" ]; then \
		"$$ESLINT_BIN" js/ --ext .js --no-error-on-unmatched-pattern || true; \
	else \
		echo "eslint not found; skipping JS lint"; \
	fi

.PHONY: lint-json
lint-json:
	@echo "Validating JSON files..."; \
	set -e; FILES=""; \
	for f in composer.json package.json package-lock.json tests/assets/manifest.json; do \
		[ -f "$$f" ] && FILES="$$FILES $$f"; \
	done; \
	php scripts/lint-json.php $$FILES

.PHONY: phpcs phpcs-fix
phpcs:
	@echo "Running PHP_CodeSniffer (phpcs)..."; \
	if [ ! -x vendor/bin/phpcs ]; then composer install --prefer-dist; fi; \
	vendor/bin/phpcs --standard=phpcs.xml

phpcs-fix:
	@echo "Running phpcbf (auto-fix where possible)..."; \
	if [ ! -x vendor/bin/phpcbf ]; then composer install --prefer-dist; fi; \
	vendor/bin/phpcbf --standard=phpcs.xml || true

.PHONY: lint-sh
lint-sh:
	@echo "ShellCheck for bash scripts (via container if available)..."; \
	if command -v $(DOCKER) >/dev/null 2>&1; then \
		$(DOCKER) run --rm -v $(CURDIR):/work koalaman/shellcheck:stable sh -c 'shopt -s globstar nullglob; shellcheck -x /work/scripts/**/*.sh' || true; \
	else \
		if command -v shellcheck >/dev/null 2>&1; then shellcheck -x scripts/*.sh || true; else echo "No docker or shellcheck; skipping"; fi; \
	fi

.PHONY: phpstan
phpstan:
	@echo "Running PHPStan (static analysis) if available..."; \
	if [ ! -x vendor/bin/phpstan ]; then \
		if command -v composer >/dev/null 2>&1; then composer install --prefer-dist; else echo "composer not found; skipping phpstan"; exit 0; fi; \
	fi; \
	vendor/bin/phpstan analyse --memory-limit=512M -c phpstan.neon.dist || true

.PHONY: lint-deep
lint-deep: lint lint-json lint-sh phpstan
	@echo "Deep lint completed."

.PHONY: lint-all
lint-all: lint


# Security audit focused on app-level dependencies only (skip local Nextcloud fixture)
.PHONY: audit audit-app
audit: audit-app

audit-app:
	@echo "[audit] Composer audit (prod deps only)..."; \
	if command -v composer >/dev/null 2>&1; then \
		composer audit --no-interaction || true; \
	else \
		echo "composer not found; using containerized composer:2"; \
		$(DOCKER) run --rm -v $(CURDIR):/app -w /app composer:2 composer audit --no-interaction || true; \
	fi
	@echo "[audit] Trivy FS scan (HIGH/CRITICAL, --scanners vuln, excluding ./nextcloud)..."; \
	mkdir -p build; \
	$(DOCKER) run --rm -v $(CURDIR):/work aquasec/trivy:0.53.0 fs --severity HIGH,CRITICAL --scanners vuln --ignore-unfixed --no-progress --skip-dirs /work/nextcloud --format json -o /work/build/trivy_app.json /work || true; \
	echo "[audit] Trivy JSON report: build/trivy_app.json"
