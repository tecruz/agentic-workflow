# TASK-022 — v1.12.0 release bookkeeping: skills expansion + Nx/Turborepo/Bazel

## Status

Status: done
Updated: 2026-09-07

## Risk profile

Profile: standard

## Profile rationale

Standard release bookkeeping and publication. No authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply.

## Acceptance criteria

- AC-1: CHANGELOG date aligned with publication date (2026-09-07); VERSION=1.12.0.
- AC-2: Annotated tag `v1.12.0` created on the master merge commit and pushed;
  VERSION/CHANGELOG/tag agreement (`1.12.0` / `[1.12.0] - 2026-09-07`).
- AC-3: Release workflow green on the tagged SHA: metadata validation, full
  CI, bundle build, SHA256SUMS verification, no-leak gate, tar.gz + zip
  extract/install tests, publication as Latest.
- AC-4: Supersede bookkeeping recorded — v1.11.0 marked superseded,
  v1.12.0 release note in STATUS.md.
- AC-5: ROADMAP.md version line updated to `1.12.0`.
- AC-6: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | CHANGELOG [1.12.0] - 2026-09-07; VERSION=1.12.0; CHANGELOG date matches tag date | passed |
| AC-2 | Annotated tag v1.12.0 created on adc2912 and pushed; VERSION/CHANGELOG/tag agreement confirmed | passed |
| AC-3 | Release run 34102306954 completed: 7/7 jobs green (Validate metadata, Full Bats macOS+Ubuntu, Full Pester Windows, Validator parity, ci-required, Build & publish); 3 assets published; gh api releases/latest → v1.12.0, published 2026-09-07T09:15:32Z | passed |
| AC-4 | STATUS.md diff: v1.12.0 release note added; v1.11.0 marked superseded | passed |
| AC-5 | ROADMAP.md version line updated to 1.12.0; all later-items landed note updated | passed |
| AC-6 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- None selected — release bookkeeping records observed CI/release results; no specialist module triggers

## Skills

- release-verification v1 invoked — VERSION/CHANGELOG/tag agreement, bundle publication, and archive integrity confirmed before publication

## Files changed

- .agentic/tasks/TASK-022-v1120-release-bookkeeping.md (new)
- CHANGELOG.md — publication date aligned to 2026-09-07
- ROADMAP.md — version line updated to 1.12.0
- .agentic/STATUS.md — v1.12.0 release note; v1.11.0 superseded; ADR-0015 added to Recent Decisions

## Verification

### Baseline

- Pre-publication master `88ec62b` (PR #24 merge): VERSION=1.12.0;
  CHANGELOG `[1.12.0] - 2026-09-07` (matches publication date, no alignment
  commit needed); PR CI green on the branch (7/7 required jobs).
- Annotated tag v1.12.0 created on `adc2912` and pushed to origin.

### Final

- Release workflow run 34102306954: all 7 jobs green (metadata validation,
  Full Bats Ubuntu+macOS, Full Pester Windows, Validator parity,
  ci-required, Build & publish).
- Published assets: agentic-workflow-1.12.0.tar.gz,
  agentic-workflow-1.12.0.zip, SHA256SUMS.
- `gh api repos/tecruz/agentic-workflow/releases/latest` → tag_name v1.12.0;
  published 2026-09-07T09:15:32Z.
- Handoff gate (bash + pwsh) on this file: VALID.
- git diff --check clean.

## Remaining risks

- None. All roadmap items have landed through v1.12.0.
