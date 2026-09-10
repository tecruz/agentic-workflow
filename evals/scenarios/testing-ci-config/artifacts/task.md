# TASK-EVAL: testing-ci-config

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: standard

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Approval gates

- [x] AG-1: Approved by CI Lead on 2026-08-24

## Acceptance criteria

- AC-1: CI test wall-clock time reduced by at least 30%.
- AC-2: Coverage report shows no regression below the raised threshold.
- AC-3: Sharded and non-sharded runs produce identical pass/fail results.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | ci-pipeline-comparison: wall-clock reduced from 12 min to 8 min | passed |
| AC-2 | coverage-report: line coverage held at 84% above the raised 82% threshold | passed |
| AC-3 | shard-parity: sharded and non-sharded runs produce identical results | passed |

## Context modules

- testing-infrastructure v1 loaded — shard parallelization and coverage threshold raised

## Skills

- verification-triage v1 invoked — pipeline comparison triaged before merge

## Verification

### Baseline

- CI test wall-clock at 12 min; coverage threshold at 78%; no sharding.

### Final

- CI test wall-clock at 8 min; coverage threshold raised to 82%; 4 shards.

## Files changed

- `jest.config.js`
- `.github/workflows/ci.yml`

## Remaining risks

- None identified.
