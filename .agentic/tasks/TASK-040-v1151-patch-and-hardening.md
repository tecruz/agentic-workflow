# TASK-040 — v1.15.1 patch release and release workflow rerun hardening

## Status

Status: done
Updated: 2026-09-14

## Risk profile

Profile: standard

## Profile rationale

Operational and release maintenance work: v1.15.1 patch release (protocol_version sweep to 1.15.1 across emitters, schemas, and evals), release.yml idempotency/rerun hardening, and `validate-handoff.sh` non-interactive stdin redirect hardening (`</dev/null`). No authentication, payments, secrets handling, data migrations, core protocol logic changes, public API compatibility breaks, privacy-regulated data, or safety-critical behavior. Selected context module and invoked skill cover the scope completely.

## Acceptance criteria

- AC-1: VERSION, all protocol_version emitters, schemas, and evals artifacts swept from `1.15.0` to `1.15.1`.
- AC-2: CHANGELOG.md carries a `## [1.15.1] - 2026-09-14` section documenting the portability and handoff-gate fixes.
- AC-3: Release workflow (`.github/workflows/release.yml`) hardened with idempotent-success handling for already-published releases (asset-verification and checksum validation instead of failing mid-workflow).
- AC-4: `validate-handoff.sh` redirects sub-validator stdin from `/dev/null` to prevent non-interactive MSYS/Git Bash batch invocation deadlocks.
- AC-5: All checks in `.agentic/checks.tsv` pass; task file and `.agentic/STATUS.md` entry present; handoff gate validates this task file successfully.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Grep sweep confirms zero remaining unmigrated `1.15.0` protocol_version strings in code, schemas, and evals | passed |
| AC-2 | CHANGELOG.md section verified for format and SemVer correctness | passed |
| AC-3 | Release workflow YAML structure syntactically sound; idempotency check added | passed |
| AC-4 | `validate-handoff.sh` verified with `</dev/null` on all three validator calls | passed |
| AC-5 | `validate-handoff.sh .agentic/tasks/TASK-040-v1151-patch-and-hardening.md` -> VALID | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — release machinery, workflow hardening, and script execution resilience

## Skills

- release-verification v1 invoked — confirming VERSION, CHANGELOG, tag agreement, and release pipeline integrity

## Files changed

- .agentic/VERSION
- CHANGELOG.md
- .github/workflows/release.yml
- .agentic/scripts/validate-handoff.sh
- (all swept files with protocol_version 1.15.0 → 1.15.1)
- .agentic/tasks/TASK-040-v1151-patch-and-hardening.md (new)
- .agentic/STATUS.md

## Verification

### Baseline

- `validate-handoff.sh` hung on Windows non-interactive runs; release.yml failed on dispatch reruns.

### Final

- `validate-handoff.sh .agentic/tasks/TASK-040-v1151-patch-and-hardening.md` -> VALID
- Protocol sweep consistency check passes cleanly on `1.15.1`.

## Remaining risks

- None identified
