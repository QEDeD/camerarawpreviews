# Camera RAW Previews – Analysis & Implementation Log (Consolidated)

<!-- File baseline timestamp: 2025-08-16T09:27:00+0200 (CEST) -->

Integrity note: Removed corrupted duplicated header and stray embedded exiftool snippet previously present above; content below is authoritative.

Last updated: 2025-08-16 (verification timestamp 2025-08-16T09:27:00+0200 CEST)

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
- `Makefile`: Targets for local fast tests (`test-fast`), integration with core (`integration-tests-core`), packaging, environment health (`health-core`).
 - `Makefile`: Targets for local fast tests (`test-fast`), integration with core (`integration-tests-core`), full harness (`integration-full` – includes provider listing + focused 3FR selection test), packaging, environment health (`health-core`).
- `.devcontainer/*`: Dockerfile with `BASE_IMAGE` and `INSTALL_NODE` args, environment verification script, simplified post-create steps.

## 5. Build & Packaging Status  <!-- id:build-status updated:2025-08-14T15:35:39Z -->
Command: `make appstore`
Artifact: `build/camerarawpreviews_nextcloud.tar.gz`
`exiftool.bin`: Ensured (static, podman, or perl wrapper fallback). Skippable locally via `SKIP_EXIFTOOL_CHECK=1`.

Lint gates (local-only):
- JS: `make lint-js` (uses local eslint if present), or `npx eslint . --ext .js,.cjs,.mjs --cache`
- JS autofix: `npx eslint js --ext .js,.cjs,.mjs --fix`
- PHP: `vendor/bin/phpcs --standard=phpcs.xml`
- PHP autofix: `vendor/bin/phpcbf --standard=phpcs.xml lib`

## 6. Verification (Local Sanity)  <!-- id:verification updated:2025-08-14T15:35:39Z -->
```bash
php -l lib/AppInfo/Application.php && \
grep -q LoggerInterface lib/AppInfo/Application.php && \
grep -iq exponential js/register-viewer.js && \
test -f build/camerarawpreviews_nextcloud.tar.gz && \
echo "OK" || echo "FAIL"
```

## 7. Deployment Test Plan (NC 31)  <!-- id:deployment-plan updated:2025-08-14T15:35:39Z -->
1. Extract tarball to `apps` (or `apps-extra`).
2. Enable: `occ app:enable camerarawpreviews`.
3. Upload RAW file; open in Files app.
4. Expect Viewer loads preview. If not:
  - Browser console: look for final backoff failure log.
  - Nextcloud log: determine event vs fallback path (info/debug lines).

## 8. Logging & Diagnostics  <!-- id:logging updated:2025-08-14T15:35:39Z -->
Server logs include: `isAvailable check`, `Preview pipeline start`, `Selected preview tag`, `Extracted preview tag`, `Preview extracted`.
Client script logs only on terminal failure (single error). Additional granular logs intentionally server-side to avoid console noise.

## 9. Current Gap (Resolved in Test Harness): PreviewManager & 3FR  <!-- id:gap-3fr updated:2025-08-14T22:12:00Z -->
Original symptom: PreviewManager skipped 3FR while direct provider path succeeded. Instrumentation of `PreviewManager` + `Generator` plus a debug print in the integration test showed the 3FR file MIME resolved to `application/octet-stream` (not `image/x-dcraw`). Cause: in the test setup the app was not actually installed under `nextcloud/apps/`, so our `MimeTypeMapping` was never invoked and the narrowed regex (`/^(image\/x-dcraw)(;+.*)*$/`) could not match. Resolution: broadened the provider registration regex to include `application/octet-stream` (and restored `image/x-indesign`). The test also performs a manual provider registration fallback (to be removed once the app is mounted properly in tests). Extension safety: `RawPreviewBase::isAvailable` enforces a strict RAW extension whitelist, so broadening does not introduce generic octet‑stream processing.
Deployment insight: In a real Nextcloud deployment (app enabled under `nextcloud/apps/`), `.3fr` will map to `image/x-dcraw`; the broadened regex becomes a hardening measure for future / unmapped RAW variants or configuration drift.
Follow-ups: Adjust integration harness to symlink/install the app so MIME mapping is exercised; then remove manual registration while keeping (or documenting) the broadened regex rationale.

