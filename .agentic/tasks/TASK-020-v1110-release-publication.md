# TASK-020 — v1.11.0 release publication: adapters + verifier performance

## Status

Status: done
Updated: 2026-09-05

## Risk profile

Profile: standard

## Profile rationale

Standard release publication work: annotated tag creation, observing the
release workflow, and supersede bookkeeping. No authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply. The
infrastructure-change module is not triggered: this publishes the framework's
own distribution, not production infrastructure (TASK-016/TASK-018 precedent).

## Acceptance criteria

- AC-1: CI (Full) green on master before tagging — Full Bats (Ubuntu 22.04),
  Full Bats (macOS), Full Pester (Windows), Validator parity, ci-required.
- AC-2: Annotated tag `v1.11.0` created on the master merge commit and pushed;
  VERSION/CHANGELOG/tag agreement (`1.11.0` / `[1.11.0] - 2026-09-05`).
- AC-3: Release workflow green on the tagged SHA: metadata validation, full
  CI, bundle build, SHA256SUMS verification, no-leak gate, tar.gz + zip
  extract/install tests, publication as Latest.
- AC-4: Supersede bookkeeping recorded — v1.10.0 marked superseded,
  v1.11.0 release note in STATUS.md.
- AC-5: Handoff gate VALID on this task file (three legs).

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | CI (Full) run 33985843661 on master 2fa065a: all four jobs + aggregator success (after repair cycle 1 via PR #21, proven on run 33983895929) | passed |
| AC-2 | Annotated tag v1.11.0 pushed (2fa065a); VERSION=1.11.0; CHANGELOG [1.11.0] - 2026-09-05 | passed |
| AC-3 | Release run 33989410376 completed (after repair cycle 2 via PR #22); 3 assets published (tar.gz/zip/SHA256SUMS); gh api releases/latest → v1.11.0, published 2026-09-05T20:31:18Z | passed |
| AC-4 | STATUS.md diff: v1.11.0 released note + v1.10.0 superseded | passed |
| AC-5 | validate-handoff.sh/.ps1 on this file: VALID (three legs) | passed |

## Approval gates

- None identified

## Context modules

- None selected — release bookkeeping records observed CI/release results; no specialist module triggers

## Skills

- release-verification v1 invoked — VERSION/CHANGELOG/tag agreement, bundle publication, and archive integrity confirmed before publication

## Files changed

- .agentic/tasks/TASK-020-v1110-release-publication.md (new)
- .agentic/STATUS.md — v1.11.0 release note; v1.10.0 superseded

## Verification

### Baseline

- Pre-publication master `3c095c1` (PR #20 merge): VERSION=1.11.0;
  CHANGELOG `[1.11.0] - 2026-09-05` (matches publication date, no alignment
  commit needed); PR CI green on the branch (7/7 required jobs).
- CI (Full) dispatched on master as run 33982620296; tag gated on its result.
- Repair cycle 1: Bats Ubuntu+macOS failed ONLY on release-archive leak tests
  120/121 (missed `.github`→`.github/workflows` scoping in PR #20); fixed via
  PR #21 (merged as `2fa065a`); proven by CI (Full) run 33983895929 on the fix
  branch (all 4 jobs + aggregator success).
- CI (Full) re-dispatched on post-merge master as run 33985843661; tag gated
  on its result.
- Repair cycle 2: first publish attempt (run 33987399382) passed metadata +
  full CI on the tagged SHA but failed at release.yml's own inline leak gate
  (bare `.github`); fixed via PR #22 (merged as `5d96ea2`); nothing was
  published (latest remained v1.10.0).
- Release re-dispatched via workflow_dispatch for existing tag v1.11.0 as run
  33989410376 (definition from fixed master, build from tag tree).

### Final

- Annotated tag v1.11.0 created on 2fa065a and pushed; first publish attempt
  (run 33987399382) passed metadata + full CI on the tagged SHA but failed at
  release.yml's own inline leak gate (bare `.github`; repair cycle 2, PR #22
  merged as `5d96ea2`, nothing published).
- Release re-dispatched for the existing tag (run 33989410376): every step
  green (metadata validation, full CI on tagged SHA, bundle build,
  SHA256SUMS verification, no-leak gate, tar.gz + zip extract/install,
  publish).
- `gh api repos/tecruz/agentic-workflow/releases/latest` → tag_name v1.11.0;
  published assets: agentic-workflow-1.11.0.tar.gz, agentic-workflow-1.11.0.zip,
  SHA256SUMS; published 2026-09-05T20:31:18Z.
- Handoff gate (bash + pwsh) on this file: VALID.
- git diff --check clean.

## Remaining risks

- None. The roadmap's Later / ideas list now retains only the optional-check
  policy review; all other items are done through v1.11.0.
