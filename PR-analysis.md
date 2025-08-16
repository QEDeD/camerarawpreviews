# Camera RAW Previews – Analysis & Implementation Log (Consolidated)

<!-- File baseline timestamp: 2025-08-16T09:27:00+0200 (CEST) -->

Integrity note: Removed corrupted duplicated header and stray embedded exiftool snippet previously present above; content below is authoritative.

Last updated: 2025-08-16 (verification timestamp 2025-08-16T18:10:00+0200 CEST)

## 1. Context & Problem Statement  <!-- id:context updated:2025-08-15T00:10:00Z -->
On Nextcloud Hub 10 (31.0.0) RAW files (CR2, NEF, DNG, etc.) were downloaded instead of opening in the Viewer. Hypothesis (confirmed by behavior change after fix): race / timing issue with the Viewer `LoadViewer` event in NC 31 causing our registration script to miss the event.

## 2. Goals / Success Criteria  <!-- id:goals updated:2025-08-15T00:25:00Z -->
✅ RAW files open in Viewer (instead of being shown download dialog)
✅ No duplicate handler registration
✅ Fallback path when event class missing or listener registration fails
✅ Maintain forward compatibility with newer NC versions
✅ Fast local verification (<1 min)
🧪 Streamlined test pipeline (unit + integration) with clean automation against a full Nextcloud instance (container & core checkout) to minimize manual setup.
 📦 Tests cover all formats and format variants we claim to support in docs (asset corpus + assertions kept in sync with documented support).

## 3. Implemented Solution Overview  <!-- id:solution-overview updated:2025-08-15T00:10:00Z -->
PHP (`Application.php`): Event-first script registration using `LoadViewer` if class exists; otherwise immediate fallback. Defensive try/catch + PSR logger.
JS (`register-viewer.js`): IIFE with bounded exponential backoff (100 → 1600 ms) retrying viewer availability; idempotent; emits single error after final attempt.
Preview extraction (`RawPreviewBase`): Stable core; added debug logging around tag selection and extraction; provider registration regex is broadened to include `image/x-dcraw`, `image/x-indesign`, and `application/octet-stream` (hardened). Safety is enforced by the RAW extension whitelist in `isAvailable`.
Build (`Makefile`): Hardened `ensure-exiftool-bin` (Docker/Podman/perl wrapper tiers). Appstore packaging resilient; optional signing respected. Added integration-oriented targets.
Dev Environment (`.devcontainer`): Minimal reproducible PHP image with `gd`, `imagick`, ImageMagick CLI, optional Node via `INSTALL_NODE` build ARG (currently disabled). Post-create verifies environment then installs composer dependencies.

