# TASK-203: Migrate billing schema to monthly invoices

## Risk profile

Profile: high-assurance

## Profile rationale

Affects billing and a destructive database migration. Escalated to high-assurance.

## Requirements

- R-1: Invoice data is rekeyed from `billing_events` to `monthly_invoices`.
- R-2: No invoice is lost during migration.

## Risk analysis

Threat: dropping `billing_events` before invoices are verified would lose
financial data. Blast radius: all customers. Mitigations: two-phase migration
with a retained backup table and a verification query comparing row counts and
totals.

## Requirement-to-evidence

| Requirement | Evidence required | Result |
|---|---|---|
| R-1 | Migration integration test | Passed |
| R-2 | Verification query on restored backup | Passed |

## Acceptance criteria

- AC-1: Migration script is idempotent.
- AC-2: Verification query passes on the backup.

## Required evidence

| Criterion | Evidence required | Result |
|---|---|---|
| AC-1 | Idempotency test | Passed |
| AC-2 | Verification query | Passed |

## Negative-path and boundary tests

- Migration against a partially populated schema.
- Zero-invoice customer.

## Integration verification

Staging: migration ran against staging data; verification query passed.

## Approval gates

- [x] Approved by: data-owner@example.com (2026-08-16)
- [x] Signed off: billing-review@example.com (2026-08-16)

## Independent review

Reviewed by a second engineer; confirmed no path drops `billing_events`
before verification.

## Files changed

- `migrations/014_monthly_invoices.sql`
- `internal/billing/migrate.go`

## Verification

### Baseline

`go test ./internal/billing` — 19 passed, 0 failed.

### Final

`go test ./internal/billing` — 22 passed, 0 failed.

## Remaining risks

- None unresolved.