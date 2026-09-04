# TASK-018 — v1.10.0 release publication: skills as a first-class category

## Status

Status: done
Updated: 2026-09-04

## Risk profile

Profile: standard

## Profile rationale

Standard release publication work: annotated tag creation, observing the
release workflow, and supersede bookkeeping. No authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply. The
infrastructure-change module is not triggered: this publishes the framework's
own distribution, not production infrastructure (TASK-016 precedent).

## Acceptance criteria

- AC-1: CI (Full) green on master before tagging — Full Bats (Ubuntu 22.04),
  Full Bats (macOS), Full Pester (Windows), Validator parity, ci-required.
- AC-2: Annotated tag `v1.10.0` created on master `48f7d91` and pushed;
  VERSION/CHANGELOG/tag agreement (`1.10.0` / `[1.10.0] - 2026-09-04`).
- AC-3: Release workflow green on the tagged SHA: metadata validation, full
  CI, bundle build, SHA256SUMS verification, no-leak gate, tar.gz + zip
  extract/install tests, publication as Latest.
- AC-4: Supersede bookkeeping recorded — v1.9.0 marked superseded,
  v1.10.0 release note in STATUS.md.
- AC-5: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | CI (Full) run 33898578777 on master 48f7d91: all five jobs success | passed |
| AC-2 | Annotated tag v1.10.0 pushed (48f7d91); VERSION=1.10.0; CHANGELOG [1.10.0] - 2026-09-04 | passed |
| AC-3 | Release run 33924382932 completed; 3 assets published (tar.gz/zip/SHA256SUMS); gh api releases/latest → v1.10.0 | passed |
| AC-4 | STATUS.md diff: v1.10.0 released note + v1.9.0 superseded | passed |
| AC-5 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- None selected — release bookkeeping records observed CI/release results; no specialist module triggers

## Skills

- release-verification v1 invoked — VERSION/CHANGELOG/tag agreement, bundle publication, and archive integrity confirmed before publication

## Files changed

- .agentic/tasks/TASK-018-v1100-release-publication.md (new)
- .agentic/STATUS.md — v1.10.0 release note; v1.9.0 superseded

## Verification

### Baseline

Pre-publication master 48f7d91: CI (Full) green across all five jobs after the
PR #19 executable-bit fix; VERSION=1.10.0; CHANGELOG [1.10.0] - 2026-09-04.

### Final

- Annotated tag v1.10.0 created on 48f7d91 and pushed; Release workflow
  (run 33924382932) completed with every step green (metadata validation,
  full CI on the tagged SHA, bundle build, SHA256SUMS verification, no-leak
  gate, tar.gz + zip extract/install, publish).
- `gh api repos/tecruz/agentic-workflow/releases/latest` → tag_name v1.10.0;
  published assets: agentic-workflow-1.10.0.tar.gz, agentic-workflow-1.10.0.zip,
  SHA256SUMS; published 2026-09-04T22:36:38Z.
- Handoff gate (bash + pwsh) on this file: VALID.
- git diff --check clean.

## Remaining risks

- None. Next roadmap items remain in Later / ideas (optional-check policy
  review, more agent-tool adapters, large-checks.tsv profiling).
