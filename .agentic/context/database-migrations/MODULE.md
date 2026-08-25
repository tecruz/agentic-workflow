# Module: database-migrations

## ID

database-migrations

## Version

1

## Minimum risk profile

high-assurance

## Load when

- Schema changes (tables, columns, indexes, constraints)
- New, edited, or reordered migration files
- Backfills or bulk data transformations
- Destructive data operations (drops, truncations, type narrowing)

## Required context

- Current schema state and migration history
- Migration tooling and how reversibility is expressed in this project
- Data-volume estimates for affected tables
- Backup and restore procedures that apply to the target environment

## Approval gates

- Explicit approval required before destructive operations on existing data

## Required evidence

- Forward migration applied against a representative local dataset
- Recovery plan: tested down/rollback path or a documented forward-fix strategy
- Verification query or check proving post-migration data integrity

## Prohibited shortcuts

- Do not edit an already-applied migration in place
- Do not run destructive statements without a recorded recovery plan
- Do not skip rehearsal of the migration against realistic data volumes