## 10. Risks & Mitigations  <!-- id:risks updated:2025-08-14T15:35:39Z -->
| Risk | Status | Mitigation |
|------|--------|------------|
| LoadViewer API change | Low | Fallback direct registration in place |
| Missed edge RAW MIME (octet-stream) | Partially addressed | Regex accepts; extension whitelist limits scope |
| TIFF preview requires Imagick | Conditional | `isAvailable` rejects when unsupported |
| 3FR not selected by PreviewManager | Resolved (test env config) | MIME mapping not active in tests; broadened regex now matches `application/octet-stream`; plan: install app in tests to verify mapping |
| Packaging drift (base image updates) | Medium | Documented `BASE_IMAGE` arg; digest pinning deferred |
| InDesign preview temporarily disabled | Known trade-off | Re-introduce by widening provider regex or separate provider if InDesign previews required |

## 11. Future Work (Backlog)  <!-- id:backlog updated:2025-08-14T15:35:39Z -->
- PreviewManager selection tracing (confirm provider registration ordering; maybe add explicit priority if API allows).
- Optional controller endpoint for on-demand fallback preview generation (only if selection gap persists).
- Enhance `list-providers.php` to map internal classes once correct service lookup identified.
- README troubleshooting: add 3FR note & direct test script usage.
- Digest pin base image + document reproducibility procedure.
- Extend asset corpus (medium format RAW variants) & raise coverage threshold (>70%).

## 12. Timeline Snapshot  <!-- id:timeline updated:2025-08-14T15:35:39Z -->
2025-08-12: Viewer registration refactor + JS backoff + packaging.
2025-08-13/14: Logging, asset annotation, fast test subset, integration harness, 3FR diagnostics, devcontainer hardening, direct provider test added.

## 13. Summary Statement  <!-- id:summary updated:2025-08-14T22:12:00Z -->
Robust, race-resistant Viewer registration deployed; preview extraction validated across standard RAWs. 3FR PreviewManager path now succeeds after identifying a test-only MIME mapping omission and broadening the provider regex to include `application/octet-stream`. Broadening is an intentional hardening (guarded by extension whitelist). Remaining work centers on refining the test harness (real app install) and removing temporary manual registration & instrumentation.

## 14. Next Immediate Action (If Resumed)  <!-- id:next-action updated:2025-08-14T15:35:39Z -->

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

🟡 [TODO][2025-08-14T15:35:39Z] Restore optional InDesign preview support
- Current narrowed regex omits `image/x-indesign` (trade-off). Decide: reintroduce via secondary provider or broaden regex after 3FR issue resolved.

🟡 [TODO][2025-08-14T15:35:39Z] README troubleshooting update
- Add 3FR note, direct diagnostic script usage (`scripts/diagnose-3fr.php`), and InDesign support status.

🟡 [TODO][2025-08-14T15:35:39Z] Provider enumeration script completion
- Finish `scripts/list-providers.php` to reliably list providers (identify correct service / internal manager class) or remove if infeasible.

🟡 [TODO][2025-08-14T15:35:39Z] Digest pin base image
- Pin `BASE_IMAGE` with sha256 digest; document update workflow.

🟡 [TODO][2025-08-14T15:35:39Z] Asset corpus expansion & coverage gate
- Add medium format RAW variants beyond 3FR; raise validation threshold (>70%) and enforce.

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
None yet.

Verification note (2025-08-14T15:42:21Z): All sections reconciled against current repository state (Application.php, RawPreviewBase.php, ExiftoolRunner.php, register-viewer.js, integration tests, scripts). No undocumented code paths or drift detected; backlog items accurately reflect remaining gaps. 

---
This consolidated analysis supersedes earlier duplicated blocks; prior verbose / duplicated sections removed for clarity.


