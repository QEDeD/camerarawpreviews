# Camera RAW Previews
[![Github All Releases](https://img.shields.io/github/downloads/ariselseng/camerarawpreviews/total.svg)](https://github.com/ariselseng/camerarawpreviews/releases) [![paypal](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.me/AriSelseng/2EUR)

A Nextcloud app that extracts embedded previews for camera **RAW** images like .CR2, .CRW, .DNG, .MRW, .NEF, .NRW, .RW2, .SRW, .SRW, etc.

This app also gives you preview of Adobe **Indesign** files (.INDD) photos.


## Requirements
* Probably **memory_limit** quite high.
* **imagick** or **gd** module. If imagick is available, it will use that for performance.
* For files with a TIFF preview (at least some DNG files), **imagick** is required

## Installation
Install in Nextcloud App store.
https://apps.nextcloud.com/apps/camerarawpreviews

Install in ownCloud Marketplace (older version that is not supported anymore, due to too much difference between owncloud and nextcloud now)
https://marketplace.owncloud.com/apps/camerarawpreviews

## Building locally
- Run "make"
- Place this app in **./apps/**

## Local-Only Policy (No Remote CI Services)
This project intentionally does NOT use GitHub Actions (or any external CI service). All quality gates, packaging steps, and verification are designed to run entirely on a developer workstation or within the provided Dev Container. Rationale:
* Reduce external dependencies (works offline / air‑gapped).
* Keep build logic transparent (Makefile + scripts) and reproducible.
* Avoid divergence between “CI environment” and real local usage.

Authoritative principle: If a check matters, it must be runnable with a single local command documented below. If something cannot be verified locally, we treat it as unverifiable and redesign.

### Core Local Quality Gates
| Goal | Command | Notes |
|------|---------|-------|
| Ensure exiftool helper present | `make ensure-exiftool-bin` | Builds static perl helper or wrapper |
| Fast logical tests (tag selection) | `make test-fast` | Skips integration; uses dummy runner |
| Full (standalone subset) tests | `make test-local` | Installs dev deps if missing |
| Fetch RAW sample assets | `make fetch-assets` | Idempotent; cached under `tests/assets` |
| Validate asset sizes & coverage | `make validate-assets` | Warns if coverage low / size cap exceeded |
| Annotate missing expected tags | `make annotate-tags` | Updates manifest (review diff) |
| Verify previews in a running NC | `make verify-assets` | Requires instance (see workflows A/B) |
| Package for App Store | `make appstore` | Produces `build/camerarawpreviews_nextcloud.tar.gz` |
| Dev environment smoke (offline CI surrogate) | `make dev-env-verify` | Builds dev image & runs `verify-env` |

### Minimal Release Checklist (Local)
1. `make ensure-exiftool-bin`
2. `make test-fast` (green)
3. `make fetch-assets validate-assets` (no hard errors)
4. (Optional deeper) `make test-local`
5. Spin up NC (method A or B below) and manual open a RAW file → Viewer loads
6. `make appstore`
7. Inspect `build/camerarawpreviews_nextcloud.tar.gz` size & contents

### Dev Container Usage
Open repository in supported editor (e.g. VS Code) and let the Dev Container build. All prerequisites (php, gd/imagick, docker-in-docker) are provisioned. Quality gate commands above are identical inside the container.

### Adding New Checks
When proposing a new quality gate, add a Make target and document it here. Do not rely on hidden scripts or external service configuration.

## Building the exiftool helper (exiftool.bin)
You have three options:
- Docker (default): Builds a static Perl runtime inside a container
  - Use Docker (default): `make perl`
  - Or Podman: `DOCKER=podman make perl`
- Wrapper fallback (no containers): A lightweight shell wrapper calling system Perl
  - Automatically used when Docker/Podman are not available
- Skip strict check (for local packaging only): `SKIP_EXIFTOOL_CHECK=1 make appstore`

Signing uses Docker by default. To use Podman:
```
DOCKER=podman make appstore
```

## Information about the perl binary
- To avoid lots of issues and problems for users I am bundling a static build of perl for x86_64
- The binary is built using an isolated docker container with this: http://software.schmorp.de/pkg/App-Staticperl.html

## Troubleshooting
- If you get no preview, make sure your raw files has an embedded preview. If it looks like this, it does not have an embedded preview:
 ```shell
$ exiftool -json -preview:all rawfile.dng
 [{
  "SourceFile": "rawfile.dng"
}]
```

## Integration & Validation (Local / Dev Container Only)

Two supported workflows:

### A. Clone Nextcloud Core Inside Dev Container
1. Run: `make setup-core`
2. Serve: `php -S 0.0.0.0:8080 -t nextcloud/`
3. Visit http://localhost:8080 (admin / admin)
4. The app is symlinked into `nextcloud/apps/camerarawpreviews`.

Core Integration Automation:
- All-in-one (setup + server + integration tests + health): `make integration-core-all`
- Stop built-in server: `make stop-core-server`
Override version: `NC_VERSION=31.0.7 make setup-core`
Memory limit: Integration targets run with PHP memory_limit=512M (override via `PHP_OPTIONS='-d memory_limit=768M' make integration-core-all`).

Run local phpunit (standalone limited): `make test-local`
Note: Full integration tests require Nextcloud's own phpunit deps (the release tarball may lack them; use a git clone if needed).

### B. Run Official Nextcloud Container (Docker-in-Docker)
1. Ensure devcontainer has docker feature (already configured).
2. Run: `make run-nc-container`
3. Visit http://localhost:8080 (admin / admin)
4. App mounted at `/var/www/html/custom_apps/camerarawpreviews` inside container.

#### Docker Integration Tests
- Full test suite inside container (all tests): `make tests`
- Integration-only tests: `make integration-docker`
- Health + script detection: `make docker-health`
Environment overrides:
```bash
NC_NAME=nc-dev-alt NC_IMAGE=nextcloud:31-apache make run-nc-container
```
The test target will install a local phpunit9 PHAR inside the container if missing.

Health Checks:
- Core mode: `make health-core` (requires running PHP -S server)
- Docker mode: `make docker-health`

To rebuild exiftool helper (if needed): `make ensure-exiftool-bin`

### Choosing a Workflow
- Auto-detect: `make integration` (prefers Docker/Podman; falls back to core flow automatically)
- Force core flow: `FORCE_CORE=1 make integration`
- Force container flow: `FORCE_DOCKER=1 make integration`

Guidance:
- Use Core (A) for deep integration debugging with the core test harness.
- Use Container (B) for fast manual UI/Viewer checks.

### Test Assets & Validation
Commands (all local, no GitHub Actions required):
1. Fetch RAW assets:
  make fetch-assets
2. Validate size / checksum / (partial) tag coverage (<400MB hard limit):
  make validate-assets
3. Auto-annotate missing expectedTag entries (non-destructive; review diff before committing):
  make annotate-tags
4. Run unit/integration tests (standalone phpunit subset):
  make test-local
5. (Optional) Run preview verification script against a running Nextcloud instance:
  make verify-assets

Asset governance: Hard cap 400MB enforced by validate script. If exceeded, remove or replace largest files before proceeding.

Fast iteration: `make test-fast` executes a limited representative subset (unit + tag logic). Use `make test-local` for broader coverage. If your devcontainer lacks Docker-in-Docker, `make integration` will transparently run the core flow instead.

## Key Supported Formats
- Canon: CR2, CR3 (and CRW)
- Nikon: NEF (and NRW)
- Sony: ARW (and SR2/SRF/SRW)
- Adobe: DNG
- Plus many others: 3FR, RAF, RW2, ORF, PEF, IIQ, FFF, MRW, KDC, X3F, RWL, ORI, TIFF

See “Supported Formats vs Tests” above and `docs/format-support-checklist.md` for coverage status (assets and tests).

No Remote CI dependency: All quality gates are intentionally local; do not add GitHub Actions workflows. Any future automation must still be reproducible via a single documented local Make target.

### Supported Formats vs Tests
See `docs/format-support-checklist.md` for a living checklist mapping claimed support to test assets and coverage.

### Pre-commit Hook (Local)
Install local git hooks to prevent accidental large/binary asset commits and to run a quick PHP syntax check:

```bash
scripts/install-git-hooks.sh
```

This sets `core.hooksPath` to `.githooks` and enables a pre-commit that:
- Blocks files in `tests/assets/cache/` (except `.gitkeep`)
- Blocks provider diagnostic outputs in `build/providers_*.{json,log}`
- Fails on staged files >10MB
- Runs `php -l` on staged PHP files
