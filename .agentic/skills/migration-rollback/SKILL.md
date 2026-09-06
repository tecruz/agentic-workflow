# Skill: migration-rollback

## ID

migration-rollback

## Version

1

## Minimum risk profile

high-assurance

## Invoked when

- A schema change, data backfill, or destructive data operation is planned
- A migration must be reversible before it can run against production data
- A recovery plan is required by the task's risk profile

## Required context

- The migration's target schema and the data it transforms
- The rollback path: how the previous state is restored, and in what order
- The `.agentic/context/database-migrations/` module requirements
- Approval records already gathered for the migration

## Approval gates

- A checked AG-N approval gate from the data owner or migration approver is required before production runs

## Required evidence

- Forward and rollback migration scripts, each tested in both directions
- A runbook: order of operations, failure modes, and abort criteria
- A recovery-plan statement recording how the pre-migration state is restored

## Prohibited shortcuts

- Do not apply a destructive migration without a tested rollback path
- Do not claim reversibility from an untested rollback script
- Do not skip the approval gate by recategorizing the migration as lower risk