## 4. Key Code Changes (Current State)  <!-- id:key-changes updated:2025-08-15T00:25:00Z -->
- `lib/AppInfo/Application.php`: Event-first registration + broadened provider regex (`^((image/x-dcraw)|(image/x-indesign)|(application/octet-stream))(;+.*)*$`).
- `js/register-viewer.js`: Exponential backoff registration logic.
- `lib/RawPreviewBase.php`: Added detailed debug logs (`isAvailable`, pipeline start, tag selection, extraction, final stats); whitelist-based `isAvailable` with TIFF capability check; accepts `application/octet-stream` for edge RAW types.
- `lib/ExiftoolRunner.php`: Centralized exiftool invocation + orientation copy; static perl wrapper / binary resolution.
- `tests/RawPreviewBaseTagTest.php`: Unit tests for priority tag selection + failure path.
- `tests/integration/PreviewFlowTest.php`: End-to-end preview generation with tag expectation checking (skips problematic TIFF preview edge if needed).
- `tests/integration/DirectProvider3frTest.php`: Direct invocation confirms 3FR extraction succeeds (isolation vs PreviewManager selection issue).
- `tests/integration/Preview3frSelectionTest.php`: Confirms PreviewManager selects our provider for 3FR with the broadened provider regex.
- `tests/integration/PreviewKeyFormatsSelectionTest.php`: Sanity-checks key RAW formats (CR2/NEF/DNG mandatory; ARW/CR3 optional when assets exist).
- `scripts/diagnose-3fr.php`: Ad-hoc diagnostic confirming provider output for 3FR.
- `scripts/list-providers.php`: Reflection-based provider enumeration and availability probe; also attempts a standard preview fetch and reports result and detected MIME.
- `scripts/annotate-tags.sh` / `scripts/validate-assets.sh`: Asset tag annotation & coverage validation (soft warning threshold).
- `scripts/fetch-assets.sh`: Container-only guard by default; pre-hash comparison; HEAD pre-check with validators; streaming downloads to `.tmp`; 60s default timeout; stale file purge and re-fetch; sidecar `.sha1.json` with `{sha1, etag, last_modified, size}` for unknown hashes; skips empty-URL stubs.
- `scripts/validate-assets.sh`: Container-only guard; recognizes sidecar metadata; size caps raised to warn at 2.5 GB and hard fail at 3.0 GB.
- `scripts/run-nextcloud-container.sh`: Mounts named volume `${NC_NAME}-assets` at `tests/assets/cache` so assets live only inside container; exports `INSIDE_NC_CONTAINER=1`; replaces fixed sleep with status.php polling; pre-installs phpunit9 on first run; attempts to install php-imagick/ImageMagick and checks TIFF capability.
- `scripts/scaffold-missing-assets.php`: Generates manifest stubs for all provider-supported but missing formats (includes INDD) to speed up asset curation.
- `Makefile`: Targets for local fast tests (`test-fast`), integration with core (`integration-tests-core`), full harness, packaging, health. Updated `integration-docker` to fetch/validate assets inside container and run a format coverage report; added `coverage-all`, `scaffold-assets`, and `clean-docker-assets`; optional enforcement via `ENFORCE_FULL_COVERAGE=1`.
 - `Makefile`: Targets for local fast tests (`test-fast`), integration with core (`integration-tests-core`), full harness (`integration-full` – includes provider listing + focused 3FR selection test), packaging, environment health (`health-core`).
- `Makefile`: Added `coverage-all`, `scaffold-assets`, container coverage gate (optional via ENFORCE_FULL_COVERAGE=1).
- `.devcontainer/*`: Dockerfile with `BASE_IMAGE` and `INSTALL_NODE` args, environment verification script, simplified post-create steps.
 - `tests/bootstrap.php`: Loads Nextcloud core from local checkout or from `/var/www/html` when running inside the container; uses `call_user_func(['OC_App','loadApp'], ...)` to avoid static analyzer noise.
 - `tests/integration/Preview3frSelectionTest.php`: Removed manual MIME mapping injection; asserts `.3fr` resolves to `image/x-dcraw` under live Nextcloud + app enabled.
 - `tests/MimeRegexTest.php`: Lightweight unit to keep provider regex expectations in check.
 - `tests/assets/manifest.json`: Added scaffolding entries for all remaining formats with `labels:["MISSING_URL"]` to drive FULL coverage completion.

## 5. Build & Packaging Status  <!-- id:build-status updated:2025-08-14T15:35:39Z -->
Command: `make appstore`
Artifact: `build/camerarawpreviews_nextcloud.tar.gz`
`exiftool.bin`: Ensured (static, podman, or perl wrapper fallback). Skippable locally via `SKIP_EXIFTOOL_CHECK=1`.

Linting & checks:
- Required (default `make lint`):
  - PHP syntax (php -l) across tracked PHP files
  - ESLint over `js/`
  - JSON lint for composer/package/manifest
  - PHPCS (composer auto-installed if missing)
- Optional/deep (`make lint-deep`):
  - ShellCheck for shell scripts (via container if available)
  - PHPStan static analysis (installed via composer dev-deps)
  - Auto-fix (optional): `make phpcs-fix` for PHPCBF

