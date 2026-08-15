# Project Status

> High-level index of the adopting project's active state. One file per task
> lives in `.agentic/tasks/`; one file per architectural decision lives in
> `.agentic/decisions/`. This file is a generated-or-maintained summary, not a
> merge-conflict hotspot.

## Active Tasks

- [x] TASK-001 — Installer lifecycle hardening for v1.2.1 (see `.agentic/tasks/TASK-001-v121-lifecycle-hardening.md`)

## Recent Decisions

- ADR-0006 — Installer lifecycle hardening: read-only plans, confined manifests, proven legacy ownership (see `docs/decisions/ADR-0006-installer-lifecycle-hardening.md`)

## Notes

- v1.2.1 lifecycle-hardening work is complete and verified locally:
  `bash -n` OK; PowerShell parse OK; Bats 105 total / 0 failures / 1 CI-only
  skip; Pester 91/91. Bundle `dist/agentic-workflow-1.2.1/` rebuilt and
  `sha256sum -c` clean. No tag, push, or release without explicit approval.
- Adopters: replace the placeholders above with links to real task and decision
  files as they are created. Keep this file brief; the per-task and per-decision
  files hold the detail.
