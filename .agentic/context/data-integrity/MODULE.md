# Module: data-integrity

## ID

data-integrity

## Version

1

## Minimum risk profile

high-assurance

## Load when

- Data validation logic changes
- Schema constraints modified or added
- Transaction boundaries altered
- Backup or recovery procedures changed
- Audit logging for data operations modified
- Data repair or migration scripts introduced
- Referential integrity constraints changed

## Required context

- Current data validation rules and where they are enforced
- Transaction isolation levels and boundary definitions
- Backup schedules, retention policies, and restore procedures
- Audit log format and ingestion pipeline
- Known data quality issues and their remediation history
- Schema versioning strategy and migration tooling

## Approval gates

- Data migration plans require review before execution
- Changes to transaction boundaries require sign-off from data owner
- Backup/restore procedure changes require verified runbook update

## Required evidence

- Integrity constraint tests covering valid and invalid data
- Negative-path data tests confirming rejection of malformed input
- Backup and restore verification demonstrating recoverability
- Migration rollback tests proving reversibility
- Audit log entry tests verifying complete capture of data mutations

## Prohibited shortcuts

- Do not skip negative-path tests for data validation changes
- Do not modify transaction boundaries without integration-level verification
- Do not merge backup/restore changes without a successful restore test
- Do not bypass audit logging requirements for convenience