## 6. Verification (Local Sanity)  <!-- id:verification updated:2025-08-16T16:05:00Z -->
```bash
php -l lib/AppInfo/Application.php && \
grep -q LoggerInterface lib/AppInfo/Application.php && \
grep -iq exponential js/register-viewer.js && \
test -f build/camerarawpreviews_nextcloud.tar.gz && \
echo "OK" || echo "FAIL"
```

## 6.1 Devcontainer Verification (2025-08-16)  <!-- id:verification-devcontainer updated:2025-08-16T15:10:00Z -->
- Fixed PHP zip runtime by adding `libzip4`; ensured `zip` extension loads (asserted at build and via verify script).
- Disabled CLI Xdebug by default: `ENV XDEBUG_MODE=off` to avoid step-debug connection noise.
- Post-create now marks `/workspace` as a safe Git directory to eliminate "dubious ownership" on Windows volume mounts.
- Adopted volume-backed workspace in `devcontainer.json`; bootstrap clones repo into Docker volume if empty.
- Verified inside container:
  - `verify-env` reports: PHP 8.2 with `gd, zip, imagick` and `convert` present.
  - `composer install` succeeds.
  - `vendor/bin/phpunit -c phpunit.xml.dist` passes: Tests 14, Assertions 47, Skipped 1.

Artifacts: `build/trivy_app.json` (Trivy app-only scan), `.trivyignore` (excludes local Nextcloud fixture).

## 6.2 Asset management & coverage (container-only)  <!-- id:assets-coverage updated:2025-08-16T16:30:00Z -->
- Policy: Test assets live only inside the Nextcloud integration container. A named volume `${NC_NAME}-assets` is mounted at `/var/www/html/custom_apps/camerarawpreviews/tests/assets/cache`.
- Fetch & validate (in-container): `make integration` runs fetch and validate inside the container before tests. Host runs are guarded; set `FORCE_HOST_FETCH=1` only if needed.
- Integrity & efficiency:
  - Pre-hash check for known SHA1s.
  - HEAD pre-check with `If-None-Match` / `If-Modified-Since` for unknown hashes; skip download on `304` or matching validators.
  - Streaming downloads to `.tmp`, 60s default timeout (`DOWNLOAD_TIMEOUT` override).
  - Sidecar `tests/assets/cache/.sha1.json` stores `{sha1, etag, last_modified, size}` for entries with unknown manifest hashes.
  - Stale/mismatched files are auto-removed and re-fetched.
- Size limits:
  - Per-file `size_limit` enforced from `tests/assets/manifest.json`.
  - Global cap: hard < 3.0 GB, warn at 2.5 GB.
- Scaffolding & coverage:
  - Generate stubs for all supported-but-missing formats (includes INDD): `make scaffold-assets` → `build/missing-assets.template.json`.
  - Fill `url` and `sha1` for each stub and merge into `tests/assets/manifest.json`. Stub entries marked with `MISSING_URL` (and `sha1: auto`) are skipped by the fetch step until populated.
  - Check coverage: `make coverage-all` (includes INDD). In container runs, coverage is printed automatically; set `ENFORCE_FULL_COVERAGE=1 make integration` to fail on gaps.
- Reset cache volume: `make clean-docker-assets` to force a clean re-download next run.

### Windows quickstart (host Docker Desktop)
- Open Windows PowerShell in the repo root (not inside the devcontainer).
- Start container: `./scripts/run-nextcloud-container.ps1`
- Smoke test env: `./scripts/integration-smoke.ps1`
- Full integration (optional): `ENFORCE_FULL_COVERAGE=1 make integration-docker` from WSL/devcontainer, or run the above Make target logic manually via `docker exec`.

## 7. Deployment Test Plan (NC 31)  <!-- id:deployment-plan updated:2025-08-16T16:05:00Z -->
1. Extract tarball to `apps` (or `apps-extra`).
2. Enable: `occ app:enable camerarawpreviews`.
3. Upload RAW file; open in Files app.
4. Expect Viewer loads preview. If not:
  - Browser console: look for final backoff failure log.
  - Nextcloud log: determine event vs fallback path (info/debug lines).

