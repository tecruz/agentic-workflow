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
| AC-1 | CHANGELOG [1.12.0] - 2026-09-07; VERSION=1.12.0 | pending |
| AC-2 | Annotated tag v1.12.0 created on 88ec62b; pushed to origin | pending |
| AC-3 | Release workflow run on tagged SHA; 3 assets published | pending |
| AC-4 | STATUS.md diff: v1.12.0 release note; v1.11.0 superseded | pending |
| AC-5 | ROADMAP.md version line = 1.12.0 | pending |
| AC-6 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | pending |

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
- .agentic/STATUS.md — v1.12.0 release note; v1.11.0 superseded

## Verification

### Baseline

- Pre-publication master `88ec62b` (PR #24 merge): VERSION=1.12.0;
  CHANGELOG `[1.12.0] - 2026-09-07` (matches publication date, no alignment
  commit needed); PR CI green on the branch (7/7 required jobs).
- CI (Full) dispatched on master; tag gated on its result.

### Final

- Annotated tag v1.12.0 created on 88ec62b and pushed; release workflow
  run on tagged SHA: every step green (metadata validation, full CI on
  tagged SHA, bundle build, SHA256SUMS verification, no-leak gate,
  tar.gz + zip extract/install, publish).
- `gh api repos/tecruz/agentic-workflow/releases/latest` → tag_name v1.12.0;
  published assets: agentic-workflow-1.12.0.tar.gz, agentic-workflow-1.12.0.zip,
  SHA256SUMS.
- Handoff gate (bash + pwsh) on this file: VALID.
- git diff --check clean.

## Remaining risks

- None. All roadmap items have landed through v1.12.0.
