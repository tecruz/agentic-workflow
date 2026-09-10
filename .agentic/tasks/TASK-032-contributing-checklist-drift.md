# TASK-032 — CONTRIBUTING.md check-list drift fix

## Status

Status: done
Updated: 2026-09-09

## Risk profile

Profile: standard

## Profile rationale

Documentation-only change to the development repository — no authentication,
payments, secrets handling, data migration, production infrastructure,
irreversible operation, public-API compatibility commitment,
privacy-regulated data, or safety-critical behavior.

## Acceptance criteria

- AC-1: The "Required checks run" list in CONTRIBUTING.md matches the
  authoritative `.agentic/checks.tsv` (14 required checks): eight `bash -n`
  syntax targets, the PowerShell parser check over all `.ps1` twins, the
  handoff-gate self-check, both test suites, and both eval twins.
- AC-2: The stale "requires … node" note is removed (checks.tsv requires
  no node toolchain).
- AC-3: CONTRIBUTING.md points readers at `.agentic/checks.tsv` as the
  authoritative contract.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | CONTRIBUTING.md list rewritten from `.agentic/checks.tsv` contents | passed |
| AC-2 | "requires bash, pwsh, bats" — node requirement dropped | passed |
| AC-3 | "That file is the authoritative contract" sentence added | passed |

## Approval gates

- None identified

## Context modules

- None selected — documentation edit does not trigger any specialist module

## Skills

- None required — prose update, no procedural work

## Files changed

- CONTRIBUTING.md — Local verification section
- .agentic/tasks/TASK-032-contributing-checklist-drift.md (new)

## Verification

### Baseline

CONTRIBUTING.md listed four required checks; `.agentic/checks.tsv` has
fourteen, so new contributors verifying locally would run a subset and
miss syntax gates, the handoff self-check, and the eval twins.

### Final

The Local verification section now mirrors the full check contract,
drops the stale node requirement, and defers to `.agentic/checks.tsv`
as authoritative. No code or behavior changes.

## Remaining risks

- None identified. The section can drift again as checks change; the
  added authoritative-source sentence mitigates by telling readers
  where the truth lives.