Assets policy for integration (container-only):
- The test asset cache is stored in a container volume mounted at `/var/www/html/custom_apps/camerarawpreviews/tests/assets/cache` and does not live on the host.
- `make integration-docker` now fetches and validates assets inside the container and enforces checksum verification; mismatches trigger re-download and removal of stale files.
- Total asset size threshold increased to <3GB to allow testing more formats; warn at 2.5GB.

Format coverage expectations:
- Manifest should contain at least one sample for each provider-supported extension: `indd, 3fr, arw, cr2, cr3, crw, dng, erf, fff, iiq, kdc, mrw, nef, nrw, orf, ori, pef, raf, rw2, rwl, sr2, srf, srw, tif/tiff, x3f`.
- INDD is required (preview via embedded JPEG). Add a small sample and ensure selection via PreviewManager.

## 8. Logging & Diagnostics  <!-- id:logging updated:2025-08-14T15:35:39Z -->
Server logs include: `isAvailable check`, `Preview pipeline start`, `Selected preview tag`, `Extracted preview tag`, `Preview extracted`.
Client script logs only on terminal failure (single error). Additional granular logs intentionally server-side to avoid console noise.

## 9. Current Gap (addressed in container harness): PreviewManager & 3FR  <!-- id:gap-3fr updated:2025-08-16T18:05:00Z -->
Original symptom: PreviewManager skipped 3FR while direct provider path succeeded. Root cause in tests: app not actually installed → mapping not active → `.3fr` resolved to `application/octet-stream`.
Fixes: (1) Broaden provider regex to include `application/octet-stream` (with `image/x-indesign` restored). (2) Mount and enable the app inside a real Nextcloud container so `MimeTypeMapping` is exercised. (3) Remove manual mapping injection in tests and assert `.3fr → image/x-dcraw`.
Safety: `RawPreviewBase::isAvailable` extension whitelist prevents generic octet‑stream processing.
Deployment: In real NC, `.3fr` maps to `image/x-dcraw`; broadened regex is retained as a hardening measure.

## 10. Risks & Mitigations  <!-- id:risks updated:2025-08-16T18:08:00Z -->
| Risk | Status | Mitigation |
|------|--------|------------|
| LoadViewer API change | Low | Fallback direct registration in place |
| Missed edge RAW MIME (octet-stream) | Partially addressed | Regex accepts; extension whitelist limits scope |
| TIFF preview requires Imagick | Mitigated in harness | Container installs php-imagick/ImageMagick and checks TIFF delegate; Makefile preflight enforces when FULL coverage is on |
| 3FR not selected by PreviewManager | Resolved in container tests | App is enabled in a live Nextcloud container; mapping is exercised and asserted |
| Packaging drift (base image updates) | Medium | Documented `BASE_IMAGE` arg; digest pinning deferred |
| INDD asset/test missing | Open | Add INDD sample to manifest and assert selection via PreviewManager |
| Docker not available in devcontainer | Known | Run container-based integration on host (Docker/Podman) or fallback to core checkout flow |

## 11. Future Work (Backlog)  <!-- id:backlog updated:2025-08-16T16:35:00Z -->
- PreviewManager selection tracing (confirm provider registration ordering; maybe add explicit priority if API allows).
- Optional controller endpoint for on-demand fallback preview generation (only if selection gap persists).
- Enhance `list-providers.php` to map internal classes once correct service lookup identified.
- README troubleshooting: add 3FR note & direct test script usage.
- Digest pin base image + document reproducibility procedure.
- Extend asset corpus (medium format RAW variants). Populate manifest with samples for all provider-supported formats (INDD, CRW, ERF, FFF, IIQ, KDC, MRW, NRW, ORF, ORI, PEF, RW2, RWL, SR2, SRF, SRW, X3F) using `make scaffold-assets`, then `ENFORCE_FULL_COVERAGE=1` gate in container runs.
- README troubleshooting: document container-only asset workflow, size caps, sidecar semantics, and `scaffold-assets`/coverage usage.

