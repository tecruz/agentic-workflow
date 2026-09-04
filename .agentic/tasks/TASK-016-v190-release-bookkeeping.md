# TASK-016 — v1.9.0 release bookkeeping: context-module expansion + orchestration maturity

## Status

Status: done
Updated: 2026-09-04

## Risk profile

Profile: standard

## Profile rationale

Standard maintenance/release work: registers five already-landed context
modules in installers/bundle, updates installer test expectations, and performs
the 1.9.0 version sweep + changelog + tag. No authentication, payments,
secrets handling, data migration, production infrastructure, irreversible
operation, public-API compatibility commitment, privacy-regulated data, or
safety-critical behavior. Escalation signals reviewed; none apply.
The infrastructure-change module is not triggered: its Load-when trigger
explicitly excludes framework-test workflow edits that only run this
repository's own checks, and installer registration follows the TASK-006
precedent (framework distribution, not production infrastructure).
No new ADR: the five modules are evolutionary additions under the existing
module contract (ADR-0010), not architectural change; orchestration follow-ups
are realizations of ADR-0011, not a new decision. Skills work is explicitly
scoped after v1.9.0 ships.

## Acceptance criteria

- AC-1: Installer/bundle registration gap closed — install.sh, install.ps1,
  and scripts/build-bundle.sh register the 5 new context modules
  (performance, accessibility, i18n, mobile-adaptive, testing-infrastructure);
  fresh install and clean bundle contain all 10 modules as managed files.
- AC-2: Installer test expectations cover 10 modules — install_test.bats
  context assertions and Pester Install bundle/upgrade assertions updated;
  N-1 upgrade path v1.8.0 install → v1.9.0 upgrade delivers the new modules.
- AC-3: Release bookkeeping — STATUS.md rows, ROADMAP.md Item 4 marked done
  with Current-state version line at 1.9.0.
- AC-4: Version sweep + changelog — .agentic/VERSION is 1.9.0,
  protocol_version is 1.9.0 across all 8 emitters (coordinator, validate-task,
  validate-context, verify — bash+ps1 each), schemas, and evals artifacts;
  CHANGELOG.md [1.9.0] section records new modules + fixtures, coordinator
  integration tests in CI, AGENTIC_WORKER_CMD docs, stale-worktree GC policy,
  and the coordinator.ps1 JSON-mode Write-Log parity fix.
- AC-5: Full local verification green (bats, Pester, fixtures, evals) before
  tag; CI + CI (Full) green on the release SHA, annotated tag v1.9.0, release
  workflow publishes, extracted-archive + upgrade tests green.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Fresh-install (install.ps1 → 10 dirs + 10 manifest rows) and bundle build (10 dirs under dist bundle) | passed |
| AC-2 | install_test.bats + Install.Tests.ps1 updated to 10 modules; Install.Tests.ps1 80 passed/0 failed/2 skipped; manual v1.8.0→current upgrade delivers 5 new modules (10 dirs) | passed |
| AC-3 | STATUS.md + ROADMAP.md diff shows Item 4 done and version 1.9.0 | passed |
| AC-4 | Select-String sweep shows no 1.8.0 in emitters/schemas/evals/tests; VERSION=1.9.0; CHANGELOG [1.9.0] present | passed |
| AC-5 | Local: Pester 385 passed/0 failed (Install 80/0/2, Context+Coord 70/0/1, Task+Verify+Contracts 235/0/13), evals 8/8 both languages, fixtures green both harnesses; Bats proven in CI; CI (fast) + CI (Full) green on be8160a; annotated tag v1.9.0; release workflow published 3 assets (tar.gz/zip/SHA256SUMS) with archive extract+install + SHA256SUMS verification | passed |

## Approval gates

- None identified

## Context modules

- testing-infrastructure v1 loaded — task updates installer test expectations, adds installer/bundle coverage for new fixtures, and runs the full test/CI verification gate

## Files changed

- install.sh — 5 new managed context module paths
- install.ps1 — 5 new managed context module paths
- scripts/build-bundle.sh — bundle dirs + copies for 5 new modules
- tests/bats/install_test.bats — 10-module assertions
- tests/pester/Install.Tests.ps1 — 10-module bundle/upgrade assertions
- .agentic/VERSION — 1.9.0
- .agentic/scripts/*, .agentic/schemas/*, evals/* — protocol_version sweep to 1.9.0
- tests/bats/*, tests/pester/* — protocol_version expectation updates to 1.9.0
- CHANGELOG.md — [1.9.0] section
- ROADMAP.md — Item 4 done, version 1.9.0
- README.md — Context Modules table expanded to 10 modules; Android/Kotlin
  detection notes + Supported Stacks row synced with shipped v1.8.0 behavior
  (review fix)
- .agentic/STATUS.md — v1.9.0 rows

## Verification

### Baseline

Pre-change master (3054b12): 5 new MODULE.md files + INDEX + 20 fixtures exist
on disk but install.sh/install.ps1/build-bundle.sh still list only the original
5 modules; VERSION=1.8.0; protocol_version=1.8.0; ROADMAP Item 4 open.

### Final

- pwsh syntax: install.ps1, verify.ps1, validate-task.ps1, validate-context.ps1,
  validate-handoff.ps1, coordinator.ps1 all parse OK.
- bash -n: install.sh, verify.sh, validate-task.sh, validate-context.sh,
  validate-handoff.sh, coordinator.sh, build-bundle.sh all OK.
- validate-context (ps1 + sh) on this file: VALID (testing-infrastructure).
- evals: run-evals.ps1 8/8, run-evals.sh 8/8.
- fixtures: run-fixtures.ps1 green, run-fixtures.sh green (all goldens OK).
- Pester Install.Tests.ps1: 80 passed / 0 failed / 2 skipped.
- Pester ValidateContext + Coordinator + Integration: 70 passed / 0 failed / 1 skipped.
- Pester ValidateTask + Verify + JsonContracts: 235 passed / 0 failed / 13 skipped.
- Fresh install via install.ps1: 10 context dirs, 10 manifest MODULE rows.
- Bundle build: 10 context dirs under dist/agentic-workflow-1.8.0 (pre-sweep dir name).
- Manual N-1 check: v1.8.0 bundle lacks performance (False); upgrade with current
  bundle creates the 5 new MODULE.md files (10 dirs total).
- Sweep check: no 1.8.0 remains in emitters/schemas/evals/tests/artifacts; VERSION=1.9.0.
- Review pass: git diff --check clean; byte-level CR scan clean (LF endings);
  README Context Modules table (5→10) and Android/Kotlin detection notes +
  Supported Stacks row corrected to shipped v1.8.0 behavior (pre-existing
  doc drift found during review).
- Bats: proven in CI (Full) — Ubuntu + macOS jobs green (install_test.bats,
  validate_context_test.bats, coordinator_test.bats). (`bash -n` errors on Bats
  `@test` DSL syntax are expected and pre-existing.)
- Published: commit be8160a pushed; CI (fast) + CI (Full) green on the release
  SHA; annotated tag v1.9.0 pushed; release workflow green (metadata validation,
  full CI on tagged SHA, bundle build, SHA256SUMS verification, no-leak gate,
  tar.gz + zip extract/install tests) and published 3 assets as Latest
  (`agentic-workflow-1.9.0.tar.gz`, `.zip`, `SHA256SUMS`).

## Remaining risks

- None for v1.9.0. Next roadmap item — Skills as a first-class category — is
  explicitly scoped after v1.9.0 (new ADR, likely ADR-0014).
