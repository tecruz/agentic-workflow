# TASK-EVAL: data-integrity-change

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: high-assurance

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Requirements

- R-1: The constraint applies without blocking production writes.
- R-2: The repair pass is idempotent and reversible.

## Risk analysis

Threat model: a partial repair run silently corrupting duplicate rows and a lock window starving order writes. Mitigations: staged repair with per-batch checksums, rehearsed down-migration, audit logging of every mutation.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | Concurrent-write probe measured zero failed writes on staging replay | passed |
| R-2 | Repair rerun over the same snapshot produced no additional changes | passed |

## Negative-path and boundary tests

- Insert attempts with duplicate emails are rejected before commit.
- Repair reruns report zero residual duplicates.

## Integration verification

- Staging replay of one million customers exercised the full repair/constraint cycle.

## Recovery plan

- Restore the staging snapshot procedure documented in docs/ops.md; the down-migration is the first-line reversal.
## Approval gates

- [x] AG-1: Approved by Data Owner on 2026-08-24

## Independent review

- Data guild reviewed the constraint and repair plan (PR #16).

## Acceptance criteria

- AC-1: Duplicate emails are repaired before the constraint lands.
- AC-2: The constraint rejects new duplicate inserts.
- AC-3: Every repaired row is captured in the audit log.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | recovery-plan: repair pass rehearsed against staging snapshot | passed |
| AC-2 | integrity-constraint-tests: duplicate-email inserts rejected across 14 cases | passed |
| AC-3 | audit-log-capture: every repaired row logged with before/after values | passed |

## Context modules

- data-integrity v1 loaded — constraint change with a data repair pass

## Skills

- task-decomposition v1 invoked — change broken into constraint, repair, and verify steps

## Verification

### Baseline

- 'dbmate status' clean; duplicate count recorded at 142.

### Final

- Constraint replayed on staging; duplicate count zero; audit log verified; 'dbmate rollback' rehearsed.

## Files changed

- `db/migrations/0043_email_unique.sql`
- `src/data/repair_duplicates.py`

## Remaining risks

- None identified.