## 12. Timeline Snapshot  <!-- id:timeline updated:2025-08-16T18:09:00Z -->
2025-08-12: Viewer registration refactor + JS backoff + packaging.
2025-08-13/14: Logging, asset annotation, fast test subset, integration harness, 3FR diagnostics, devcontainer hardening, direct provider test added.
2025-08-16: Container-only asset workflow (volume mount, host guards), fetch optimizations (pre-hash, HEAD validators, streaming, timeout), sidecar enrichment, raised size caps (<3 GB), coverage reporting/enforcement hooks, scaffolding tool, Makefile targets (`coverage-all`, `scaffold-assets`, `clean-docker-assets`).
2025-08-16 (later): Nextcloud container runner uses status.php polling; phpunit9 pre-baked; Imagick/TIFF ensured; integration tests rely on live mapping (manual MIME injection removed). Manifest scaffold extended to all formats with `MISSING_URL` labels.

## 13. Summary Statement  <!-- id:summary updated:2025-08-14T22:12:00Z -->
Robust, race-resistant Viewer registration deployed; preview extraction validated across standard RAWs. 3FR PreviewManager path now succeeds after identifying a test-only MIME mapping omission and broadening the provider regex to include `application/octet-stream`. Broadening is an intentional hardening (guarded by extension whitelist). Remaining work centers on refining the test harness (real app install) and removing temporary manual registration & instrumentation.

## 14. Next Immediate Action (If Resumed)  <!-- id:next-action updated:2025-08-16T18:09:00Z -->
1) Fill URLs and SHA1 for scaffolded formats in `tests/assets/manifest.json` (INDD included).
2) On a host with Docker/Podman: `make run-nc-container` then `ENFORCE_FULL_COVERAGE=1 make integration-docker` (assets fetched/validated in-container).
3) If any format fails preview, add targeted test diagnostics and adjust `expectedTag`/per-file limits as needed. If Docker not available, fallback: `composer install` then `FORCE_HOST_FETCH=1 ENFORCE_FULL_COVERAGE=1 make integration-full`.

## 15. TODO (Tracked Items)  <!-- id:todos created:2025-08-14T15:35:39Z -->
Format: `[TODO][timestamp]` now shown with status icon (Legend: 🟡 open · 🔴 blocked · ✅ done). All entries below are currently open.

### 15.1 Open Items
🟡 [TODO][2025-08-14T15:44:09Z] Optimized full Nextcloud integration test pipeline
- Add dedicated Make target to spin a full Nextcloud container (stable tag) + mount app, run integration tests automatically, and tear down.
- Evaluate using official nextcloud:fpm + ephemeral MariaDB/Redis vs existing script; cache exiftool build between runs.
- Document workflow in README (fast path vs full path) and gate in CI (future optional).
🟡 [TODO][2025-08-14T15:35:39Z] PreviewManager provider selection for 3FR (refined)
- Symlink or copy app into `nextcloud/apps/` during integration tests to activate `MimeTypeMapping` and remove manual provider registration.
- After confirming `.3fr → image/x-dcraw`, decide whether to keep broadened regex (documented hardening) or narrow and add a dedicated octet‑stream fallback test.
- Remove temporary diagnostic instrumentation from patched core copies before release.

🟡 [TODO][2025-08-16T16:35:00Z] Add INDD asset and test
- Add an INDD sample to the manifest and a basic integration assertion that PreviewManager selects our provider.

🟡 [TODO][2025-08-14T15:35:39Z] README troubleshooting update
- Add 3FR note, direct diagnostic script usage (`scripts/diagnose-3fr.php`), and InDesign support status.

