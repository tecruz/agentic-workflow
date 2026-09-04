# Project Status

> High-level index of the adopting project's active state. One file per task
> lives in `.agentic/tasks/`; one file per architectural decision lives in
> `.agentic/decisions/`. This file is a generated-or-maintained summary, not a
> merge-conflict hotspot.

## Active Tasks

- [x] TASK-001 — Installer lifecycle hardening for v1.2.1 (see `.agentic/tasks/TASK-001-v121-lifecycle-hardening.md`)
- [x] v1.2.2 release-integrity hardfix (PR #6): version/changelog/tag agreement,
  reusable CI, extracted-archive and release-to-release upgrade tests, release
  workflow. Released as `v1.2.2`. Superseded by v1.3.0.
- [x] PR #7 & PR #8 — Risk profiles and evidence contracts and v1.3.0 finalization (PR #8): `prototype`/`standard`/
  `high-assurance` profiles, task validators, risk-aware task template, release upgrade tests, and release finalization. Released as `v1.3.0`. Superseded by v1.4.0.
- [x] PR #9 — Versioned JSON result contracts (`v1.4.0`): machine-readable verification and task-validation result contracts, JSON output modes for verifiers and task validators (`--format json` / `-Format Json`), managed JSON schemas (`.agentic/schemas/`), stable diagnostic codes, clean stdout isolation, redaction policy, ADR-0009, and schema compliance tests.
- [x] TASK-004 — PR #9 second-review blocker: Bash `--events-force` rejected directory destinations and stranded the scratch stream (see `.agentic/tasks/TASK-004-bash-events-force-directory.md`)
- [x] TASK-005 — v1.4.0 publication: changelog publication-date alignment (`b4f1248`), annotated `v1.4.0` tag, workflow-built and published assets, and supersede bookkeeping (see `.agentic/tasks/TASK-005-v140-release-publication.md`)
- [x] TASK-006 — PR #10 portable context modules and offline behavioral evaluations (`v1.5.0`): five-module registry under `.agentic/context/`, `validate-context.sh`/`.ps1` with cross-language parity and stable diagnostics, `context-selection-v1` schema, eight-scenario offline eval harness (no LLM/network), installer/bundle/CI registration with `evals/` leak gates, real v1.4.0→v1.5.0 migration test, protocol_version sweep to 1.5.0 (see `.agentic/tasks/TASK-006-context-modules-and-evals.md`)
- [x] TASK-007 — PR #10 review fixes: PowerShell sentinel grammar aligned with the Bash anchored grammar (malformed `None selected-but-not-really` / `None selected because ...` now INVALID in both languages), stale Pester JSON-identifier assertion corrected to the documented redaction contract, missing perl reclassified as BLOCKED with schema-valid code `TOOLING_UNAVAILABLE`, regression fixtures + golden tests added (see `.agentic/tasks/TASK-007-pr10-review-fixes.md`)
- [x] TASK-008 — PR #10 pre-merge polish: final fixture/test/registration counts corrected in TASK-006 and the PR description (42 shared fixtures, 57 Bats cases, 41 Pester cases, 11 registrations); eval harness fence parsing now mirrors the production validator for both ``` and `~~~`; `#Requires -Version 7.0` guard on `run-evals.ps1`; deterministic `[ordered]` JSON in `generate-scenarios.ps1` (see `.agentic/tasks/TASK-008-pr10-polish.md`)
- [x] TASK-009 — ADR-0011 full orchestration (`v1.6.0`): isolated worktrees, generic worker runner, observable JSONL events and versioned result contracts, approval-gated spawning/remote writes, Bash+PowerShell coordinator twins (see `.agentic/tasks/TASK-009-orchestration-full-implementation.md`)
- [x] TASK-010 — CI (Full) repair on the orchestration head: shellcheck findings cleared from install.sh / verify.sh / validate-task.sh; Bats coordinator test 16 redaction patterns include the leading-dot relative `task_file` form; Full Pester (Windows) timeout fixed by skipping the redundant bash-leg context parity on Windows, preferring Git Bash over the WSL launcher, and sizing the job budget to the slowest observed runner image (see `.agentic/tasks/TASK-010-ci-full-repair.md`)
- [x] TASK-011 — v1.6.0 publication: changelog publication-date alignment, annotated tag, workflow release, supersede bookkeeping (see `.agentic/tasks/TASK-011-v160-release-publication.md`)
- [x] TASK-012 — v1.6.1 fix round — bugs + hygiene + CI maintainability (see `.agentic/tasks/TASK-012-maintenance.md`)
- [x] TASK-013 — Draft ROADMAP.md (see `.agentic/tasks/TASK-013-draft-roadmap.md`)
- [x] TASK-014 — Workspace and monorepo detection (v1.7.0): manifest-driven discovery for pnpm-workspace.yaml, package.json workspaces, Cargo workspace, pom.xml modules, settings.gradle include, with Bash+PowerShell parity and 7 new fixtures (see `.agentic/tasks/TASK-014-workspace-monorepo-detection.md`)
- [x] TASK-015 — v1.8.0 release bookkeeping: deeper Android/Kotlin detection (see `.agentic/tasks/TASK-015-v180-release-bookkeeping.md`)
- [x] TASK-016 — v1.9.0 release bookkeeping: context-module expansion + orchestration maturity (see `.agentic/tasks/TASK-016-v190-release-bookkeeping.md`)

## Recent Decisions

- ADR-0006 — Installer lifecycle hardening: read-only plans, confined manifests, proven legacy ownership (see `docs/decisions/ADR-0006-installer-lifecycle-hardening.md`)
- ADR-0007 — Extension versioning policy for future protocol extensions (see `docs/decisions/ADR-0007-extension-versioning.md`)
- ADR-0008 — Risk profiles and evidence contracts (see `docs/decisions/ADR-0008-risk-profiles-and-evidence-contracts.md`)
- ADR-0009 — Machine-readable result contracts (see `docs/decisions/ADR-0009-machine-readable-result-contracts.md`)
- ADR-0010 — Portable context modules and offline behavioral evaluations (see `docs/decisions/ADR-0010-context-modules-and-evaluations.md`)
- ADR-0011 — Isolated multi-agent task coordination (see `docs/decisions/ADR-0011-isolated-multi-agent-task-coordination.md`)
- ADR-0012 — Workspace and monorepo detection (see `docs/decisions/ADR-0012-workspace-monorepo-detection.md`)
- ADR-0013 — Deeper Android and Kotlin detection (see `docs/decisions/ADR-0013-deeper-android-kotlin-detection.md`)

## Notes

- **v1.9.0 — context-module expansion + orchestration maturity** (unreleased, on `master`): five new context modules (`performance`, `accessibility`, `i18n`, `mobile-adaptive`, `testing-infrastructure`) with 20 fixtures, installer/bundle/upgrade registration for all 10 modules; cross-platform coordinator integration tests in CI, `AGENTIC_WORKER_CMD` docs, stale-worktree GC policy, `coordinator.ps1` JSON-mode `Write-Log` parity fix; `protocol_version` sweep to `1.9.0`; `VERSION` bump to `1.9.0`. See `TASK-016`, `CHANGELOG.md` `[1.9.0]`, and `ROADMAP.md` (Items 4 + 5 done; Skills scoped after v1.9.0).

- **v1.8.0 — deeper Android/Kotlin detection** (unreleased, on `master`): root-level detection now interprets version catalogs (`gradle/libs.versions.toml`) and convention plugins (`id("...android...")`); per-module detection scans module build files and manifests without cross-module contamination; two new fixtures/goldens (`android-version-catalog`, `android-convention-plugin`); `protocol_version` sweep to `1.8.0`; `VERSION` bump to `1.8.0`. See `TASK-015`, `ADR-0013`, `CHANGELOG.md` `[1.8.0]`, and `ROADMAP.md`.

- **v1.7.0 — workspace/monorepo detection** (unreleased, on `master`): manifest-driven discovery for `pnpm-workspace.yaml`, `package.json` `workspaces`, `Cargo.toml` `[workspace]`, `pom.xml` `<modules>`, `settings.gradle(.kts)` `include` with `*`/`**`/`!` and deduplication; 7 new fixtures/goldens with Bash+PowerShell parity; `protocol_version` sweep to `1.7.0`; `VERSION` bump to `1.7.0`. See `TASK-014`, `ADR-0012`, `CHANGELOG.md` `[1.7.0]`, and `ROADMAP.md`.

- **v1.6.1 released 2026-08-30** as annotated tag `v1.6.1` on commit `972cfdb` (fix round: coordinator path redaction, double logging, `Trim()` no-op, exit-code alignment, shellcheck/ps-syntax hygiene, `CODE_OF_CONDUCT.md`, `.editorconfig`, `.gitattributes`, `README.md` badge). The v1.6.0 release is marked as superseded.

- **v1.6.0 released 2026-08-29** as annotated tag `v1.6.0` on commit `0f84cb0`
  (the master merge of PR #13). The Release workflow passed: metadata
  validation (VERSION/CHANGELOG/tag agreement), full CI matrix on the tagged
  SHA, bundle build, leak gate, extracted-archive install tests for both
  archives, SHA256SUMS verification, and publication as Latest. Published
  assets (`agentic-workflow-1.6.0.tar.gz`, `.zip`, `SHA256SUMS`). The v1.4.0
  release is marked as superseded (v1.5.0 was never published).
- **v1.4.0 released 2026-08-24** as annotated tag `v1.4.0` on commit `b4f1248`.
  The Release workflow passed: metadata validation (VERSION/CHANGELOG/tag
  agreement), full CI on the tagged SHA, bundle build, extracted-archive tests
  for both archives, SHA256SUMS verification with re-download of uploaded
  assets, and publication as Latest. Published assets
  (`agentic-workflow-1.4.0.tar.gz`, `.zip`, `SHA256SUMS`). The v1.3.0 release
  is marked as superseded. Superseded by v1.6.0.
- **v1.3.0 released 2026-08-21** as annotated tag `v1.3.0`. Introduces risk profiles (`prototype`, `standard`, `high-assurance`), task evidence contracts, structural validators (Bash & PowerShell), and comprehensive release-to-release upgrade testing from v1.2.2. The v1.2.2 release is marked as superseded.
- **v1.2.2 released 2026-08-18** as annotated tag `v1.2.2` on commit `c835edf`.
  The Release workflow passed on Windows, Ubuntu, and macOS: metadata
  validation (VERSION/CHANGELOG/tag agreement), reusable CI, bundle build,
  archive extraction tests, SHA256SUMS verification, and publication. Published
  assets (`agentic-workflow-1.2.2.tar.gz`, `.zip`, `SHA256SUMS`) were
  independently downloaded and verified; both archives install cleanly into an
  empty project and the verifier reports UNSUPPORTED (3) as expected. The
  v1.2.1 release is marked as superseded.
- v1.2.1 lifecycle-hardening + write-confinement work is complete and verified
  locally: `bash -n` OK on `install.sh` and `.agentic/scripts/verify.sh`;
  PowerShell parse OK on `install.ps1` and `.agentic/scripts/verify.ps1`;
  Bats 123 total / 0 failures / 1 CI-only skip (pwsh parity); Pester 106
  passed / 0 failed / 2 platform skips.
- **TASK-003 (PR #9 review blockers) completed 2026-08-24**: all 4 merge blockers fixed (optional-failure PASS schema validity, nested cwd labels, task-path redaction, format validation), schema updated to 1.4.0 with `optional_failed` and PASS invariant, tests added (Bats + Pester), docs updated (README, CHANGELOG, ADR-0009). Ready for CI gate.
- **TASK-004 (PR #9 second-review blocker) completed 2026-08-24**: Bash `--events-force` now rejects existing non-regular event destinations before promotion, verifies a regular destination file after forced promotion, and clears `EVENTS_SCRATCH`; Bats regression test added (55/55 local). Fast CI + CI (Full) required on the resulting SHA.
- Adopters: replace the placeholders above with links to real task and decision
  files as they are created. Keep this file brief; the per-task and per-decision
  files hold the detail.
