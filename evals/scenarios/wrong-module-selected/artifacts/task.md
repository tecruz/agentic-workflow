# TASK-EVAL: wrong-module-selected

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: high-assurance

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Requirements

- R-1: The lookup table enforces per-row authorization boundaries.

## Risk analysis

Threat model: authorization checks skipped on direct table access. Mitigations: row-level access enforced at query time and boundary tests on both sides of the matrix.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | Row-level access matrix exercised across all roles | passed |

## Negative-path and boundary tests

- Direct reads below the required role are refused.

## Integration verification

- The lookup table is wired into the authorization path end-to-end.

## Recovery plan

- Down-migration drops the index without removing the table; rollback restores the prior authorization flow.
## Approval gates

- [x] AG-1: Approved by Security on 2026-08-24

## Independent review

- Security reviewer signed off on the authorization change (PR #18).

## Acceptance criteria

- AC-1: Unauthorized access is rejected by the new lookup path.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | authorization-boundary-tests: row-level access matrix covered | passed |

## Context modules

- database-migrations v1 loaded — schema change introduces a new authorization lookup index

## Skills

- verification-triage v1 invoked — boundary-test results triaged before migration sign-off

## Verification

### Baseline

- 'npm test -- --run' → 80 passed, 0 failed before the lookup.

### Final

- 'npm test -- --run' → 83 passed, 0 failed after the lookup landed.

## Files changed

- `db/migrations/0050_session_auth_index.sql`

## Remaining risks

- None identified.