🟡 [TODO][2025-08-14T15:35:39Z] Provider enumeration script completion
- Finish `scripts/list-providers.php` to reliably list providers (identify correct service / internal manager class) or remove if infeasible.

🟡 [TODO][2025-08-14T15:35:39Z] Digest pin base image
- Pin `BASE_IMAGE` with sha256 digest; document update workflow.

🟡 [TODO][2025-08-16T16:35:00Z] Asset corpus expansion & hard coverage gate
- Add samples for remaining provider-supported formats; run `ENFORCE_FULL_COVERAGE=1 make integration` in CI/local container runs to enforce.

🟡 [TODO][2025-08-15T00:30:00Z] Keep docs and tests in sync for claimed formats
- Maintain `docs/format-support-checklist.md` alongside README claims.
- Ensure each claimed format has: an asset in `tests/assets/cache`, a manifest entry with `expectedTag` where feasible, and an assertion in `PreviewFlowTest` or a dedicated test.

🟡 [TODO][2025-08-14T15:35:39Z] Optional on-demand preview fallback endpoint
- Only if PreviewManager selection gap persists; controller returning generated JPEG.

🟡 [TODO][2025-08-14T15:35:39Z] Security & supply chain enhancements
- Add composer audit + (optional) container image scan target (local only per policy).

🟡 [TODO][2025-08-14T15:35:39Z] Changelog / version bump
- Prepare release notes summarizing race fix, logging, tests, 3FR known limitation.

🟡 [TODO][2025-08-14T15:35:39Z] Automated local validation bundle
- Single Make target chaining: fetch assets → fast tests → integration subset → packaging sanity.
Decide: pursue PreviewManager provider selection trace vs. document current limitation. Implement whichever chosen, then update this file.

### 15.2 Completed TODOs
✅ [DONE][2025-08-16T16:30:00Z] Container-only asset workflow
- Assets cached in a named container volume; host fetch/validate guarded by default; reset via `make clean-docker-assets`.
✅ [DONE][2025-08-16T16:30:00Z] Fetch/validate hardening
- Pre-hash checks, HEAD validator pre-checks, streaming downloads with timeout, sidecar metadata support; stale file purge and re-fetch; size caps raised to <3 GB.
✅ [DONE][2025-08-16T16:30:00Z] Coverage reporting and scaffolding
- Added `coverage-all`, optional enforcement in `integration-docker` via `ENFORCE_FULL_COVERAGE=1`, and `scaffold-assets` to generate manifest stubs for missing formats (includes INDD).
✅ [DONE][2025-08-16T16:30:00Z] Integration-docker asset flow
- `integration-docker` fetches and validates assets inside the container before running tests and prints coverage.
✅ [DONE][2025-08-16T18:06:00Z] Container runner healthcheck & phpunit pre-bake
- Replaced fixed sleep with status.php polling; installed phpunit9 inside container on first run for faster subsequent runs.
✅ [DONE][2025-08-16T18:06:00Z] Imagick/TIFF readiness in container
- Container script attempts to install php-imagick/ImageMagick and verifies TIFF delegate; Makefile preflight checks/enforces for FULL coverage.
✅ [DONE][2025-08-16T18:07:00Z] Integration tests use live MIME mapping
- Removed manual MIME mapping injection from 3FR selection test; assert `.3fr → image/x-dcraw` under live Nextcloud + app enabled.
✅ [DONE][2025-08-16T18:08:00Z] Manifest scaffolding for all formats
- Added stub entries with `MISSING_URL` labels for all remaining supported formats to drive FULL coverage completion.

Verification note (2025-08-14T15:42:21Z): All sections reconciled against current repository state (Application.php, RawPreviewBase.php, ExiftoolRunner.php, register-viewer.js, integration tests, scripts). No undocumented code paths or drift detected; backlog items accurately reflect remaining gaps. 

---
This consolidated analysis supersedes earlier duplicated blocks; prior verbose / duplicated sections removed for clarity.


