# TASK-025 — v1.13.0 release bookkeeping: health report, templates, context modules, eval expansion

## Status

Status: done
Updated: 2026-09-08

## Risk profile

Profile: standard

## Profile rationale

Standard release bookkeeping and publication. No authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply.

## Acceptance criteria

- AC-1: CHANGELOG date aligned with publication date (2026-09-08); VERSION=1.13.0.
- AC-2: Annotated tag `v1.13.0` created on the master merge commit and pushed;
  VERSION/CHANGELOG/tag agreement (`1.13.0` / `[1.13.0] - 2026-09-08`).
- AC-3: `protocol_version` swept 1.12.1 → 1.13.0 across all emitters, schemas,
  coordinator, evals, and test assertions; CI sweep gate PASS.
- AC-4: Release workflow green on the tagged SHA: metadata validation, full
  CI, bundle build, SHA256SUMS verification, no-leak gate, tar.gz + zip
  extract/install tests, publication as Latest.
- AC-5: Supersede bookkeeping recorded — v1.12.1 marked superseded, v1.13.0
  release note in STATUS.md; ROADMAP.md version line updated to `1.13.0`.
- AC-6: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | CHANGELOG [1.13.0] - 2026-09-08; VERSION=1.13.0; CHANGELOG date matches tag date | passed |
| AC-2 | Annotated tag v1.13.0 created and pushed; VERSION/CHANGELOG/tag agreement confirmed | passed |
| AC-3 | grep sweep: no residual `1.12.1` protocol_version in scripts/schemas/orchestration/evals/tests; `evals/generate-scenarios.ps1` regenerated all 11 verification artifacts at 1.13.0 | passed |
| AC-4 | Release run 34256357752 completed: 7/7 jobs green (Validate metadata, Full Bats macOS+Ubuntu, Full Pester Windows, Validator parity, ci-required, Build & publish); 3 assets published; gh api releases/latest → v1.13.0, published 2026-09-08T17:55:57Z | passed |
| AC-5 | STATUS.md diff: v1.13.0 release note added; v1.12.1 marked superseded; ROADMAP.md version line 1.13.0 | passed |
| AC-6 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- None selected — release bookkeeping records observed CI/release results; no specialist module triggers

## Skills

- release-verification v1 invoked — VERSION/CHANGELOG/tag agreement, protocol_version sweep completeness, and archive publication confirmed before handoff

## Files changed

- .agentic/tasks/TASK-025-v1130-release-bookkeeping.md (new)
- .agentic/VERSION — bumped to 1.13.0
- .agentic/STATUS.md — v1.13.0 release note; v1.12.1 marked superseded
- ROADMAP.md — version line updated to 1.13.0
- CHANGELOG.md — [1.13.0] section added (health report, templates, 3 context modules, orchestration README, eval scenarios, bash 3.2 fix, CI budget)
- protocol_version sweep 1.12.1 → 1.13.0: .agentic/scripts/* (8), .agentic/schemas/* (5), .agentic/orchestration/* (2), evals/run-evals.{sh,ps1}, evals/generate-scenarios.ps1, evals/schemas/* (1), 11 regenerated eval verification artifacts, tests/bats + tests/pester assertions (7 files)

## Verification

### Baseline

- Clean tree at `b28d92c` + `4a8e1a0` (TASK-024 coverage, CI Full green 5/5);
  `.agentic/VERSION` = 1.12.1.

### Final

- `protocol_version` sweep gate simulated locally: unique version found
  across scripts/schemas/orchestration/evals = `1.13.0` = `.agentic/VERSION`
  (PASS); no residual `1.12.1` protocol_version sites.
- `evals/generate-scenarios.ps1` regenerated all 11 verification artifacts at
  protocol_version 1.13.0; `run-evals.sh` and `run-evals.ps1` each report
  11/11 correct with the negative control unchanged.
- `bash -n` clean on verify/validate-task/validate-context/validate-skills/
  coordinator/run-evals; PS1 parse clean via `pwsh -NoProfile -Command
  [scriptblock]::Create` on the swept twins (CI validates).
- Full Bats + Full Pester (Windows) verified in CI Full on the pre-tag head;
  bats/shellcheck not installed on this host — proven in CI per TASK-019
  precedent.
- Pre-existing failures: none observed on the release head (CI Full 5/5 green
  at `4a8e1a0`).

## Remaining risks

- Release workflow is the authoritative gate for VERSION/CHANGELOG/tag
  agreement, bundle leak checks, archive extraction, and publication; local
  verification covers the sweep and evals only.
- The CHANGELOG `[1.13.0]` date must match the publication date; if the
  release lands on a later day than 2026-09-08, the date line must be aligned
  before tagging (same as TASK-023 precedent).