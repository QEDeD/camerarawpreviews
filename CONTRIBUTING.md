# Contributing to Camera RAW Previews

This project follows a strict local-only workflow: **no GitHub Actions or external CI services**. All validation, testing, packaging, and environment checks MUST be runnable locally (workstation or dev container) using documented Make targets.

## Guiding Principles
1. Reproducible: Every gate = a Make target you can run repeatedly.
2. Observable: Outputs are plain stdout/stderr; no hidden dashboards.
3. Offline-capable: Network only when fetching dependencies or assets explicitly.
4. Minimal coupling: Build scripts avoid assumptions about host OS beyond Docker + basic tooling.
5. Testable abstractions: External tools (exiftool) wrapped so logic is unit testable without spawning processes.

## Key Make Targets
| Purpose | Command |
|---------|---------|
| Build / update dependencies | `make build` |
| Ensure exiftool helper | `make ensure-exiftool-bin` |
| Fast tests (unit/tag logic) | `make test-fast` |
| Standalone tests (w/ dev deps) | `make test-local` |
| Fetch sample RAW assets | `make fetch-assets` |
| Validate asset size / coverage | `make validate-assets` |
| Annotate missing expected tags | `make annotate-tags` |
| Verify previews in running NC | `make verify-assets` |
| Package for App Store | `make appstore` |
| Dev env sanity (CI surrogate) | `make dev-env-verify` |

## Development Environment
Use the provided Dev Container. It supplies:
- PHP (>=8.1) with gd & imagick
- Docker-in-Docker (build static perl helper)
- Composer + project vendor directory

If you prefer host tooling, ensure Docker, PHP 8.1+, and composer are installed.

## Workflow (Typical Change)
1. Edit code.
2. Run `make test-fast` (quick feedback).
3. If touching preview extraction: `make ensure-exiftool-bin` then `make test-local`.
4. If adding/changing assets: `make fetch-assets validate-assets`.
5. Manual functional check (spin up NC via `make run-nc-container`, open RAW file in Viewer).
6. `make appstore` to create distributable bundle.

## Adding New Checks / Tools
- Add a self-descriptive Make target.
- Update README Local-Only section & this file.
- Ensure it fails with non-zero exit code on error and prints clear diagnostics.
- Avoid embedding logic in Git hooks or undocumented scripts.

## Style & Practices
- PHP: PSR-4, PSR LoggerInterface, avoid global state. Defensive try/catch around integration points.
- JS: IIFE, optional chaining, bounded exponential backoff for async availability.
- No direct `error_log`; always use injected logger.
- No silent catch blocks; log warning/error with context.

## Testing Strategy
- Unit tests isolate logic (e.g. tag selection) with dummy runner.
- Integration (optional) requires live NC instance – not enforced automatically.
- Fast subset keeps iteration low-latency.

## Versioning & Releases
1. Bump version in `appinfo/info.xml` when preparing a release.
2. Run full local checklist (see README Minimal Release Checklist).
3. Package via `make appstore`.
4. Inspect tarball contents before distribution.

## Prohibited (By Policy)
- Adding GitHub Actions / external CI workflows
- Introducing required steps not represented as a Make target
- Hardcoding absolute local paths in scripts
- Depending on unlogged, interactive prompts in automation

## Questions
Open an issue describing the desired enhancement and the local command you expect to add. Provide:
- Rationale
- Proposed Make target name
- Exit conditions

Thank you for contributing while keeping the workflow fully self-contained.
