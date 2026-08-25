# TASK-EVAL: database-migration

## Status

Status: done
Updated: 2026-08-24

## Risk profile

Profile: high-assurance

## Profile rationale

Fixture artifact for the behavioral evaluation harness.

## Requirements

- R-1: Index creation completes without blocking production writes.
- R-2: The migration reverses cleanly.

## Risk analysis

Threat model: long lock windows starving order writes and an unrecoverable partial build. Mitigations: concurrent index build, staged rollout, rehearsed down-migration against a staging snapshot.

## Requirement-to-evidence

| Requirement ID | Evidence | Result |
| --- | --- | --- |
| R-1 | Concurrent-write probe measured zero failed writes on staging replay | passed |
| R-2 | Down-migration rehearsal restored the pre-migration schema snapshot | passed |

## Negative-path and boundary tests

- Migration aborts cleanly when the lock timeout elapses.
- Down-migration removes the index without touching order rows.

## Integration verification

- Staging replay of one million orders exercised the full up/down cycle.

## Recovery plan

- Restore the staging snapshot procedure documented in docs/ops.md; the down-migration is the first-line reversal.
## Approval gates

- [x] AG-1: Approved by Data Recovery Owner on 2026-08-24

## Independent review

- Database guild reviewed the migration plan (PR #13).

## Acceptance criteria

- AC-1: The migration reverses cleanly when rehearsed.
- AC-2: The orders index exists without blocking concurrent writes.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | recovery-plan: down-migration rehearsed against staging snapshot | passed |
| AC-2 | concurrent-write probe holds zero failed writes during the index build | passed |

## Context modules

- database-migrations v1 loaded — schema change with backfill implications

## Verification

### Baseline

- 'dbmate status' clean; row count checksum recorded.

### Final

- Index build replayed on staging; checksum unchanged; 'dbmate rollback' verified.

## Files changed

- `db/migrations/0042_orders_index.sql`

## Remaining risks

- None identified.
