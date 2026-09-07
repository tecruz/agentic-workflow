# TASK-023 — v1.12.1 release bookkeeping: post-v1.12.0 audit fixes

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

- AC-1: CHANGELOG date aligned with publication date (2026-09-07); VERSION=1.12.1.
- AC-2: Annotated tag `v1.12.1` created on the master merge commit and pushed;
  VERSION/CHANGELOG/tag agreement (`1.12.1` / `[1.12.1] - 2026-09-07`).
- AC-3: Release workflow green on the tagged SHA: metadata validation, full
  CI, bundle build, SHA256SUMS verification, no-leak gate, tar.gz + zip
  extract/install tests, publication as Latest.
- AC-4: Supersede bookkeeping recorded — v1.12.0 marked superseded,
  v1.12.1 release note in STATUS.md.
- AC-5: ROADMAP.md version line updated to `1.12.1`.
- AC-6: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | CHANGELOG [1.12.1] - 2026-09-07; VERSION=1.12.1; CHANGELOG date matches tag date | passed |
| AC-2 | Annotated tag v1.12.1 created and pushed; VERSION/CHANGELOG/tag agreement confirmed | passed |
| AC-3 | Release run 34129764990 completed: 7/7 jobs green (Validate metadata, Full Bats macOS+Ubuntu, Full Pester Windows, Validator parity, ci-required, Build & publish); 3 assets published; gh api releases/latest → v1.12.1, published 2026-09-07T14:20:27Z | passed |
| AC-4 | STATUS.md diff: v1.12.1 release note added; v1.12.0 marked superseded | passed |
| AC-5 | ROADMAP.md version line updated to 1.12.1 | passed |
| AC-6 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- None selected — release bookkeeping records observed CI/release results; no specialist module triggers

## Skills

- release-verification v1 invoked — VERSION/CHANGELOG/tag agreement, bundle publication, and archive integrity confirmed before publication

## Files changed

- .agentic/tasks/TASK-023-v1121-release-bookkeeping.md (new)
- CHANGELOG.md — [1.12.1] section added (Nx parity, turbo fixture, CRLF, harness stderr, CI sweep gate)
- ROADMAP.md — version line updated to 1.12.1
- .agentic/STATUS.md — v1.12.1 release note; v1.12.0 marked superseded
- .agentic/VERSION — bumped to 1.12.1
- All protocol_version sites swept 1.12.0 → 1.12.1 (32 files: scripts, schemas, orchestration, evals, tests)
