# Project Status

> High-level index of the adopting project's active state. One file per task
> lives in `.agentic/tasks/`; one file per architectural decision lives in
> `.agentic/decisions/`. This file is a generated-or-maintained summary, not a
> merge-conflict hotspot.

## Active Tasks

- [x] TASK-001 — Installer lifecycle hardening for v1.2.1 (see `.agentic/tasks/TASK-001-v121-lifecycle-hardening.md`)
- [x] v1.2.2 release-integrity hardfix (PR #6): version/changelog/tag agreement,
  reusable CI, extracted-archive and release-to-release upgrade tests, release
  workflow. Released as `v1.2.2`.
- [ ] PR #7 — Risk profiles and evidence contracts: `prototype`/`standard`/
  `high-assurance` profiles, a risk-aware task template, structural task
  validators (Bash + PowerShell), lifecycle risk-classification step, and
  managed-file registration in the installers and bundle.
  See `.agentic/tasks/TASK-002-risk-profiles-and-evidence-contracts.md`.

## Recent Decisions

- ADR-0006 — Installer lifecycle hardening: read-only plans, confined manifests, proven legacy ownership (see `docs/decisions/ADR-0006-installer-lifecycle-hardening.md`)
- ADR-0007 — Extension versioning policy for future protocol extensions (see `docs/decisions/ADR-0007-extension-versioning.md`)
- ADR-0008 — Risk profiles and evidence contracts (see `docs/decisions/ADR-0008-risk-profiles-and-evidence-contracts.md`)

## Notes

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
- Adopters: replace the placeholders above with links to real task and decision
  files as they are created. Keep this file brief; the per-task and per-decision
  files hold the detail.
