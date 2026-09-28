# TASK-FX: waived-gates-duplicate

## Status

Status: done
Updated: 2026-09-27

## Risk profile

Profile: standard

## Profile rationale

Standard product work; fixture for the optional `## Waived gates` section.

## Acceptance criteria

- AC-1: The scenario behaves as described.

## Required evidence

| AC ID | Evidence | Result |
| --- | --- | --- |
| AC-1 | Unit test `scenario_test.go` | Passed |
## Approval gates

- [x] AG-1: Approved by alice@example.com on 2026-09-20

## Waived gates

- WG-1: First check - waived by bob@example.com on 2026-09-21 - reason one
- WG-1: Second check - waived by carol@example.com on 2026-09-22 - reason two
## Verification

### Baseline

- `go test ./...` → 10 passed, 0 failed.

### Final

- `go test ./...` → 11 passed, 0 failed.
## Files changed

- `internal/scenario/scenario.go`
## Remaining risks

- None identified.