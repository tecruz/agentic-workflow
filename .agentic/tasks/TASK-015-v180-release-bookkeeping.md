# TASK-015 — v1.8.0 release bookkeeping: deeper Android/Kotlin detection

## Objective

Complete the v1.8.0 release bookkeeping for the deeper Android/Kotlin detection
merged in PR #17 (commit `bf8ea1f`). The code landed but versioning, CHANGELOG,
ADR, and protocol_version sweep were deferred.

## Acceptance criteria

- [x] ROADMAP.md item 2 checkboxes checked, version updated to 1.8.0
- [x] ADR-0013 written and indexed in `docs/decisions/README.md`
- [ ] `.agentic/VERSION` bumped to `1.8.0`
- [ ] `protocol_version` sweep to `1.8.0` across all schemas, scripts, evals, tests
- [ ] CHANGELOG.md `[1.8.0]` section added
- [ ] Task file created (this file)
- [ ] `.agentic/STATUS.md` updated with v1.8.0 note
- [ ] Tag `v1.8.0` created and Release workflow passes

## Context

PR #17 (`feat/android-kotlin-detection`) merged at `bf8ea1f` but versioning
was deferred. The detection contract changed (root-level version catalog +
convention plugin; per-module split without version catalog), which per
ADR-0007 requires a protocol_version bump and VERSION bump.

## Verification

- All 51/51 fixtures pass (Bash + PowerShell)
- 8/8 offline evals pass (both languages)
- CI green on Linux, macOS, Windows
- Cross-language parity maintained

## Files to update

- `.agentic/VERSION` → `1.8.0`
- `protocol_version` sweep: schemas, scripts, evals, tests (done)
- `CHANGELOG.md` `[1.8.0]` section
- `.agentic/STATUS.md` v1.8.0 note
- Tag `v1.8.0` → Release workflow