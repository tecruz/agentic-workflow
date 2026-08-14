# ADR-0002 — Honest verification state model (PASS/FAIL/BLOCKED/UNSUPPORTED)

- **Date**: 2026-08-13
- **Status**: Accepted
- **Deciders**: maintainers, review of `feedback.md`

## Context

The original verifiers reported `PASS` even when a required check could not
run (tooling missing), which is a false success: an agent would stop believing
work was verified. Review feedback (§1 "truthful verification") required
that a required check that is blocked must never yield `PASS`.

## Decision

- Exit codes and semantics:
  - `0` **PASS** — at least one required check ran and all passed.
  - `1` **FAIL** — a required check ran and failed.
  - `2` **BLOCKED** — project/checks found, but required tooling or check
    configuration is unavailable.
  - `3` **UNSUPPORTED** — no supported project or check configuration found.
- Invariant: `PASS` is impossible unless at least one required check actually
  ran. A blocked required check always reports `BLOCKED`, never `PASS`.
- Classification priority: `FAIL` > `BLOCKED` > `PASS` > `UNSUPPORTED`.
- `.agentic/checks.tsv` is the authoritative check list when it defines at
  least one check line; auto-detection is only a bootstrap fallback.
  `--emit-checks` prints the detected stack as TSV for the installer.
- `optional` checks run when tooling is available but never fail a run.

## Consequences

- Verifier output is trustworthy; agents can rely on exit code 0.
- Added complexity in classification logic and per-check bookkeeping
  (`REQUIRED_RAN`, `FAILED`, `BLOCKED` flags), covered by fixture tests and a
  dedicated CI job (see ADR/tests).
- `verify.sh` and `verify.ps1` behave identically and are kept in sync.