# TASK-EVAL: dependency-upgrade

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Approval gates

- None identified

## Acceptance criteria

- AC-1: The suite is green on the upgraded lockfile.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | build-and-test-passing: full suite green on the updated lockfile | passed |

## Context modules

- dependency-changes v1 loaded — lockfile-changing upgrade reviewed for transitive drift

## Verification

### Baseline

- 'npm ci && npm test' → 210 passed, 0 failed on the previous lockfile.

### Final

- 'npm ci && npm test' → 210 passed, 0 failed on the upgraded lockfile.

## Files changed

- `package.json`
- `package-lock.json`

## Remaining risks

- None identified.
